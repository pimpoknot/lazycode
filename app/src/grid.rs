//! Screen state driven by Neovim's `ext_linegrid` redraw events.
use rmpv::Value;
use std::collections::HashMap;

#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub struct Style {
    pub fg: Option<u32>,
    pub bg: Option<u32>,
    pub sp: Option<u32>,
    pub reverse: bool,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strike: bool,
    pub blend: u8,
}

/// shortcut: keeps only the first char of a cell, so combining marks are dropped; store a string when shaping lands.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cell {
    pub ch: char,
    pub hl: u32,
}

const BLANK: Cell = Cell { ch: ' ', hl: 0 };

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum CursorShape {
    Block,
    Vertical,
    Horizontal,
}

#[derive(Clone, Copy)]
struct ModeInfo {
    shape: CursorShape,
    percent: u32,
    attr: u32,
    /// blinkwait, blinkon and blinkoff from 'guicursor', in milliseconds.
    blink: [u64; 3],
}

/// A `grid_scroll`, with the rows that left the region, for the scroll animation.
pub struct Scroll {
    pub top: usize,
    pub bottom: usize,
    pub left: usize,
    pub right: usize,
    pub rows: i64,
    pub gone: Vec<Vec<Cell>>,
}

pub struct Grid {
    pub cols: usize,
    pub rows: usize,
    pub cells: Vec<Cell>,
    pub fg: u32,
    pub bg: u32,
    pub sp: u32,
    pub cursor: (usize, usize),
    styles: HashMap<u32, Style>,
    modes: Vec<ModeInfo>,
    mode: usize,
    /// Address of the new server after `:restart`, until the window joins it.
    pub restart: Option<String>,
    /// Scrolls since the renderer last took them.
    pub scrolls: Vec<Scroll>,
    /// The `guifont` and 'linespace' options, until the window reads them.
    pub guifont: Option<String>,
    pub linespace: Option<i64>,
    /// Scrolls since start, for the tests' screen dump.
    pub scrolled: u64,
    /// Windows that scrolled, as `(top, bottom, left, right, rows)`, waiting for the next flush.
    hints: Vec<(usize, usize, usize, usize, i64)>,
    /// The cells as of the last flush.
    shown: Vec<Cell>,
}

fn int(v: Option<&Value>) -> i64 {
    v.and_then(Value::as_i64).unwrap_or(0)
}

fn size(v: Option<&Value>) -> usize {
    int(v).max(0) as usize
}

fn color(v: i64) -> Option<u32> {
    (v >= 0).then_some(v as u32)
}

impl Grid {
    pub fn new() -> Self {
        Self {
            cols: 0,
            rows: 0,
            cells: Vec::new(),
            fg: 0xc0caf5,
            bg: 0x1a1b26,
            sp: 0xff0000,
            cursor: (0, 0),
            styles: HashMap::new(),
            modes: Vec::new(),
            mode: 0,
            restart: None,
            scrolls: Vec::new(),
            scrolled: 0,
            guifont: None,
            linespace: None,
            hints: Vec::new(),
            shown: Vec::new(),
        }
    }

    pub fn style(&self, id: u32) -> Style {
        self.styles.get(&id).copied().unwrap_or_default()
    }

    /// Foreground and background after defaults and reverse video.
    pub fn colors(&self, style: &Style) -> (u32, u32) {
        let fg = style.fg.unwrap_or(self.fg);
        let bg = style.bg.unwrap_or(self.bg);
        if style.reverse { (bg, fg) } else { (fg, bg) }
    }

    /// Plain text of the screen, one line per row, for the end-to-end tests.
    pub fn text(&self) -> String {
        let mut out = String::new();
        for row in self.cells.chunks(self.cols.max(1)) {
            let line: String = row.iter().map(|c| c.ch).collect();
            out.push_str(line.trim_end());
            out.push('\n');
        }
        out
    }

    /// blinkwait, blinkon and blinkoff of the current mode, when the cursor blinks.
    pub fn blink(&self) -> Option<[u64; 3]> {
        let blink = self.modes.get(self.mode)?.blink;
        (blink[1] > 0 && blink[2] > 0).then_some(blink)
    }

    /// `None` when the active mode hides the cursor, as the Explorer and Welcome panels do.
    pub fn cursor_shape(&self) -> Option<(CursorShape, u32)> {
        let Some(info) = self.modes.get(self.mode) else {
            return Some((CursorShape::Block, 100));
        };
        (self.style(info.attr).blend < 100).then_some((info.shape, info.percent))
    }

