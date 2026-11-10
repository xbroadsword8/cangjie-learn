//! PeerWatcher：sync\ 裡其他電腦的次數會被讀進 Model，自己的檔不重複算，沒變動不重讀
//! （對應 tests/test_windows_pime.py::test_peers_and_sync_status）。
use cangjie_core::sync::PeerWatcher;
use cangjie_core::Model;
use std::sync::Mutex;
use std::time::Duration;

#[test]
fn peers_change_ranking() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
    let dir = std::env::temp_dir().join(format!("cangjie_core_peers_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("sync")).unwrap();
    let model = Mutex::new(Model::open(root.join("data/model.db"), dir.join("user.db")).unwrap());
    let picked = model.lock().unwrap().candidates("a", "")[1].ch.clone();
    let first = model.lock().unwrap().candidates("a", "")[0].ch.clone();
    assert_ne!(picked, first);

    std::fs::write(dir.join("settings.json"), r#"{"sync_remote":"x","sync_name":"me"}"#).unwrap();
    std::fs::write(dir.join("sync/other.json"), format!(r#"{{"uni":{{"{picked}":50}},"bi":{{}}}}"#)).unwrap();
    std::fs::write(dir.join("sync/me.json"), format!(r#"{{"uni":{{"{first}":9999}},"bi":{{}}}}"#)).unwrap();

    let mut w = PeerWatcher::new(&dir, Duration::from_secs(60));
    assert!(w.poll(&model), "第一次一定要讀");
    assert_eq!(model.lock().unwrap().candidates("a", "")[0].ch, picked);   // 別台學的算進來，自己的檔不算
    assert!(!w.poll(&model), "間隔內不再檢查");

    let mut w2 = PeerWatcher::new(&dir, Duration::ZERO);
    assert!(w2.poll(&model));
    assert!(!w2.poll(&model), "檔案沒變不重讀");
    std::fs::write(dir.join("sync/other.json"), r#"{"uni":{},"bi":{}}"#).unwrap();
    assert!(w2.poll(&model), "檔案變了要重讀");
    assert_eq!(model.lock().unwrap().candidates("a", "")[0].ch, first);
    let _ = std::fs::remove_dir_all(&dir);
}
