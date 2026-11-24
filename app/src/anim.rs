//! Smooth scrolling and cursor blinking. Pure logic, so it is tested without a GPU.
use crate::grid::{Cell, Scroll};

/// How fast a scroll settles: the offset shrinks by e every this many milliseconds.
const SCROLL_MS: f32 = 60.0;
/// Length of the blink fade in and out.
const FADE_MS: u64 = 150;

/// One scrolling region sliding back to rest, with the rows that already left it.
pub struct ScrollAnim {
    pub top: usize,
    pub bottom: usize,
    pub left: usize,
    pub right: usize,
    /// Pixels the content is drawn below its real place; negative is above.
    pub offset: f32,
    /// Rows just above the region, nearest last.
    above: Vec<Vec<Cell>>,
    /// Rows just below the region, nearest first.
    below: Vec<Vec<Cell>>,
}

impl ScrollAnim {
    /// Adds a `grid_scroll` to the matching animation, or starts one.
    pub fn push(anims: &mut Vec<ScrollAnim>, s: Scroll, cell_h: f32) {
        let i = match anims
            .iter()
            .position(|a| (a.top, a.bottom, a.left, a.right) == (s.top, s.bottom, s.left, s.right))
        {
            Some(i) => i,
            None => {
                anims.push(ScrollAnim {
                    top: s.top,
                    bottom: s.bottom,
                    left: s.left,
                    right: s.right,
                    offset: 0.0,
                    above: Vec::new(),
                    below: Vec::new(),
                });
                anims.len() - 1
            }
        };
        let a = &mut anims[i];
        let n = s.rows.unsigned_abs() as usize;
        if s.rows > 0 {
            a.above.extend(s.gone);
            a.below.drain(..n.min(a.below.len()));
        } else {
            a.below.splice(0..0, s.gone);
            a.above.truncate(a.above.len().saturating_sub(n));
        }
        a.offset += s.rows as f32 * cell_h;
        // A jump longer than the region shows no motion worth the rows it would keep.
        let limit = (a.bottom - a.top) as f32 * cell_h;
        a.offset = a.offset.clamp(-limit, limit);
        let keep = |px: f32| (px.max(0.0) / cell_h).ceil() as usize;
        let above = keep(a.offset);
        a.above.drain(..a.above.len().saturating_sub(above));
        a.below.truncate(keep(-a.offset));
    }

    /// Moves every animation `ms` milliseconds on, and drops the ones at rest.
    pub fn step(anims: &mut Vec<ScrollAnim>, ms: f32) {
        for a in anims.iter_mut() {
            a.offset *= (-ms / SCROLL_MS).exp();
        }
        anims.retain(|a| a.offset.abs() >= 0.5);
    }

    /// Cells of a row relative to the region top: negative rows are above it.
    /// `None` inside the region, where the grid itself is drawn.
    pub fn extra_row(&self, v: isize) -> Option<&[Cell]> {
        let h = (self.bottom - self.top) as isize;
        if v < 0 {
            let i = self.above.len() as isize + v;
            (i >= 0).then(|| self.above[i as usize].as_slice())
        } else if v >= h {
            self.below.get((v - h) as usize).map(Vec::as_slice)
        } else {
            None
        }
    }

    /// Rows above and below the region that may show during the animation.
    pub fn extra(&self) -> (usize, usize) {
        (self.above.len(), self.below.len())
    }

    pub fn contains(&self, row: usize, col: usize) -> bool {
        (self.top..self.bottom).contains(&row) && (self.left..self.right).contains(&col)
    }
}

/// Cursor opacity `t` ms after it last moved: solid for `wait`, then on and off with fades.
pub fn blink_alpha(t: u64, [wait, on, off]: [u64; 3]) -> f32 {
    if t < wait {
        return 1.0;
    }
    let p = (t - wait) % (on + off);
    let fade = FADE_MS as f32;
    if p < on {
        ((on - p) as f32 / fade).min(1.0)
    } else {
        (1.0 - (on + off - p) as f32 / fade).max(0.0)
    }
}

/// Milliseconds until the blink next needs a frame.
pub fn blink_wait(t: u64, [wait, on, off]: [u64; 3]) -> u64 {
    if t < wait {
        return wait - t;
    }
    let p = (t - wait) % (on + off);
    let (fade_out, fade_in) = (on.saturating_sub(FADE_MS), on + off - FADE_MS.min(off));
    match p {
        p if p < fade_out => fade_out - p,
        p if p >= on && p < fade_in => fade_in - p,
        _ => 16,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(c: char) -> Vec<Cell> {
        vec![Cell { ch: c, hl: 0 }]
    }

    fn scroll(rows: i64, gone: &[char]) -> Scroll {
        Scroll {
            top: 0,
            bottom: 10,
            left: 0,
            right: 1,
            rows,
            gone: gone.iter().map(|c| row(*c)).collect(),
        }
    }

    #[test]
    fn scroll_starts_where_the_content_was_and_settles() {
        let mut anims = Vec::new();
        ScrollAnim::push(&mut anims, scroll(2, &['a', 'b']), 20.0);
        assert_eq!(anims[0].offset, 40.0);
        // The rows that left stay just above the region, in order.
        assert_eq!(anims[0].extra_row(-2).unwrap()[0].ch, 'a');
        assert_eq!(anims[0].extra_row(-1).unwrap()[0].ch, 'b');
        assert!(anims[0].extra_row(0).is_none());
        ScrollAnim::step(&mut anims, 60.0);
        assert!((anims[0].offset - 40.0 / std::f32::consts::E).abs() < 0.01);
        ScrollAnim::step(&mut anims, 1000.0);
        assert!(anims.is_empty());
    }

    #[test]
    fn scrolling_back_continues_from_the_current_offset() {
        let mut anims = Vec::new();
        ScrollAnim::push(&mut anims, scroll(1, &['a']), 20.0);
        ScrollAnim::push(&mut anims, scroll(-1, &['z']), 20.0);
        assert_eq!(anims[0].offset, 0.0);
        assert_eq!(anims[0].extra(), (0, 0));
        ScrollAnim::push(&mut anims, scroll(-1, &['y']), 20.0);
        assert_eq!(anims[0].offset, -20.0);
        assert_eq!(anims[0].extra_row(10).unwrap()[0].ch, 'y');
    }

    #[test]
    fn blink_fades_out_and_in() {
        let blink = [500, 530, 530];
        assert_eq!(blink_alpha(100, blink), 1.0);
        assert_eq!(blink_alpha(500, blink), 1.0);
        assert!((blink_alpha(500 + 455, blink) - 0.5).abs() < 0.01);
        assert_eq!(blink_alpha(500 + 600, blink), 0.0);
        assert!((blink_alpha(500 + 1060 - 75, blink) - 0.5).abs() < 0.01);
        assert_eq!(blink_wait(100, blink), 400);
        assert_eq!(blink_wait(500, blink), 380);
        assert_eq!(blink_wait(500 + 450, blink), 16);
        assert_eq!(blink_wait(500 + 600, blink), 310);
    }
}
