//! 打很多次「自己」不該讓無上文的「已經」變成「己經」（對應 tests/test_composer.py::test_context_decided_learning_not_char_preference）。
use cangjie_core::Model;
use std::collections::HashMap;

#[test]
fn context_decided_learning_not_char_preference() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
    let dir = std::env::temp_dir().join(format!("cangjie_core_expl_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let db = root.join("data/model.db");
    let mut m = Model::open(&db, dir.join("user.db")).unwrap();
    for _ in 0..12 { m.learn("己", "自", false); }
    for _ in 0..3 { m.learn("已", "前", false); }
    assert_eq!(m.candidates("su", "")[0].ch, "已");
    assert_eq!(m.candidates("su", "我")[0].ch, "已");
    assert_eq!(m.candidates("su", "自")[0].ch, "己");
    drop(m);
    let mut m2 = Model::open(&db, dir.join("user.db")).unwrap();
    assert_eq!(m2.candidates("su", "")[0].ch, "已");
    // 別台電腦學到的「自己」同樣扣掉
    let mut bi = HashMap::new();
    bi.insert("自己".to_string(), 30);
    let mut uni = HashMap::new();
    uni.insert("己".to_string(), 30);
    m2.set_peers(uni, bi);
    assert_eq!(m2.candidates("su", "")[0].ch, "已");
    // 沒有上文可解釋的選字照樣算偏好
    for _ in 0..5 { m2.learn("己", "", false); }
    assert_eq!(m2.candidates("su", "")[0].ch, "己");
    let _ = std::fs::remove_dir_all(&dir);
}