    /// Applies one `redraw` batch and returns true when it ended a frame.
    pub fn apply(&mut self, batch: &Value) -> bool {
        let mut flushed = false;
        for event in batch.as_array().into_iter().flatten() {
            let Some(parts) = event.as_array() else {
                continue;
            };
            let Some(name) = parts.first().and_then(Value::as_str) else {
                continue;
            };
            if name == "flush" {
                flushed = true;
            }
            for args in &parts[1..] {
                if let Some(args) = args.as_array() {
                    self.event(name, args);
                }
            }
        }
        if flushed {
            self.settle_hints();
        }
        flushed
    }

    /// Neovim sends no `grid_scroll` while a floating window is open, and the Explorer always
    /// is. So Lua reports each window scroll, and when the window's rows really moved since the
    /// last flush, that becomes a scroll like `grid_scroll`, with the rows that left it.
    fn settle_hints(&mut self) {
        let hints = std::mem::take(&mut self.hints);
        if self.shown.len() == self.cells.len() {
            for (top, bottom, left, right, rows) in hints {
                let covered = self
                    .scrolls
                    .iter()
                    .any(|s| s.top < bottom && top < s.bottom && s.left < right && left < s.right);
                if let (false, Some(rows)) = (covered, self.shift(top, bottom, left, right, rows)) {
                    let n = rows.unsigned_abs() as usize;
                    let leaving = if rows > 0 {
                        top..top + n
                    } else {
                        bottom - n..bottom
                    };
                    let gone = leaving
                        .map(|r| self.shown[r * self.cols + left..r * self.cols + right].to_vec())
                        .collect();
                    self.scrolls.push(Scroll {
                        top,
                        bottom,
                        left,
                        right,
                        rows,
                        gone,
                    });
                    self.scrolled += 1;
                }
            }
        }
        self.shown.clone_from(&self.cells);
    }

    /// How many rows the content of a region moved since the last flush, trying Lua's count
    /// first: wrapped lines make screen rows differ from buffer lines.
    fn shift(
        &self,
        top: usize,
        bottom: usize,
        left: usize,
        right: usize,
        hint: i64,
    ) -> Option<i64> {
        let (bottom, right) = (bottom.min(self.rows), right.min(self.cols));
        if hint == 0 || top >= bottom || left >= right {
            return None;
        }
        let h = (bottom - top) as i64;
        let row = |cells: &[Cell], r: i64| {
            let start = r as usize * self.cols;
            cells[start + left..start + right].to_vec()
        };
        let moved = |k: i64| {
            let rows = top as i64 + 0.max(-k)..bottom as i64 - 0.max(k);
            let total = rows.end - rows.start;
            let same = rows
                .filter(|&r| row(&self.cells, r) == row(&self.shown, r + k))
                .count() as i64;
            total >= 2 && same * 5 >= total * 3
        };
        if (0..h).all(|r| row(&self.cells, top as i64 + r) == row(&self.shown, top as i64 + r)) {
            return None;
        }
        let sign = hint.signum();
        std::iter::once(hint.clamp(-(h - 2), h - 2))
            .chain((1..h - 1).map(|k| k * sign))
            .find(|&k| k != 0 && moved(k))
    }

