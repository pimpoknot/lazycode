//! LazyCode native window: draws the embedded Neovim without a terminal.
mod anim;
mod grid;
mod icon;
mod input;
mod nvim;
mod render;

use grid::Grid;
use nvim::Nvim;
use render::Renderer;
use rmpv::Value;
use std::sync::Arc;
use std::time::{Duration, Instant};
use winit::application::ApplicationHandler;
use winit::dpi::{LogicalSize, PhysicalPosition};
use winit::event::{ElementState, MouseButton, MouseScrollDelta, StartCause, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop, EventLoopProxy};
use winit::keyboard::ModifiersState;
use winit::window::{CursorIcon, Window, WindowId};

enum UserEvent {
    Redraw(Value),
    /// Mouse pointer chosen by `lazycode.mouse`: pointer, text, ew-resize, ns-resize or default.
    Pointer(String),
    Exit,
}

struct Ui {
    window: Arc<Window>,
    renderer: Renderer,
    nvim: Nvim,
    grid: Grid,
    size: (u32, u32),
    modifiers: ModifiersState,
    position: PhysicalPosition<f64>,
    cell: (u32, u32),
    held: Option<&'static str>,
    wheel: f64,
    /// When the cursor last moved or changed shape: the blink restarts from there.
    cursor_since: Instant,
    last_frame: Instant,
    /// True while a scroll animation runs.
    moving: bool,
}

struct App {
    proxy: EventLoopProxy<UserEvent>,
    args: Vec<String>,
    ui: Option<Ui>,
    error: Option<String>,
    /// Set by the end-to-end tests, which read the screen as text.
    screen: Option<std::path::PathBuf>,
}

/// First line: cell width, cell height, padding and whether the cursor shows.
fn write_screen(path: &std::path::Path, ui: &Ui) {
    let (w, h) = ui.renderer.cell;
    let visible = ui.grid.cursor_shape().is_some() as u8;
    let (pad, scrolled) = (ui.renderer.pad, ui.grid.scrolled);
    let text = format!("{w} {h} {pad} {scrolled} {visible}\n{}", ui.grid.text());
    let partial = path.with_extension("partial");
    if std::fs::write(&partial, text).is_ok() {
        let _ = std::fs::rename(partial, path);
    }
}

impl App {
    fn start(&mut self, event_loop: &ActiveEventLoop) -> Result<Ui, String> {
        #[allow(unused_mut)]
        let mut attributes = Window::default_attributes()
            .with_title("LazyCode")
            .with_window_icon(winit::window::Icon::from_rgba(icon::rgba(128), 128, 128).ok())
            .with_inner_size(LogicalSize::new(1200.0, 760.0));
        #[cfg(target_os = "macos")]
        {
            use winit::platform::macos::{OptionAsAlt, WindowAttributesExtMacOS};
            attributes = attributes.with_option_as_alt(OptionAsAlt::Both);
        }
        #[cfg(all(unix, not(target_os = "macos")))]
        {
            use winit::platform::{
                wayland::WindowAttributesExtWayland, x11::WindowAttributesExtX11,
            };
            // Matches StartupWMClass in packaging/linux/lazycode.desktop.
            attributes = WindowAttributesExtX11::with_name(attributes, "lazycode", "lazycode");
            attributes = WindowAttributesExtWayland::with_name(attributes, "lazycode", "lazycode");
        }
        let window = Arc::new(
            event_loop
                .create_window(attributes)
                .map_err(|e| e.to_string())?,
        );
        let renderer = Renderer::new(window.clone())?;
        let (on_notify, on_exit) = handlers(&self.proxy);
        let nvim = Nvim::spawn(self.args.clone(), on_notify, on_exit)
            .map_err(|e| format!("Could not start Neovim: {e}"))?;
        let size = renderer.grid_size();
        nvim.attach(size.0, size.1);
        Ok(Ui {
            window,
            renderer,
            nvim,
            grid: Grid::new(),
            size,
            modifiers: ModifiersState::empty(),
            position: PhysicalPosition::new(0.0, 0.0),
            cell: (0, 0),
            held: None,
            wheel: 0.0,
            cursor_since: Instant::now(),
            last_frame: Instant::now(),
            moving: false,
        })
    }
}

