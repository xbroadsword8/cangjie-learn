//! 使用者選項：存在學習資料旁的 settings.json（對應 cjlearn/settings.py，三平台格式相同）。
use serde_json::{Map, Value};
use std::path::Path;

#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub clear_on_error: bool,
    pub full_punct: bool,
    pub full_shape: bool,
    pub sync_remote: String,
    pub sync_name: String,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { clear_on_error: true, full_punct: false, full_shape: false, sync_remote: String::new(), sync_name: String::new() }
    }
}

/// 讀取；檔案不存在、壞掉、不是物件、型別不符的欄位一律用預設值（同 Python load）。
pub fn load(path: impl AsRef<Path>) -> Settings {
    let mut s = Settings::default();
    let Ok(text) = std::fs::read_to_string(path) else { return s };
    let Ok(Value::Object(m)) = serde_json::from_str::<Value>(&text) else { return s };
    if let Some(Value::Bool(b)) = m.get("clear_on_error") { s.clear_on_error = *b; }
    if let Some(Value::Bool(b)) = m.get("full_punct") { s.full_punct = *b; }
    if let Some(Value::Bool(b)) = m.get("full_shape") { s.full_shape = *b; }
    if let Some(Value::String(v)) = m.get("sync_remote") { s.sync_remote = v.clone(); }
    if let Some(Value::String(v)) = m.get("sync_name") { s.sync_name = v.clone(); }
    s
}

/// 寫入（indent=1、不跳脫非 ASCII，先寫 .tmp 再改名）。
pub fn save(path: impl AsRef<Path>, s: &Settings) -> std::io::Result<()> {
    let p = path.as_ref();
    if let Some(dir) = p.parent() {
        if !dir.as_os_str().is_empty() { std::fs::create_dir_all(dir)?; }
    }
    let mut m = Map::new();
    m.insert("clear_on_error".into(), Value::Bool(s.clear_on_error));
    m.insert("full_punct".into(), Value::Bool(s.full_punct));
    m.insert("full_shape".into(), Value::Bool(s.full_shape));
    m.insert("sync_remote".into(), Value::String(s.sync_remote.clone()));
    m.insert("sync_name".into(), Value::String(s.sync_name.clone()));
    let mut buf = Vec::new();
    {
        use serde::Serialize;
        let fmt = serde_json::ser::PrettyFormatter::with_indent(b" ");
        let mut ser = serde_json::Serializer::with_formatter(&mut buf, fmt);
        Value::Object(m).serialize(&mut ser).map_err(std::io::Error::other)?;
    }
    let mut tmp = p.as_os_str().to_owned();
    tmp.push(".tmp");
    let tmp = std::path::PathBuf::from(tmp);
    std::fs::write(&tmp, buf)?;
    std::fs::rename(&tmp, p)
}

/// 重讀再改再存（同 Python update）。
pub fn update(path: impl AsRef<Path>, f: impl FnOnce(&mut Settings)) -> std::io::Result<Settings> {
    let mut s = load(path.as_ref());
    f(&mut s);
    save(path.as_ref(), &s)?;
    Ok(s)
}
