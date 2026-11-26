//! GPU grid renderer: one instanced quad per background, glyph and decoration.
use crate::anim::ScrollAnim;
use crate::grid::{Cell, CursorShape, Grid};
use bytemuck::{Pod, Zeroable};
use std::collections::HashMap;
use std::sync::Arc;
use winit::window::Window;

const ATLAS: u32 = 2048;
const PADDING: f32 = 6.0;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Instance {
    pos: [f32; 2],
    size: [f32; 2],
    uv: [f32; 4],
    color: [f32; 4],
    /// The color under a glyph, so its edges blend in linear light like kitty's.
    bg: [f32; 4],
    glyph: f32,
}

#[derive(Clone, Copy)]
struct Glyph {
    uv: [f32; 4],
    size: [f32; 2],
    offset: [f32; 2],
}

/// Shelf packer for rasterized glyphs.
#[derive(Default)]
struct Atlas {
    glyphs: HashMap<(char, u8), Option<Glyph>>,
    x: u32,
    y: u32,
    shelf: u32,
}

impl Atlas {
    fn place(&mut self, w: u32, h: u32) -> Option<(u32, u32)> {
        if self.x + w + 1 > ATLAS {
            self.x = 0;
            self.y += self.shelf + 1;
            self.shelf = 0;
        }
        if self.y + h + 1 > ATLAS {
            return None;
        }
        let spot = (self.x, self.y);
        self.x += w + 1;
        self.shelf = self.shelf.max(h);
        Some(spot)
    }
}

fn rgba(c: u32) -> [f32; 4] {
    [
        ((c >> 16) & 255) as f32 / 255.0,
        ((c >> 8) & 255) as f32 / 255.0,
        (c & 255) as f32 / 255.0,
        1.0,
    ]
}

/// Every font detail the window draws with: `guifont` plus Neovim's 'linespace'.
#[derive(Clone, Debug, PartialEq)]
pub struct Font {
    pub families: Vec<String>,
    pub points: f32,
    pub weight: u16,
    pub bold: u16,
    /// Extra pixels between letters (`guifont` `:c`) and between lines ('linespace').
    pub letter: f32,
    pub line: f32,
}

impl Default for Font {
    /// Until `guifont` arrives: the same font `lazycode/font.lua` asks for.
    fn default() -> Self {
        Font {
            families: vec![
                "FiraCode Nerd Font Mono".into(),
                "JetBrainsMono Nerd Font Mono".into(),
            ],
            points: 13.0,
            weight: 550,
            bold: 700,
            letter: 0.0,
            line: 0.0,
        }
    }
}

/// A `guifont` like `Fira Code,Hack:h14:w600:W800:c1`: families in order, size, weight, bold
/// weight and letter spacing. Missing parts keep their defaults, and underscores stand for spaces
/// as other Neovim GUIs accept.
pub fn parse_guifont(value: &str) -> Font {
    let mut font = Font::default();
    let mut parts = value.split(':');
    let families: Vec<String> = parts
        .next()
        .unwrap_or_default()
        .split(',')
        .map(|f| f.trim().replace('_', " "))
        .filter(|f| !f.is_empty())
        .collect();
    if !families.is_empty() {
        font.families = families;
    }
    let options: Vec<&str> = parts.collect();
    let number = |prefix: char, range: std::ops::RangeInclusive<f32>| {
        options
            .iter()
            .filter_map(|p| p.strip_prefix(prefix)?.parse::<f32>().ok())
            .find(|v| range.contains(v))
    };
    font.points = number('h', 4.0..=96.0).unwrap_or(font.points);
    font.weight = number('w', 100.0..=900.0).map_or(font.weight, |w| w as u16);
    font.bold = number('W', 100.0..=900.0).map_or(font.bold, |w| w as u16);
    font.letter = number('c', -5.0..=20.0).unwrap_or(font.letter);
    font
}

/// Nerd Font icons live in the Private Use Areas.
fn is_icon(c: char) -> bool {
    matches!(c, '\u{e000}'..='\u{f8ff}' | '\u{f0000}'..='\u{ffffd}')
}

/// Scale that makes a `w`×`h` glyph fill a `box_w`×`box_h` box without distortion.
fn fit(w: f32, h: f32, box_w: f32, box_h: f32) -> f32 {
    (box_w / w.max(1.0)).min(box_h / h.max(1.0))
}

