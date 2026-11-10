//! 學習資料同步的輸入法端（對應 cjlearn/sync.py 的 read_peers／PeerWatcher／status_text）：
//! 只讀 `<data_dir>\sync\*.json` 與 `sync_status.json`，不連網；同步本身由排程跑 sync.py。
use crate::model::Model;
use crate::settings;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const SYNC_DIR: &str = "sync";
pub const STATUS_FILE: &str = "sync_status.json";

/// 讀其他電腦（檔名不等於 self_name）的次數並相加；壞檔、非正整數的值略過。
pub fn read_peers(sync_dir: impl AsRef<Path>, self_name: &str) -> (HashMap<String, i64>, HashMap<String, i64>) {
    let (mut uni, mut bi) = (HashMap::new(), HashMap::new());
    let mut files: Vec<PathBuf> = match std::fs::read_dir(sync_dir.as_ref()) {
        Ok(rd) => rd.filter_map(Result::ok).map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "json")).collect(),
        Err(_) => return (uni, bi),
    };
    files.sort();
    for f in files {
        if f.file_stem().is_some_and(|s| s == self_name) { continue; }
        let Ok(text) = std::fs::read_to_string(&f) else { continue };
        let Ok(Value::Object(d)) = serde_json::from_str::<Value>(&text) else { continue };
        for (key, dst) in [("uni", &mut uni), ("bi", &mut bi)] {
            if let Some(Value::Object(m)) = d.get(key) {
                for (k, n) in m {
                    if let Value::Number(n) = n {
                        if let Some(n) = n.as_i64().filter(|n| *n > 0) {
                            *dst.entry(k.clone()).or_insert(0) += n;
                        }
                    }
                }
            }
        }
    }
    (uni, bi)
}

/// sync/ 有變動才重讀；最多每 interval 檢查一次。
pub struct PeerWatcher {
    data_dir: PathBuf,
    interval: Duration,
    next: Option<Instant>,
    sig: Option<(String, Vec<(String, u128, u64)>)>,
}

impl PeerWatcher {
    pub fn new(data_dir: impl Into<PathBuf>, interval: Duration) -> Self {
        PeerWatcher { data_dir: data_dir.into(), interval, next: None, sig: None }
    }

    /// 有重讀並 set_peers 回傳 true。
    pub fn poll(&mut self, model: &Mutex<Model>) -> bool {
        let now = Instant::now();
        if self.next.is_some_and(|t| now < t) { return false; }
        self.next = Some(now + self.interval);
        let name = settings::load(self.data_dir.join("settings.json")).sync_name;
        let dir = self.data_dir.join(SYNC_DIR);
        let sig = (name.clone(), Self::signature(&dir));
        if self.sig.as_ref() == Some(&sig) { return false; }
        self.sig = Some(sig);
        let (uni, bi) = if name.is_empty() { (HashMap::new(), HashMap::new()) } else { read_peers(&dir, &name) };
        model.lock().unwrap().set_peers(uni, bi);
        true
    }

    fn signature(dir: &Path) -> Vec<(String, u128, u64)> {
        let Ok(rd) = std::fs::read_dir(dir) else { return vec![] };
        let mut v: Vec<(String, u128, u64)> = rd.filter_map(Result::ok)
            .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
            .filter_map(|e| {
                let m = e.metadata().ok()?;
                let t = m.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_nanos();
                Some((e.file_name().to_string_lossy().into_owned(), t, m.len()))
            }).collect();
        v.sort();
        v
    }
}

fn read_status(data_dir: &Path) -> Option<serde_json::Map<String, Value>> {
    let text = std::fs::read_to_string(data_dir.join(STATUS_FILE)).ok()?;
    match serde_json::from_str::<Value>(&text).ok()? {
        Value::Object(m) if !m.is_empty() => Some(m),
        _ => None,
    }
}

fn secs(v: Option<&Value>) -> i64 {
    v.and_then(Value::as_f64).unwrap_or(0.0) as i64
}

fn ago(now: i64, t: i64) -> String {
    let m = (now - t).div_euclid(60);
    if m < 1 { "剛剛".into() }
    else if m < 60 { format!("{m} 分鐘前") }
    else if m < 2880 { format!("{} 小時前", m / 60) }
    else { format!("{} 天前", m / 1440) }
}

