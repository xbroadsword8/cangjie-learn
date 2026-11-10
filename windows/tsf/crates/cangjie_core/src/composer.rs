//! 按鍵狀態機：倉頡組字、選字、標點、中英切換（對應 cjlearn/composer.py）。
//! 鍵用 X keysym 名稱字串表示（"a"、"space"、"comma"、"Shift_L"…）。
use crate::model::{Candidate, Model};
use std::sync::{Arc, Mutex};

pub const MAX_CODE: usize = 5;
pub const PAGE: usize = 9;

pub fn radical(c: char) -> char {
    const R: [char; 26] = ['日','月','金','木','水','火','土','竹','戈','十','大','中','一','弓','人','心','手','口','尸','廿','山','女','田','難','卜','重'];
    R[(c as u8 - b'a') as usize]
}

/// Ctrl＋標點 → 中文標點
pub fn cjk_punct(key: &str) -> Option<&'static str> {
    Some(match key {
        "comma" => "，", "period" => "。", "semicolon" => "；", "colon" => "：",
        "question" => "？", "exclam" => "！", "apostrophe" => "、", "backslash" => "、",
        "bracketleft" => "「", "bracketright" => "」", "braceleft" => "『", "braceright" => "』",
        "parenleft" => "（", "parenright" => "）", "less" => "《", "greater" => "》",
        "quotedbl" => "＂", "slash" => "／", "asciitilde" => "～", "asciicircum" => "……",
        "underscore" => "——", "minus" => "－", "at" => "＠", "numbersign" => "＃",
        "dollar" => "＄", "percent" => "％", "ampersand" => "＆", "asterisk" => "＊",
        "plus" => "＋", "equal" => "＝", "bar" => "｜", "grave" => "‵",
        _ => return None,
    })
}

pub fn ascii_punct(key: &str) -> Option<&'static str> {
    Some(match key {
        "comma" => ",", "period" => ".", "semicolon" => ";", "colon" => ":", "question" => "?",
        "exclam" => "!", "apostrophe" => "'", "quotedbl" => "\"", "backslash" => "\\", "slash" => "/",
        "bracketleft" => "[", "bracketright" => "]", "braceleft" => "{", "braceright" => "}",
        "parenleft" => "(", "parenright" => ")", "less" => "<", "greater" => ">", "asciitilde" => "~",
        "asciicircum" => "^", "underscore" => "_", "minus" => "-", "at" => "@", "numbersign" => "#",
        "dollar" => "$", "percent" => "%", "ampersand" => "&", "asterisk" => "*", "plus" => "+",
        "equal" => "=", "bar" => "|", "grave" => "`",
        _ => return None,
    })
}

fn full_punct_key(key: &str) -> bool {
    matches!(key, "comma" | "period" | "semicolon" | "colon" | "question" | "exclam" | "backslash"
        | "bracketleft" | "bracketright" | "braceleft" | "braceright"
        | "parenleft" | "parenright" | "less" | "greater")
}

fn context_break(key: &str) -> bool {
    matches!(key, "Return" | "KP_Enter" | "Tab" | "Left" | "Right" | "Up" | "Down" | "Home" | "End"
        | "Page_Up" | "Page_Down" | "Delete" | "Escape")
}

/// 單一字元鍵（Python 的 len(key)==1，以碼點計）。
fn single(key: &str) -> Option<char> {
    let mut it = key.chars();
    let c = it.next()?;
    if it.next().is_none() { Some(c) } else { None }
}

/// handled：是否吃掉此鍵；commit：要送出的文字。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyResult {
    pub handled: bool,
    pub commit: String,
}

fn res(handled: bool, commit: impl Into<String>) -> KeyResult {
    KeyResult { handled, commit: commit.into() }
}

pub struct Composer {
    pub model: Arc<Mutex<Model>>,
    pub chinese: bool,
    pub code: String,
    pub cands: Vec<Candidate>,
    pub page: usize,
    pub cursor: usize,
    pub ctx: String,
    pub clear_on_error: bool,
    pub full_punct: bool,
    shift_alone: bool,
}

impl Composer {
    pub fn new(model: Arc<Mutex<Model>>) -> Self {
        Composer {
            model, chinese: true, code: String::new(), cands: vec![], page: 0, cursor: 0,
            ctx: String::new(), clear_on_error: true, full_punct: false, shift_alone: false,
        }
    }

    // --- 對外狀態 ---
    pub fn preedit(&self) -> String {
        self.code.chars().map(radical).collect()
    }

    pub fn page_cands(&self) -> &[Candidate] {
        let start = (self.page * PAGE).min(self.cands.len());
        let end = ((self.page + 1) * PAGE).min(self.cands.len());
        &self.cands[start..end]
    }

    /// 焦點改變、游標移動：清組字並斷開上文。
    pub fn reset(&mut self) {
        self.clear();
        self.ctx.clear();
    }

    // --- 內部 ---
    fn refresh(&mut self) {
        self.cands = self.model.lock().unwrap().candidates(&self.code, &self.ctx);
        self.page = 0;
        self.cursor = 0;
    }

