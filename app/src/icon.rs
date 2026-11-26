//! The window icon, drawn from the same shapes as `assets/lazycode.svg`, so the app needs no
//! image decoder. Keep the two in sync.

type Point = (f32, f32);

/// Background, then each stroke: its points, half its width and its color, in SVG units.
const BACKGROUND: [f32; 3] = [26.0, 27.0, 38.0];
const RADIUS: f32 = 52.0;
const STROKES: [(&[Point], f32, [f32; 3]); 2] = [
    (
        &[(84.0, 62.0), (84.0, 194.0), (176.0, 194.0)],
        14.0,
        [122.0, 162.0, 247.0],
    ),
    (
        &[(136.0, 72.0), (184.0, 72.0), (136.0, 128.0), (184.0, 128.0)],
        8.0,
        [187.0, 154.0, 247.0],
    ),
];

fn segment(p: Point, a: Point, b: Point) -> f32 {
    let (ab, ap) = ((b.0 - a.0, b.1 - a.1), (p.0 - a.0, p.1 - a.1));
    let t = ((ap.0 * ab.0 + ap.1 * ab.1) / (ab.0 * ab.0 + ab.1 * ab.1)).clamp(0.0, 1.0);
    (ap.0 - ab.0 * t).hypot(ap.1 - ab.1 * t)
}

/// Square RGBA pixels, `size` wide.
pub fn rgba(size: u32) -> Vec<u8> {
    let unit = 256.0 / size as f32; // SVG units per pixel
    let cover = |distance: f32| (0.5 - distance / unit).clamp(0.0, 1.0);
    let mut out = Vec::with_capacity((size * size * 4) as usize);
    for y in 0..size {
        for x in 0..size {
            let p = ((x as f32 + 0.5) * unit, (y as f32 + 0.5) * unit);
            let q = (
                (p.0 - 128.0).abs() - 128.0 + RADIUS,
                (p.1 - 128.0).abs() - 128.0 + RADIUS,
            );
            let square = q.0.max(0.0).hypot(q.1.max(0.0)) + q.0.max(q.1).min(0.0) - RADIUS;
            let mut color = BACKGROUND;
            for (points, half, stroke) in STROKES {
                let d = points
                    .windows(2)
                    .map(|w| segment(p, w[0], w[1]))
                    .fold(f32::MAX, f32::min);
                let k = cover(d - half);
                color = [0, 1, 2].map(|i| color[i] + (stroke[i] - color[i]) * k);
            }
            out.extend(color.map(|c| c.round() as u8));
            out.push((cover(square) * 255.0).round() as u8);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    #[test]
    fn draws_the_strokes_inside_a_rounded_square() {
        let px = super::rgba(64);
        let at = |x: usize, y: usize| &px[(y * 64 + x) * 4..(y * 64 + x) * 4 + 4];
        assert_eq!(at(0, 0)[3], 0, "the rounded corner is transparent");
        assert_eq!(at(32, 4), [26, 27, 38, 255], "the background is opaque");
        assert_eq!(at(21, 32), [122, 162, 247, 255], "the L stroke is blue");
        assert_eq!(at(40, 18), [187, 154, 247, 255], "the Z stroke is purple");
    }
}
