//! Translates window key events to Neovim key notation.
use winit::keyboard::{Key, ModifiersState, NamedKey};

fn named(key: NamedKey) -> Option<&'static str> {
    use NamedKey::*;
    Some(match key {
        Enter => "CR",
        Tab => "Tab",
        Backspace => "BS",
        Escape => "Esc",
        Delete => "Del",
        Insert => "Insert",
        Home => "Home",
        End => "End",
        PageUp => "PageUp",
        PageDown => "PageDown",
        ArrowUp => "Up",
        ArrowDown => "Down",
        ArrowLeft => "Left",
        ArrowRight => "Right",
        Space => "Space",
        F1 => "F1",
        F2 => "F2",
        F3 => "F3",
        F4 => "F4",
        F5 => "F5",
        F6 => "F6",
        F7 => "F7",
        F8 => "F8",
        F9 => "F9",
        F10 => "F10",
        F11 => "F11",
        F12 => "F12",
        _ => return None,
    })
}

fn escape(c: char) -> String {
    match c {
        '<' => "lt".into(),
        '\\' => "Bslash".into(),
        '|' => "Bar".into(),
        c => c.to_string(),
    }
}

fn prefix(m: ModifiersState, shift: bool) -> String {
    let mut p = String::new();
    for (on, s) in [
        (m.control_key(), "C-"),
        (m.alt_key(), "A-"),
        (m.super_key(), "D-"),
        (shift, "S-"),
    ] {
        if on {
            p.push_str(s);
        }
    }
    p
}

/// `text` is the composed text from the window system, so accents and dead keys arrive intact.
pub fn to_nvim(key: &Key, text: Option<&str>, m: ModifiersState) -> Option<String> {
    if let Key::Named(k) = key
        && let Some(name) = named(*k)
    {
        return Some(format!("<{}{}>", prefix(m, m.shift_key()), name));
    }
    if !(m.control_key() || m.alt_key() || m.super_key()) {
        let text = text.filter(|t| !t.chars().any(char::is_control))?;
        return Some(text.replace('<', "<lt>"));
    }
    let Key::Character(s) = key else {
        return None;
    };
    let mut chars = s.chars();
    let c = chars.next()?;
    if chars.next().is_some() {
        return None;
    }
    // Shift is explicit for letters, while symbols already carry it: Ctrl+Shift+1 is <C-!>.
    let letter = c.is_alphabetic();
    let shown = if letter { c.to_lowercase().next()? } else { c };
    Some(format!(
        "<{}{}>",
        prefix(m, letter && m.shift_key()),
        escape(shown)
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ch(s: &str) -> Key {
        Key::Character(s.into())
    }

    #[test]
    fn plain_text_is_escaped_and_keeps_accents() {
        let none = ModifiersState::empty();
        assert_eq!(to_nvim(&ch("<"), Some("<"), none).as_deref(), Some("<lt>"));
        assert_eq!(to_nvim(&ch("ç"), Some("ç"), none).as_deref(), Some("ç"));
    }

    #[test]
    fn shortcuts_use_nvim_notation() {
        let ctrl = ModifiersState::CONTROL;
        let shift = ctrl | ModifiersState::SHIFT;
        assert_eq!(to_nvim(&ch("s"), None, ctrl).as_deref(), Some("<C-s>"));
        assert_eq!(to_nvim(&ch("E"), None, shift).as_deref(), Some("<C-S-e>"));
        assert_eq!(to_nvim(&ch("<"), None, ctrl).as_deref(), Some("<C-lt>"));
        assert_eq!(
            to_nvim(&ch("s"), None, ModifiersState::SUPER).as_deref(),
            Some("<D-s>")
        );
    }

    #[test]
    fn named_keys_include_modifiers() {
        let key = Key::Named(NamedKey::ArrowLeft);
        assert_eq!(
            to_nvim(&key, None, ModifiersState::SHIFT).as_deref(),
            Some("<S-Left>")
        );
        assert_eq!(
            to_nvim(&Key::Named(NamedKey::Shift), None, ModifiersState::SHIFT),
            None
        );
    }
}
