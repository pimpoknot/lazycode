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
    @location(4) bg: vec4<f32>,
    @location(5) glyph: f32,
}

struct Out {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) bg: vec4<f32>,
    @location(3) glyph: f32,
}

@vertex
fn vs(v: In) -> Out {
    let corner = vec2<f32>(f32(v.index & 1u), f32(v.index >> 1u));
    let p = (v.pos + corner * v.size) / screen.size;
    var out: Out;
    out.position = vec4<f32>(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    out.uv = v.uv.xy + corner * v.uv.zw;
    out.color = v.color;
    out.bg = v.bg;
    out.glyph = v.glyph;
    return out;
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// The surface blends in gamma space so theme colors stay exact. For glyph edges that makes
// light text on dark thin, so the coverage becomes the alpha a linear-light blend would give.
fn linear_alpha(coverage: f32, fg: vec3<f32>, bg: vec3<f32>) -> f32 {
    let f = luma(fg);
    let b = luma(bg);
    if abs(f - b) < 0.02 {
        return coverage;
    }
    let mixed = pow(mix(pow(b, 2.2), pow(f, 2.2), coverage), 1.0 / 2.2);
    return clamp((mixed - b) / (f - b), 0.0, 1.0);
}

@fragment
fn fs(v: Out) -> @location(0) vec4<f32> {
    if v.glyph < 0.5 {
        return v.color;
    }
    let coverage = textureSampleLevel(atlas, atlas_sampler, v.uv, 0.0).r;
    return vec4<f32>(v.color.rgb, v.color.a * linear_alpha(coverage, v.color.rgb, v.bg.rgb));
}