    fn clear(&mut self) {
        self.code.clear();
        self.cands.clear();
        self.page = 0;
        self.cursor = 0;
    }

    fn pick(&mut self, idx_in_page: Option<usize>) -> String {
        let i = idx_in_page.unwrap_or(self.cursor);
        let ch = match self.page_cands().get(i) {
            Some(c) => c.ch.clone(),
            None => return String::new(),
        };
        let corrected = self.page * PAGE + i > 0;
        self.model.lock().unwrap().learn(&ch, &self.ctx, corrected);
        let joined = format!("{}{}", self.ctx, ch);
        self.ctx = crate::model::tail_chars(&joined, 3).to_string();
        self.clear();
        ch
    }

    fn flush(&mut self) -> String {
        if self.code.is_empty() { return String::new(); }
        if self.cands.is_empty() {
            self.clear();
            return String::new();
        }
        self.pick(Some(0))
    }

    // --- 主入口 ---
    pub fn process(&mut self, key: &str, ctrl: bool, _shift: bool, alt: bool, release: bool) -> KeyResult {
        if key == "Shift_L" || key == "Shift_R" {
            if !release {
                self.shift_alone = !(ctrl || alt);
                return res(false, "");
            }
            if self.shift_alone {
                self.shift_alone = false;
                let commit = self.code.clone();
                self.clear();
                self.chinese = !self.chinese;
                self.ctx.clear();
                return KeyResult { handled: !commit.is_empty(), commit };
            }
            return res(false, "");
        }
        if release { return res(false, ""); }
        self.shift_alone = false;

        if ctrl && !alt {
            if let Some(p) = cjk_punct(key) {
                let out = self.flush() + p;
                self.ctx.clear();
                return res(true, out);
            }
        }

        if !self.chinese {
            if context_break(key) { self.ctx.clear(); }
            return res(false, "");
        }

        if ctrl || alt { return res(false, ""); }

        let one = single(key);
        if let Some(c) = one {
            if c.is_ascii_lowercase() {
                if self.code.chars().count() >= MAX_CODE { return res(true, ""); }
                self.code.push(c);
                self.refresh();
                return res(true, "");
            }
        }

        if let Some(p) = cjk_punct(key).filter(|_| self.full_punct && full_punct_key(key)) {
            let out = self.flush() + p;
            self.ctx.clear();
            return res(true, out);
        }

        if !self.code.is_empty() {
            return self.process_composing(key);
        }

        if key == "BackSpace" {
            self.ctx.pop();
        } else if context_break(key) || key == "space" || ascii_punct(key).is_some() {
            self.ctx.clear();
        } else if matches!(one, Some(c) if c.is_ascii_uppercase()) {
            self.ctx.clear();
        }
        res(false, "")
    }

    fn process_composing(&mut self, key: &str) -> KeyResult {
        let one = single(key);
        let digit = one.filter(|c| ('1'..='9').contains(c));
        let page_len = self.page_cands().len();
        if self.cands.is_empty() && self.clear_on_error && (key == "space" || digit.is_some()) {
            self.clear();
            return res(true, "");
        }
        if key == "space" {
            return res(true, self.pick(None));
        }
        if let Some(d) = digit {
            let i = d as usize - '1' as usize;
            if i < page_len { return res(true, self.pick(Some(i))); }
            return res(true, "");
        }
        match key {
            "BackSpace" => {
                self.code.pop();
                if !self.code.is_empty() { self.refresh(); } else { self.clear(); }
                return res(true, "");
            }
            "Escape" => {
                self.clear();
                return res(true, "");
            }
            "Return" | "KP_Enter" => {
                let raw = std::mem::take(&mut self.code);
                self.clear();
                self.ctx.clear();
                return res(true, raw);
            }
            "Page_Down" | "equal" | "KP_Page_Down" => {
                if (self.page + 1) * PAGE < self.cands.len() {
                    self.page += 1;
                    self.cursor = 0;
                }
                return res(true, "");
            }
            "Page_Up" | "minus" | "KP_Page_Up" => {
                if self.page > 0 {
                    self.page -= 1;
                    self.cursor = 0;
                }
                return res(true, "");
            }
            "Down" | "Right" => {
                if self.cursor + 1 < page_len {
                    self.cursor += 1;
                } else if (self.page + 1) * PAGE < self.cands.len() {
                    self.page += 1;
                    self.cursor = 0;
                }
                return res(true, "");
            }
            "Up" | "Left" => {
                if self.cursor > 0 {
                    self.cursor -= 1;
                } else if self.page > 0 {
                    self.page -= 1;
                    self.cursor = PAGE - 1;
                }
                return res(true, "");
            }
            _ => {}
        }
        if let Some(p) = ascii_punct(key) {
            let out = self.flush() + p;
            self.ctx.clear();
            return res(true, out);
        }
        if let Some(c) = one {
            if c.is_ascii_uppercase() {
                let out = self.flush() + key;
                self.ctx.clear();
                return res(true, out);
            }
        }
        let out = self.flush();
        self.ctx.clear();
        res(false, out)
    }
}