/// Font size, baseline, padding and cell size in physical pixels for a display scale.
/// Letter and line spacing widen the cell, and the text sits in its middle.
fn metrics(
    font: &fontdue::Font,
    spec: &Font,
    scale: f32,
) -> Result<(f32, f32, f32, (f32, f32)), String> {
    let px = (spec.points * 96.0 / 72.0 * scale).round();
    let (letter, line) = ((spec.letter * scale).round(), (spec.line * scale).round());
    let metrics = font
        .horizontal_line_metrics(px)
        .ok_or("The font has no line metrics.")?;
    let cell = (
        (font.metrics('M', px).advance_width.round() + letter).max(1.0),
        ((metrics.ascent - metrics.descent + metrics.line_gap).round() + line).max(1.0),
    );
    let baseline = metrics.ascent.round() + (line / 2.0).round();
    Ok((px, baseline, (PADDING * scale).round(), cell))
}

/// Regular, bold, italic and bold italic, indexed by `bold | italic << 1`, then the
/// Nerd Font symbols that the installer pins for icons the main font lacks.
fn load_fonts(
    names: &[String],
    weight: u16,
    bold: u16,
) -> Result<([fontdue::Font; 4], Option<fontdue::Font>), String> {
    use fontdb::{Family, Query, Style, Weight};
    let mut db = fontdb::Database::new();
    db.load_system_fonts();
    if let Some(dir) = std::env::var_os("LAZYCODE_FONT_DIR") {
        db.load_fonts_dir(dir);
    }
    // The text fonts the installer pins, so `lazycode/font.lua` finds them on every machine.
    if let Some(dirs) = crate::nvim::runtime().and_then(|r| std::fs::read_dir(r).ok()) {
        for dir in dirs.flatten() {
            if dir.file_name().to_string_lossy().starts_with("font-") {
                db.load_fonts_dir(dir.path());
            }
        }
    }
    let mut families: Vec<Family> = names.iter().map(|n| Family::Name(n)).collect();
    families.extend([Family::Name("JetBrains Mono"), Family::Monospace]);
    let load = |weight, style| -> Result<fontdue::Font, String> {
        let id = db
            .query(&Query {
                families: &families,
                weight,
                style,
                ..Query::default()
            })
            .ok_or("No monospace font found.")?;
        db.with_face_data(id, |data, index| {
            let settings = fontdue::FontSettings {
                collection_index: index,
                ..Default::default()
            };
            fontdue::Font::from_bytes(data, settings).map_err(str::to_string)
        })
        .ok_or("Could not read the font.")?
    };
    let fonts = [
        load(Weight(weight), Style::Normal)?,
        load(Weight(bold), Style::Normal)?,
        load(Weight(weight), Style::Italic)?,
        load(Weight(bold), Style::Italic)?,
    ];
    // The pinned copy wins: distributions package older symbol fonts under the same name.
    let pinned = crate::nvim::runtime()
        .and_then(|r| std::fs::read(r.join("fonts/SymbolsNerdFontMono-Regular.ttf")).ok());
    let symbols = pinned
        .or_else(|| {
            let id = db.query(&Query {
                families: &[Family::Name("Symbols Nerd Font Mono")],
                ..Query::default()
            })?;
            db.with_face_data(id, |data, _| data.to_vec())
        })
        .and_then(|data| fontdue::Font::from_bytes(data, fontdue::FontSettings::default()).ok());
    Ok((fonts, symbols))
}

pub struct Renderer {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    pipeline: wgpu::RenderPipeline,
    bind_group: wgpu::BindGroup,
    screen: wgpu::Buffer,
    buffer: wgpu::Buffer,
    capacity: usize,
    texture: wgpu::Texture,
    atlas: Atlas,
    fonts: [fontdue::Font; 4],
    symbols: Option<fontdue::Font>,
    font: Font,
    scale: f32,
    px: f32,
    baseline: f32,
    pub pad: f32,
    pub cell: (f32, f32),
    data: Vec<Instance>,
    /// Instance ranges to draw, each clipped to a rectangle or not.
    ranges: Vec<(std::ops::Range<u32>, Option<[u32; 4]>)>,
    anims: Vec<ScrollAnim>,
    grid_size: (usize, usize),
}