    fn event(&mut self, name: &str, a: &[Value]) {
        match name {
            "grid_resize" => {
                self.cols = size(a.get(1));
                self.rows = size(a.get(2));
                self.cells = vec![BLANK; self.cols * self.rows];
                self.cursor = (0, 0);
            }
            "grid_clear" => self.cells.fill(BLANK),
            "grid_cursor_goto" => self.cursor = (size(a.get(1)), size(a.get(2))),
            "grid_line" => self.line(a),
            "grid_scroll" => self.scroll(a),
            "default_colors_set" => {
                self.fg = color(int(a.first())).unwrap_or(self.fg);
                self.bg = color(int(a.get(1))).unwrap_or(self.bg);
                self.sp = color(int(a.get(2))).unwrap_or(self.sp);
            }
            "hl_attr_define" => {
                let mut style = Style::default();
                for (key, value) in a.get(1).and_then(Value::as_map).into_iter().flatten() {
                    match key.as_str().unwrap_or("") {
                        "foreground" => style.fg = value.as_i64().and_then(color),
                        "background" => style.bg = value.as_i64().and_then(color),
                        "special" => style.sp = value.as_i64().and_then(color),
                        "reverse" => style.reverse = value.as_bool().unwrap_or(false),
                        "bold" => style.bold = value.as_bool().unwrap_or(false),
                        "italic" => style.italic = value.as_bool().unwrap_or(false),
                        "underline" | "undercurl" | "underdouble" | "underdotted"
                        | "underdashed" => style.underline = true,
                        "strikethrough" => style.strike = value.as_bool().unwrap_or(false),
                        "blend" => style.blend = value.as_u64().unwrap_or(0).min(100) as u8,
                        _ => {}
                    }
                }
                self.styles.insert(int(a.first()) as u32, style);
            }
            "mode_info_set" => {
                self.modes = a
                    .get(1)
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .map(|mode| {
                        let field = |k: &str| {
                            mode.as_map()
                                .and_then(|m| m.iter().find(|(key, _)| key.as_str() == Some(k)))
                                .map(|(_, v)| v)
                        };
                        ModeInfo {
                            shape: match field("cursor_shape").and_then(Value::as_str) {
                                Some("vertical") => CursorShape::Vertical,
                                Some("horizontal") => CursorShape::Horizontal,
                                _ => CursorShape::Block,
                            },
                            percent: field("cell_percentage")
                                .and_then(Value::as_u64)
                                .filter(|p| *p > 0)
                                .unwrap_or(100) as u32,
                            attr: field("attr_id").and_then(Value::as_u64).unwrap_or(0) as u32,
                            blink: ["blinkwait", "blinkon", "blinkoff"]
                                .map(|k| field(k).and_then(Value::as_u64).unwrap_or(0)),
                        }
                    })
                    .collect();
            }
            "mode_change" => self.mode = size(a.get(1)),
            "option_set" if a.first().and_then(Value::as_str) == Some("guifont") => {
                self.guifont = a.get(1).and_then(Value::as_str).map(str::to_string);
            }
            "option_set" if a.first().and_then(Value::as_str) == Some("linespace") => {
                self.linespace = a.get(1).and_then(Value::as_i64);
            }
            "lazycode_scroll" if a.len() >= 5 => {
                let n = |i: usize| size(a.get(i));
                self.hints.push((n(0), n(1), n(2), n(3), int(a.get(4))));
            }
            "restart" => self.restart = a.first().and_then(Value::as_str).map(str::to_string),
            _ => {}
        }
    }

    fn line(&mut self, a: &[Value]) {
        let row = size(a.get(1));
        let mut col = size(a.get(2));
        if row >= self.rows {
            return;
        }
        let mut hl = 0;
        for cell in a.get(3).and_then(Value::as_array).into_iter().flatten() {
            let Some(cell) = cell.as_array() else {
                continue;
            };
            // An empty string is the right half of a double-width character.
            let ch = cell
                .first()
                .and_then(Value::as_str)
                .map(|s| s.chars().next().unwrap_or('\0'))
                .unwrap_or(' ');
            if let Some(id) = cell.get(1).and_then(Value::as_u64) {
                hl = id as u32;
            }
            let repeat = cell.get(2).and_then(Value::as_u64).unwrap_or(1) as usize;
            for _ in 0..repeat {
                if col >= self.cols {
                    return;
                }
                self.cells[row * self.cols + col] = Cell { ch, hl };
                col += 1;
            }
        }
    }