/// 給輸入法選單用的一行字；沒設定同步回傳空字串。now 為 Unix 秒（None＝現在）。
pub fn status_text(data_dir: impl AsRef<Path>, now: Option<i64>) -> String {
    let dir = data_dir.as_ref();
    if settings::load(dir.join("settings.json")).sync_remote.is_empty() { return String::new(); }
    let Some(st) = read_status(dir) else { return "同步：還沒執行過".into() };
    let now = now.unwrap_or_else(|| SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0));
    if st.get("ok").is_some_and(|v| v.as_bool() == Some(true)) {
        return format!("同步：{}成功", ago(now, secs(st.get("time"))));
    }
    let last_ok = secs(st.get("last_ok"));
    let last = if last_ok != 0 { format!("（上次成功 {}）", ago(now, last_ok)) } else { "（從沒成功過）".into() };
    let msg: String = st.get("message").and_then(Value::as_str).unwrap_or("").chars().take(60).collect();
    format!("⚠ 同步失敗{last}：{msg}")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("cangjie_core_sync_{}_{}", tag, std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn status_text_cases() {
        let d = tmp("status");
        assert_eq!(status_text(&d, None), "");                       // 沒設定同步
        std::fs::write(d.join("settings.json"), r#"{"sync_remote":"x","sync_name":"me"}"#).unwrap();
        assert_eq!(status_text(&d, None), "同步：還沒執行過");
        std::fs::write(d.join(STATUS_FILE), r#"{"ok":true,"time":1000,"message":"m","last_ok":1000}"#).unwrap();
        assert_eq!(status_text(&d, Some(1000)), "同步：剛剛成功");
        assert_eq!(status_text(&d, Some(1000 + 5 * 60)), "同步：5 分鐘前成功");
        assert_eq!(status_text(&d, Some(1000 + 3 * 3600)), "同步：3 小時前成功");
        assert_eq!(status_text(&d, Some(1000 + 3 * 86400)), "同步：3 天前成功");
        std::fs::write(d.join(STATUS_FILE), r#"{"ok":false,"time":5000,"message":"連不上","last_ok":1000}"#).unwrap();
        assert_eq!(status_text(&d, Some(1000 + 3 * 3600)), "⚠ 同步失敗（上次成功 3 小時前）：連不上");
        std::fs::write(d.join(STATUS_FILE), r#"{"ok":false,"time":5000,"message":"x","last_ok":0}"#).unwrap();
        assert_eq!(status_text(&d, Some(6000)), "⚠ 同步失敗（從沒成功過）：x");
        let long = "字".repeat(100);
        std::fs::write(d.join(STATUS_FILE), format!(r#"{{"ok":false,"time":1,"message":"{long}"}}"#)).unwrap();
        assert!(status_text(&d, Some(2)).ends_with(&"字".repeat(60)));
        assert_eq!(status_text(&d, Some(2)).chars().filter(|c| *c == '字').count(), 60);
        std::fs::write(d.join(STATUS_FILE), "壞掉").unwrap();
        assert_eq!(status_text(&d, None), "同步：還沒執行過");           // 壞檔視同沒有
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn read_peers_skips_self_and_bad_files() {
        let d = tmp("peers");
        std::fs::write(d.join("other.json"), r#"{"uni":{"日":5,"月":0,"金":-1,"木":1.5,"水":true},"bi":{"我日":2}}"#).unwrap();
        std::fs::write(d.join("third.json"), r#"{"uni":{"日":3},"bi":{"我日":1}}"#).unwrap();
        std::fs::write(d.join("me.json"), r#"{"uni":{"日":9999},"bi":{}}"#).unwrap();
        std::fs::write(d.join("broken.json"), "{{{").unwrap();
        std::fs::write(d.join("list.json"), "[1]").unwrap();
        std::fs::write(d.join("note.txt"), r#"{"uni":{"日":1}}"#).unwrap();
        let (uni, bi) = read_peers(&d, "me");
        assert_eq!(uni.get("日"), Some(&8));
        assert_eq!(uni.len(), 1);
        assert_eq!(bi.get("我日"), Some(&3));
        let _ = std::fs::remove_dir_all(&d);
    }
}