impl Renderer {
    pub fn new(window: Arc<Window>) -> Result<Self, String> {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor::default());
        let size = window.inner_size();
        let scale = window.scale_factor() as f32;
        let surface = instance.create_surface(window).map_err(|e| e.to_string())?;
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .map_err(|e| e.to_string())?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("lazycode"),
            required_limits:
                wgpu::Limits::downlevel_webgl2_defaults().using_resolution(adapter.limits()),
            ..Default::default()
        }))
        .map_err(|e| e.to_string())?;
        let caps = surface.get_capabilities(&adapter);
        // Blending in gamma space keeps theme colors byte-exact, like a terminal does.
        let format = caps
            .formats
            .iter()
            .copied()
            .find(|f| !f.is_srgb())
            .unwrap_or(caps.formats[0]);
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width: size.width.max(1),
            height: size.height.max(1),
            present_mode: wgpu::PresentMode::AutoVsync,
            desired_maximum_frame_latency: 1,
            alpha_mode: caps.alpha_modes[0],
            view_formats: vec![],
        };
        surface.configure(&device, &config);

        let screen = device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("glyphs"),
            size: wgpu::Extent3d {
                width: ATLAS,
                height: ATLAS,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let view = texture.create_view(&Default::default());
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor::default());
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: screen.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(&view),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
            ],
        });
        let shader = device.create_shader_module(wgpu::include_wgsl!("render.wgsl"));
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[&layout],
            push_constant_ranges: &[],
        });
        let attributes = wgpu::vertex_attr_array![
            0 => Float32x2, 1 => Float32x2, 2 => Float32x4, 3 => Float32x4, 4 => Float32x4,
            5 => Float32
        ];
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: None,
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs"),
                compilation_options: Default::default(),
                buffers: &[wgpu::VertexBufferLayout {
                    array_stride: size_of::<Instance>() as u64,
                    step_mode: wgpu::VertexStepMode::Instance,
                    attributes: &attributes,
                }],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs"),
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleStrip,
                ..Default::default()
            },
            depth_stencil: None,
            multisample: Default::default(),
            multiview: None,
            cache: None,
        });

        let capacity = 16_384;
        let buffer = Self::instance_buffer(&device, capacity);
        let (fonts, symbols) = load_fonts(
            &Font::default().families,
            Font::default().weight,
            Font::default().bold,
        )?;
        let (px, baseline, pad, cell) = metrics(&fonts[0], &Font::default(), scale)?;
        let renderer = Self {
            surface,
            device,
            queue,
            config,
            pipeline,
            bind_group,
            screen,
            buffer,
            capacity,
            texture,
            atlas: Atlas::default(),
            fonts,
            symbols,
            font: Font::default(),
            scale,
            px,
            baseline,
            pad,
            cell,
            data: Vec::new(),
            ranges: Vec::new(),
            anims: Vec::new(),
            grid_size: (0, 0),
        };
        renderer.write_screen();
        Ok(renderer)
    }

    fn instance_buffer(device: &wgpu::Device, capacity: usize) -> wgpu::Buffer {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("instances"),
            size: (capacity * size_of::<Instance>()) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        })
    }

    fn write_screen(&self) {
        let size = [
            self.config.width as f32,
            self.config.height as f32,
            0.0,
            0.0,
        ];
        self.queue
            .write_buffer(&self.screen, 0, bytemuck::cast_slice(&size));
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        self.config.width = width;
        self.config.height = height;
        self.surface.configure(&self.device, &self.config);
        self.write_screen();
    }

    /// Moving to a display with another scale re-rasterizes every glyph at the new size.
    pub fn set_scale(&mut self, scale: f32) {
        self.scale = scale;
        self.remeasure();
    }

    pub fn reset(&mut self) {
        self.anims.clear();
    }

    /// Applies `guifont`. Returns true when the cell size may have changed.
    pub fn set_font(&mut self, guifont: &str) -> bool {
        self.apply(Font {
            line: self.font.line,
            ..parse_guifont(guifont)
        })
    }

    /// Applies 'linespace', the extra pixels between lines.
    pub fn set_line_space(&mut self, pixels: f32) -> bool {
        self.apply(Font {
            line: pixels,
            ..self.font.clone()
        })
    }

    fn apply(&mut self, font: Font) -> bool {
        if font == self.font {
            return false;
        }
        if (&font.families, font.weight, font.bold)
            != (&self.font.families, self.font.weight, self.font.bold)
        {
            match load_fonts(&font.families, font.weight, font.bold) {
                Ok((fonts, _)) => self.fonts = fonts,
                Err(_) => return false,
            }
        }
        self.font = font;
        self.remeasure();
        true
    }

    fn remeasure(&mut self) {
        if let Ok((px, baseline, pad, cell)) = metrics(&self.fonts[0], &self.font, self.scale) {
            (self.px, self.baseline, self.pad, self.cell) = (px, baseline, pad, cell);
            self.atlas = Atlas::default();
        }
    }

    /// Columns and rows that fit in the window.
    pub fn grid_size(&self) -> (u32, u32) {
        let fit = |pixels: u32, cell: f32| {
            (((pixels as f32 - self.pad * 2.0) / cell).floor() as u32).max(1)
        };
        (
            fit(self.config.width, self.cell.0),
            fit(self.config.height, self.cell.1),
        )
    }

    /// Grid cell under a window position.
    pub fn cell_at(&self, x: f64, y: f64) -> (u32, u32) {
        let at = |v: f64, cell: f32| ((v as f32 - self.pad).max(0.0) / cell) as u32;
        (at(y, self.cell.1), at(x, self.cell.0))
    }

    /// Returns `None` for blank glyphs, and an error when the atlas is full.
    /// `font` is the style index, plus 4 for an icon drawn across two cells.
    fn glyph(&mut self, ch: char, font: u8) -> Result<Option<Glyph>, ()> {
        if let Some(glyph) = self.atlas.glyphs.get(&(ch, font)) {
            return Ok(*glyph);
        }
        // shortcut: only the Nerd Font symbols back up the main font, so emoji and CJK show as boxes; add a system fallback chain when someone needs them.
        let (wide, main) = (font & 4 != 0, &self.fonts[(font & 3) as usize]);
        let face = match &self.symbols {
            Some(symbols)
                if main.lookup_glyph_index(ch) == 0 && symbols.lookup_glyph_index(ch) != 0 =>
            {
                symbols
            }
            _ => main,
        };
        let (cw, chh) = self.cell;
        let px = if wide {
            let m = face.metrics(ch, self.px);
            // 1.5 of the 2 cells, so the icon keeps a gap before the text after it.
            self.px * fit(m.width as f32, m.height as f32, cw * 1.5, chh * 0.8)
        } else {
            self.px
        };
        let (m, bitmap) = face.rasterize(ch, px);
        let glyph = if m.width == 0 || m.height == 0 {
            None
        } else {
            let (x, y) = self
                .atlas
                .place(m.width as u32, m.height as u32)
                .ok_or(())?;
            self.queue.write_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: &self.texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d { x, y, z: 0 },
                    aspect: wgpu::TextureAspect::All,
                },
                &bitmap,
                wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(m.width as u32),
                    rows_per_image: None,
                },
                wgpu::Extent3d {
                    width: m.width as u32,
                    height: m.height as u32,
                    depth_or_array_layers: 1,
                },
            );
            let side = ATLAS as f32;
            Some(Glyph {
                uv: [
                    x as f32 / side,
                    y as f32 / side,
                    m.width as f32 / side,
                    m.height as f32 / side,
                ],
                size: [m.width as f32, m.height as f32],
                offset: if wide {
                    let (w, h) = (m.width as f32, m.height as f32);
                    [
                        ((cw * 2.0 - w) / 2.0).round(),
                        ((chh - h) / 2.0).round() - self.baseline,
                    ]
                } else {
                    // Letter spacing splits evenly around each letter.
                    let inset = (self.font.letter * self.scale / 2.0).round();
                    [m.xmin as f32 + inset, -(m.height as f32 + m.ymin as f32)]
                },
            })
        };
        self.atlas.glyphs.insert((ch, font), glyph);
        Ok(glyph)
    }

    fn rect(&mut self, x: f32, y: f32, w: f32, h: f32, color: u32) {
        self.data.push(Instance {
            pos: [x, y],
            size: [w, h],
            uv: [0.0; 4],
            color: rgba(color),
            bg: [0.0; 4],
            glyph: 0.0,
        });
    }

    fn text(&mut self, ch: char, font: u8, x: f32, y: f32, color: u32, bg: u32) -> Result<(), ()> {
        if let Some(g) = self.glyph(ch, font)? {
            self.data.push(Instance {
                pos: [x + g.offset[0], y + self.baseline + g.offset[1]],
                size: g.size,
                uv: g.uv,
                color: rgba(color),
                bg: rgba(bg),
                glyph: 1.0,
            });
        }
        Ok(())
    }

    /// One row of cells: backgrounds first, so an icon spilling into the next cell stays on
    /// top of it, then text and lines. `skip` leaves out cells another pass draws.
    fn row(
        &mut self,
        grid: &Grid,
        cells: &[Cell],
        x0: f32,
        y: f32,
        skip: impl Fn(usize) -> bool,
    ) -> Result<(), ()> {
        let (cw, ch) = self.cell;
        for (i, cell) in cells.iter().enumerate().filter(|(i, _)| !skip(*i)) {
            let bg = grid.colors(&grid.style(cell.hl)).1;
            if bg != grid.bg {
                self.rect(x0 + i as f32 * cw, y, cw, ch, bg);
            }
        }
        for (i, cell) in cells.iter().enumerate().filter(|(i, _)| !skip(*i)) {
            let style = grid.style(cell.hl);
            let (fg, bg) = grid.colors(&style);
            let x = x0 + i as f32 * cw;
            if cell.ch != ' ' && cell.ch != '\0' {
                let font = style.bold as u8 | (style.italic as u8) << 1;
                // Like kitty: an icon followed by a space takes both cells, so it reads at text size.
                let wide = is_icon(cell.ch) && cells.get(i + 1).is_some_and(|n| n.ch == ' ');
                self.text(cell.ch, font | (wide as u8) << 2, x, y, fg, bg)?;
            }
            if style.underline {
                let color = style.sp.unwrap_or(fg);
                self.rect(x, y + self.baseline + 2.0, cw, 1.0, color);
            }
            if style.strike {
                self.rect(x, y + (ch / 2.0).round(), cw, 1.0, fg);
            }
        }
        Ok(())
    }

    fn build(&mut self, grid: &Grid, cursor_alpha: f32) -> Result<(), ()> {
        self.data.clear();
        self.ranges.clear();
        let (cw, ch) = self.cell;
        let pad = self.pad;
        let anims = std::mem::take(&mut self.anims);
        for r in 0..grid.rows {
            let cells = &grid.cells[r * grid.cols..(r + 1) * grid.cols];
            let skip = |c: usize| anims.iter().any(|a| a.contains(r, c));
            let built = self.row(grid, cells, pad, pad + r as f32 * ch, skip);
            if built.is_err() {
                self.anims = anims;
                return Err(());
            }
        }
        self.ranges.push((0..self.data.len() as u32, None));
        // Scrolling regions slide by their offset, clipped to the region.
        for a in &anims {
            let start = self.data.len() as u32;
            let (above, below) = a.extra();
            let (top, bottom) = (pad + a.top as f32 * ch, pad + a.bottom as f32 * ch);
            for v in -(above as isize)..(a.bottom - a.top + below) as isize {
                let y = top + v as f32 * ch + a.offset;
                if y + ch <= top || y >= bottom {
                    continue;
                }
                let r = (a.top as isize + v) as usize;
                let cells = match a.extra_row(v) {
                    Some(cells) => cells,
                    None => &grid.cells[r * grid.cols + a.left..r * grid.cols + a.right],
                };
                if self
                    .row(grid, cells, pad + a.left as f32 * cw, y, |_| false)
                    .is_err()
                {
                    self.anims = anims;
                    return Err(());
                }
            }
            let clip = [
                pad + a.left as f32 * cw,
                top,
                (a.right - a.left) as f32 * cw,
                bottom - top,
            ];
            let clip = clip.map(|v| v.round().max(0.0) as u32);
            self.ranges
                .push((start..self.data.len() as u32, Some(clip)));
        }
        let start = self.data.len() as u32;
        let (row, col) = grid.cursor;
        let lift = anims
            .iter()
            .find(|a| a.contains(row, col))
            .map_or(0.0, |a| a.offset);
        self.anims = anims;
        if let Some((shape, percent)) = grid
            .cursor_shape()
            .filter(|_| row < grid.rows && col < grid.cols && cursor_alpha > 0.0)
        {
            let (x, y) = (pad + col as f32 * cw, pad + row as f32 * ch + lift);
            let cell = grid.cells[row * grid.cols + col];
            let style = grid.style(cell.hl);
            let (fg, bg) = grid.colors(&style);
            let part = percent as f32 / 100.0;
            match shape {
                CursorShape::Block => {
                    self.rect(x, y, cw, ch, fg);
                    if cell.ch != ' ' && cell.ch != '\0' {
                        let font = style.bold as u8 | (style.italic as u8) << 1;
                        self.text(cell.ch, font, x, y, bg, fg)?;
                    }
                }
                CursorShape::Vertical => self.rect(x, y, (cw * part).ceil().max(2.0), ch, fg),
                CursorShape::Horizontal => {
                    let h = (ch * part).ceil();
                    self.rect(x, y + ch - h, cw, h, fg);
                }
            }
            for i in &mut self.data[start as usize..] {
                i.color[3] *= cursor_alpha;
            }
        }
        self.ranges.push((start..self.data.len() as u32, None));
        Ok(())
    }

    /// Returns false when the surface was rebuilt and the frame must be retried.
    /// Takes the scrolls the grid recorded and moves the animations `ms` on.
    /// Returns true while something still moves.
    pub fn animate(&mut self, grid: &mut Grid, ms: f32) -> bool {
        if (grid.rows, grid.cols) != self.grid_size {
            self.grid_size = (grid.rows, grid.cols);
            self.anims.clear();
            grid.scrolls.clear();
        }
        ScrollAnim::step(&mut self.anims, ms);
        for scroll in grid.scrolls.drain(..) {
            ScrollAnim::push(&mut self.anims, scroll, self.cell.1);
        }
        !self.anims.is_empty()
    }

    pub fn draw(&mut self, grid: &Grid, cursor_alpha: f32) -> bool {
        if self.build(grid, cursor_alpha).is_err() {
            // The atlas is full: start over with only the glyphs on screen.
            self.atlas = Atlas::default();
            if self.build(grid, cursor_alpha).is_err() {
                return true;
            }
        }
        if self.data.len() > self.capacity {
            self.capacity = self.data.len().next_power_of_two();
            self.buffer = Self::instance_buffer(&self.device, self.capacity);
        }
        self.queue
            .write_buffer(&self.buffer, 0, bytemuck::cast_slice(&self.data));

        let frame = match self.surface.get_current_texture() {
            Ok(frame) => frame,
            Err(wgpu::SurfaceError::Timeout) => return false,
            Err(_) => {
                self.surface.configure(&self.device, &self.config);
                return false;
            }
        };
        let view = frame.texture.create_view(&Default::default());
        let mut encoder = self.device.create_command_encoder(&Default::default());
        {
            let [r, g, b, _] = rgba(grid.bg);
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: r as f64,
                            g: g as f64,
                            b: b as f64,
                            a: 1.0,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.bind_group, &[]);
            pass.set_vertex_buffer(0, self.buffer.slice(..));
            let (w, h) = (self.config.width, self.config.height);
            for (range, clip) in &self.ranges {
                let [x, y, cw, ch] = clip.unwrap_or([0, 0, w, h]);
                let (x, y) = (x.min(w - 1), y.min(h - 1));
                pass.set_scissor_rect(x, y, cw.min(w - x).max(1), ch.min(h - y).max(1));
                pass.draw(0..4, range.clone());
            }
        }
        self.queue.submit([encoder.finish()]);
        frame.present();
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn guifont_gives_every_font_detail() {
        let f = parse_guifont("Fira_Code, Hack:w600:W800:h12.5:c1.5");
        assert_eq!(f.families, ["Fira Code", "Hack"]);
        assert_eq!(
            (f.points, f.weight, f.bold, f.letter),
            (12.5, 600, 800, 1.5)
        );
        // Missing or out of range parts keep the defaults.
        assert_eq!(parse_guifont(""), Font::default());
        let f = parse_guifont("Hack:h0:w5");
        assert_eq!(
            (f.points, f.weight),
            (Font::default().points, Font::default().weight)
        );
    }

    #[test]
    fn atlas_wraps_shelves_and_reports_full() {
        let mut atlas = Atlas::default();
        assert_eq!(atlas.place(2000, 10), Some((0, 0)));
        assert_eq!(atlas.place(100, 20), Some((0, 11)));
        assert_eq!(atlas.place(10, ATLAS), None);
    }

    #[test]
    fn icons_fill_two_cells_without_distortion() {
        assert!(is_icon('\u{f07b}') && is_icon('\u{f024b}') && !is_icon('a'));
        // A square icon in a 10x22 cell pair is limited by the 20 px width.
        assert_eq!(fit(10.0, 10.0, 20.0, 22.0), 2.0);
        // A tall icon is limited by the height.
        assert_eq!(fit(10.0, 20.0, 20.0, 22.0), 1.1);
    }

    #[test]
    fn colors_are_byte_exact() {
        let [r, g, b, a] = rgba(0x1a1b26);
        assert_eq!(
            [
                (r * 255.0) as u8,
                (g * 255.0) as u8,
                (b * 255.0) as u8,
                a as u8
            ],
            [0x1a, 0x1b, 0x26, 1]
        );
    }
}
