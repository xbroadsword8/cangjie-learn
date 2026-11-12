//! 全形英數（Shift＋空白）：切換、中英兩種模式的輸出、組字中途的行為。
use cangjie_core::{Composer, Model};
use std::sync::{Arc, Mutex};

fn composer() -> Composer {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
    let user_db = std::env::temp_dir().join(format!("cangjie_core_fullshape_{}_{:?}.db", std::process::id(), std::thread::current().id()));
    let _ = std::fs::remove_file(&user_db);
    Composer::new(Arc::new(Mutex::new(Model::open(root.join("data/model.db"), &user_db).unwrap())))
}

/// 一般按鍵（不按 Ctrl/Alt）；回傳 (handled, commit)。
fn key(c: &mut Composer, k: &str, shift: bool) -> (bool, String) {
    let r = c.process(k, false, shift, false, false);
    (r.handled, r.commit)
}

fn toggle(c: &mut Composer) {
    c.process("Shift_L", false, true, false, false);
    assert_eq!(key(c, "space", true), (true, String::new()));
    // 放開 Shift 不能被當成單按切中英
    let chinese = c.chinese;
    c.process("Shift_L", false, false, false, true);
    assert_eq!(c.chinese, chinese);
}

#[test]
fn toggle_on_and_off() {
    let mut c = composer();
    assert!(!c.full_shape);
    toggle(&mut c);
    assert!(c.full_shape);
    assert!(c.chinese);
    toggle(&mut c);
    assert!(!c.full_shape);
}

#[test]
fn english_mode_outputs_full_width() {
    let mut c = composer();
    c.chinese = false;
    assert_eq!(key(&mut c, "a", false), (false, String::new()));
    toggle(&mut c);
    assert_eq!(key(&mut c, "a", false), (true, "ａ".into()));
    assert_eq!(key(&mut c, "A", true), (true, "Ａ".into()));
    assert_eq!(key(&mut c, "1", false), (true, "１".into()));
    assert_eq!(key(&mut c, "space", false), (true, "\u{3000}".into()));
    assert_eq!(key(&mut c, "at", true), (true, "＠".into()));
    assert_eq!(key(&mut c, "comma", false), (true, "，".into()));
    // 控制鍵照常交給應用程式
    assert_eq!(key(&mut c, "Return", false), (false, String::new()));
    assert_eq!(key(&mut c, "BackSpace", false), (false, String::new()));
    // Ctrl＋字母（快速鍵）不轉
    let r = c.process("c", true, false, false, false);
    assert!(!r.handled);
}

#[test]
fn chinese_mode_outputs_full_width_symbols() {
    let mut c = composer();
    toggle(&mut c);
    // 小寫字母照常組字
    assert_eq!(key(&mut c, "a", false), (true, String::new()));
    assert_eq!(c.code, "a");
    let (h, out) = key(&mut c, "space", false);
    assert!(h && !out.is_empty());
    // 沒在組字：數字、大寫、空白、符號都是全形
    assert_eq!(key(&mut c, "5", false), (true, "５".into()));
    assert_eq!(key(&mut c, "B", true), (true, "Ｂ".into()));
    assert_eq!(key(&mut c, "space", false), (true, "\u{3000}".into()));
    assert_eq!(key(&mut c, "slash", false), (true, "／".into()));
    // 組字中按標點：先送第一候選再接全形標點
    key(&mut c, "a", false);
    let (h, out) = key(&mut c, "period", false);
    assert!(h && out.ends_with('．') && out.chars().count() == 2, "{out}");
    // 組字中按 Enter：字碼以全形字母送出
    key(&mut c, "a", false);
    key(&mut c, "b", false);
    assert_eq!(key(&mut c, "Return", false), (true, "ａｂ".into()));
}

#[test]
fn half_width_unchanged() {
    let mut c = composer();
    assert_eq!(key(&mut c, "5", false), (false, String::new()));
    assert_eq!(key(&mut c, "space", false), (false, String::new()));
    // Shift＋空白切換時組到一半的字碼留著
    key(&mut c, "a", false);
    toggle(&mut c);
    assert_eq!(c.code, "a");
}