/// What the Neovim connection sends to the event loop.
fn handlers(
    proxy: &EventLoopProxy<UserEvent>,
) -> (
    impl Fn(&str, Value) + Send + 'static,
    impl FnOnce() + Send + 'static,
) {
    let (redraw, exit) = (proxy.clone(), proxy.clone());
    (
        move |method: &str, args: Value| {
            let event = match method {
                "redraw" => UserEvent::Redraw(args),
                // A window scrolled: the grid matches it against the next flush.
                "lazycode_scroll" => UserEvent::Redraw(Value::Array(vec![Value::Array(vec![
                    Value::from("lazycode_scroll"),
                    args,
                ])])),
                "lazycode_cursor" => UserEvent::Pointer(
                    args.as_array()
                        .and_then(|a| a.first())
                        .and_then(Value::as_str)
                        .map(str::to_string)
                        .unwrap_or_default(),
                ),
                _ => return,
            };
            let _ = redraw.send_event(event);
        },
        move || {
            let _ = exit.send_event(UserEvent::Exit);
        },
    )
}

fn mouse_modifiers(m: ModifiersState) -> String {
    [
        (m.control_key(), 'C'),
        (m.alt_key(), 'A'),
        (m.shift_key(), 'S'),
        (m.super_key(), 'D'),
    ]
    .iter()
    .filter_map(|(on, c)| on.then_some(*c))
    .collect()
}

impl Ui {
    /// Tells Neovim the new grid size after the window or the cell size changed.
    fn fit(&mut self) {
        let grid = self.renderer.grid_size();
        if grid != self.size {
            self.size = grid;
            self.nvim.resize(grid.0, grid.1);
        }
        self.window.request_redraw();
    }

    fn scroll(&mut self, lines: f64) {
        self.wheel += lines;
        let steps = self.wheel.trunc();
        self.wheel -= steps;
        let action = if steps > 0.0 { "up" } else { "down" };
        let modifiers = mouse_modifiers(self.modifiers);
        for _ in 0..steps.abs() as u32 {
            self.nvim
                .mouse("wheel", action, &modifiers, self.cell.0, self.cell.1);
        }
    }

    fn event(&mut self, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => self.nvim.input("<Cmd>confirm qa<CR>"),
            WindowEvent::Resized(size) => {
                self.renderer.resize(size.width, size.height);
                self.fit();
            }
            WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                self.renderer.set_scale(scale_factor as f32);
                self.fit();
            }
            WindowEvent::ModifiersChanged(m) => self.modifiers = m.state(),
            // Fires FocusGained, where LazyVim reloads files changed in other apps.
            WindowEvent::Focused(focused) => {
                self.nvim.notify("nvim_ui_set_focus", vec![focused.into()])
            }
            WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed => {
                let text = event.text.as_deref();
                if let Some(keys) = input::to_nvim(&event.logical_key, text, self.modifiers) {
                    self.nvim.input(&keys);
                    self.cursor_since = Instant::now();
                }
            }
            WindowEvent::CursorMoved { position, .. } => {
                self.position = position;
                let cell = self.renderer.cell_at(position.x, position.y);
                if cell != self.cell {
                    self.cell = cell;
                    let modifiers = mouse_modifiers(self.modifiers);
                    // Plain moves drive hover, including the highlight in right-click menus.
                    let (button, action) = self.held.map_or(("move", ""), |b| (b, "drag"));
                    self.nvim.mouse(button, action, &modifiers, cell.0, cell.1);
                    self.nvim.hover(cell.0, cell.1);
                }
            }
            WindowEvent::MouseInput { state, button, .. } => {
                let name = match button {
                    MouseButton::Left => "left",
                    MouseButton::Right => "right",
                    MouseButton::Middle => "middle",
                    _ => return,
                };
                let action = if state == ElementState::Pressed {
                    self.held = Some(name);
                    "press"
                } else {
                    self.held = None;
                    "release"
                };
                let modifiers = mouse_modifiers(self.modifiers);
                self.nvim
                    .mouse(name, action, &modifiers, self.cell.0, self.cell.1);
            }
            WindowEvent::MouseWheel { delta, .. } => match delta {
                MouseScrollDelta::LineDelta(_, y) => self.scroll(y as f64),
                MouseScrollDelta::PixelDelta(p) => self.scroll(p.y / self.renderer.cell.1 as f64),
            },
            WindowEvent::RedrawRequested => {
                let now = Instant::now();
                let ms = now.duration_since(self.last_frame).as_secs_f32() * 1000.0;
                self.last_frame = now;
                self.moving = self.renderer.animate(&mut self.grid, ms.min(100.0));
                let t = now.duration_since(self.cursor_since).as_millis() as u64;
                let alpha = self.grid.blink().map_or(1.0, |b| anim::blink_alpha(t, b));
                if !self.renderer.draw(&self.grid, alpha) {
                    self.window.request_redraw();
                }
            }
            _ => {}
        }
    }
}