    fn scroll(&mut self, a: &[Value]) {
        let (top, bottom) = (size(a.get(1)), size(a.get(2)).min(self.rows));
        let (left, right) = (size(a.get(3)), size(a.get(4)).min(self.cols));
        let rows = int(a.get(5));
        if left >= right || top >= bottom {
            return;
        }
        let distance = rows.unsigned_abs() as usize;
        if distance >= bottom - top {
            return;
        }
        let leaving = if rows > 0 {
            top..top + distance
        } else {
            bottom - distance..bottom
        };
        let gone = leaving
            .map(|r| self.cells[r * self.cols + left..r * self.cols + right].to_vec())
            .collect();
        self.scrolls.push(Scroll {
            top,
            bottom,
            left,
            right,
            rows,
            gone,
        });
        self.scrolled += 1;
        let mut copy = |target: usize| {
            let source = if rows > 0 {
                target + distance
            } else {
                target - distance
            };
            let from = source * self.cols + left;
            self.cells
                .copy_within(from..from + right - left, target * self.cols + left);
        };
        if rows > 0 {
            (top..bottom - distance).for_each(&mut copy);
        } else {
            (top + distance..bottom).rev().for_each(&mut copy);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(name: &str, args: Vec<Value>) -> Value {
        Value::Array(vec![name.into(), Value::Array(args)])
    }

    fn text(grid: &Grid, row: usize) -> String {
        grid.cells[row * grid.cols..(row + 1) * grid.cols]
            .iter()
            .map(|c| c.ch)
            .collect()
    }

    fn line(row: i64, s: &str) -> Value {
        let cells = s
            .chars()
            .map(|c| Value::Array(vec![c.to_string().into(), 0.into()]))
            .collect();
        event(
            "grid_line",
            vec![
                1.into(),
                row.into(),
                0.into(),
                Value::Array(cells),
                false.into(),
            ],
        )
    }

    fn sized(lines: &[&str]) -> Grid {
        let mut grid = Grid::new();
        let mut batch = vec![event(
            "grid_resize",
            vec![1.into(), 3.into(), (lines.len() as i64).into()],
        )];
        batch.extend(lines.iter().enumerate().map(|(i, s)| line(i as i64, s)));
        grid.apply(&Value::Array(batch));
        grid
    }

    fn scroll(grid: &mut Grid, rows: i64) {
        let args = vec![
            1.into(),
            0.into(),
            (grid.rows as i64).into(),
            0.into(),
            3.into(),
            rows.into(),
            0.into(),
        ];
        grid.apply(&Value::Array(vec![event("grid_scroll", args)]));
    }

    #[test]
    fn line_keeps_highlight_and_repeats() {
        let mut grid = sized(&["   "]);
        let cells = Value::Array(vec![
            Value::Array(vec!["a".into(), 7.into(), 2.into()]),
            Value::Array(vec!["b".into()]),
        ]);
        let args = vec![1.into(), 0.into(), 0.into(), cells, false.into()];
        grid.apply(&Value::Array(vec![event("grid_line", args)]));
        assert_eq!(text(&grid, 0), "aab");
        assert!(grid.cells.iter().all(|c| c.hl == 7));
    }

    #[test]
    fn scroll_moves_rows_both_ways() {
        let mut grid = sized(&["aaa", "bbb", "ccc"]);
        scroll(&mut grid, 1);
        assert_eq!(
            (text(&grid, 0), text(&grid, 1)),
            ("bbb".into(), "ccc".into())
        );
        let gone: String = grid.scrolls[0].gone[0].iter().map(|c| c.ch).collect();
        assert_eq!((grid.scrolls[0].rows, gone.as_str()), (1, "aaa"));
        let mut grid = sized(&["aaa", "bbb", "ccc"]);
        scroll(&mut grid, -1);
        assert_eq!(
            (text(&grid, 1), text(&grid, 2)),
            ("aaa".into(), "bbb".into())
        );
    }

    #[test]
    fn reported_scroll_becomes_an_animation_when_rows_moved() {
        let flush = || Value::Array(vec!["flush".into()]);
        let hint = |rows: i64| {
            event(
                "lazycode_scroll",
                vec![0.into(), 6.into(), 0.into(), 3.into(), rows.into()],
            )
        };
        let mut grid = sized(&["aaa", "bbb", "ccc", "ddd", "eee", "fff"]);
        grid.apply(&Value::Array(vec![flush()]));
        // Wrapped lines: Lua says 1 line, but the screen moved 2 rows. Row 5 is new text.
        let moved = ["ccc", "ddd", "eee", "fff", "ggg", "hhh"];
        let mut batch = vec![hint(1)];
        batch.extend(moved.iter().enumerate().map(|(i, s)| line(i as i64, s)));
        batch.push(flush());
        grid.apply(&Value::Array(batch));
        let s = &grid.scrolls[0];
        let gone: Vec<String> = s
            .gone
            .iter()
            .map(|r| r.iter().map(|c| c.ch).collect())
            .collect();
        assert_eq!(
            (s.rows, gone),
            (2, vec!["aaa".to_string(), "bbb".to_string()])
        );
        // A report whose rows did not move, like a redraw of other text, animates nothing.
        grid.scrolls.clear();
        let other = ["xxx", "yyy", "zzz", "qqq", "www", "vvv"];
        let mut batch = vec![hint(1)];
        batch.extend(other.iter().enumerate().map(|(i, s)| line(i as i64, s)));
        batch.push(flush());
        grid.apply(&Value::Array(batch));
        assert!(grid.scrolls.is_empty());
    }

    #[test]
    fn blended_cursor_is_hidden() {
        let mut grid = Grid::new();
        let attrs = Value::Map(vec![("blend".into(), 100.into())]);
        let mode = Value::Map(vec![("attr_id".into(), 9.into())]);
        grid.apply(&Value::Array(vec![
            event("hl_attr_define", vec![9.into(), attrs]),
            event("mode_info_set", vec![true.into(), Value::Array(vec![mode])]),
        ]));
        assert_eq!(grid.cursor_shape(), None);
    }
}
