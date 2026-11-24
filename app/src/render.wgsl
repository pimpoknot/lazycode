struct Screen { size: vec2<f32> }

@group(0) @binding(0) var<uniform> screen: Screen;
@group(0) @binding(1) var atlas: texture_2d<f32>;
@group(0) @binding(2) var atlas_sampler: sampler;

struct In {
    @builtin(vertex_index) index: u32,
    @location(0) pos: vec2<f32>,
    @location(1) size: vec2<f32>,
    @location(2) uv: vec4<f32>,
    @location(3) color: vec4<f32>,
    @location(4) glyph: f32,
}

struct Out {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) glyph: f32,
}

@vertex
fn vs(v: In) -> Out {
    let corner = vec2<f32>(f32(v.index & 1u), f32(v.index >> 1u));
    let p = (v.pos + corner * v.size) / screen.size;
    var out: Out;
    out.position = vec4<f32>(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    out.uv = v.uv.xy + corner * v.uv.zw;
    out.color = v.color;
    out.glyph = v.glyph;
    return out;
}

@fragment
fn fs(v: Out) -> @location(0) vec4<f32> {
    let coverage = textureSampleLevel(atlas, atlas_sampler, v.uv, 0.0).r;
    return vec4<f32>(v.color.rgb, v.color.a * mix(1.0, coverage, v.glyph));
}