impl Ui {
    /// When the next frame is due for the blink or a scroll, if anything animates.
    fn next_frame(&self) -> Option<Instant> {
        let now = Instant::now();
        let wait = if self.moving {
            16
        } else {
            let t = now.duration_since(self.cursor_since).as_millis() as u64;
            anim::blink_wait(t, self.grid.blink()?)
        };
        Some(now + Duration::from_millis(wait.max(1)))
    }
}

impl ApplicationHandler<UserEvent> for App {
    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        let next = self.ui.as_ref().and_then(Ui::next_frame);
        event_loop.set_control_flow(next.map_or(ControlFlow::Wait, ControlFlow::WaitUntil));
    }

    fn new_events(&mut self, _: &ActiveEventLoop, cause: StartCause) {
        if let (StartCause::ResumeTimeReached { .. }, Some(ui)) = (cause, &self.ui) {
            ui.window.request_redraw();
        }
    }

    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.ui.is_some() {
            return;
        }
        match self.start(event_loop) {
            Ok(ui) => self.ui = Some(ui),
            Err(error) => {
                self.error = Some(error);
                event_loop.exit();
            }
        }
    }

    fn window_event(&mut self, _: &ActiveEventLoop, _: WindowId, event: WindowEvent) {
        if let Some(ui) = &mut self.ui {
            ui.event(event);
        }
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: UserEvent) {
        match event {
            UserEvent::Exit => {
                // After :restart the old server exits, and the window moves to the new one.
                if let Some(ui) = &mut self.ui
                    && let Some(addr) = ui.grid.restart.take()
                {
                    let (on_notify, on_exit) = handlers(&self.proxy);
                    match Nvim::connect(&addr, on_notify, on_exit) {
                        Ok(nvim) => {
                            ui.grid = grid::Grid::new();
                            ui.renderer.reset();
                            ui.moving = false;
                            ui.nvim = nvim;
                            ui.nvim.attach(ui.size.0, ui.size.1);
                            ui.nvim.notify("nvim_ui_set_focus", vec![true.into()]);
                            return;
                        }
                        Err(error) => self.error = Some(format!("Could not reload: {error}")),
                    }
                }
                event_loop.exit()
            }
            UserEvent::Pointer(shape) => {
                if let Some(ui) = &self.ui {
                    ui.window.set_cursor(match shape.as_str() {
                        "pointer" => CursorIcon::Pointer,
                        "text" => CursorIcon::Text,
                        "ew-resize" => CursorIcon::EwResize,
                        "ns-resize" => CursorIcon::NsResize,
                        _ => CursorIcon::Default,
                    });
                }
            }
            UserEvent::Redraw(batch) => {
                if let Some(ui) = &mut self.ui
                    && let before = (ui.grid.cursor, ui.grid.cursor_shape())
                    && ui.grid.apply(&batch)
                {
                    if (ui.grid.cursor, ui.grid.cursor_shape()) != before {
                        ui.cursor_since = Instant::now();
                    }
                    let font = ui
                        .grid
                        .guifont
                        .take()
                        .is_some_and(|f| ui.renderer.set_font(&f));
                    let line = ui
                        .grid
                        .linespace
                        .take()
                        .is_some_and(|l| ui.renderer.set_line_space(l as f32));
                    if font || line {
                        ui.fit();
                    }
                    ui.window.request_redraw();
                    if let Some(path) = &self.screen {
                        write_screen(path, ui);
                    }
                }
            }
        }
    }
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("lazycode-app {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    #[allow(unused_mut)]
    let mut builder = EventLoop::<UserEvent>::with_user_event();
    #[cfg(target_os = "macos")]
    {
        use winit::platform::macos::EventLoopBuilderExtMacOS;
        // No app menu: Cmd+Q, Cmd+W and the rest belong to the editor, as Ctrl does on Linux.
        builder.with_default_menu(false);
    }
    let event_loop = match builder.build() {
        Ok(event_loop) => event_loop,
        Err(error) => {
            eprintln!("lazycode-app: {error}");
            std::process::exit(1);
        }
    };
    let mut app = App {
        proxy: event_loop.create_proxy(),
        args: std::env::args().skip(1).collect(),
        ui: None,
        error: None,
        screen: std::env::var_os("LAZYCODE_APP_SCREEN").map(Into::into),
    };
    let result = event_loop.run_app(&mut app);
    if let Some(error) = app.error {
        eprintln!("lazycode-app: {error}");
        std::process::exit(1);
    }
    if let Err(error) = result {
        eprintln!("lazycode-app: {error}");
        std::process::exit(1);
    }
}
