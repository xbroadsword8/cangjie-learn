//! 差分測試：讀 mac/tests/cases.json（Python 版預期結果），逐步比對。
//! 先用 `python3 mac/tests/gen_cases.py` 產生 cases.json，再 `cargo test -p cangjie_core --test difftest -- --nocapture`。
use cangjie_core::{Composer, Model};
use serde_json::Value;
use std::sync::{Arc, Mutex};

#[test]
fn diff_against_python() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
    let cases: Vec<Value> =
        serde_json::from_slice(&std::fs::read(root.join("mac/tests/cases.json")).expect("先跑 gen_cases.py")).unwrap();
    let user_db = std::env::temp_dir().join(format!("cangjie_core_difftest_{}.db", std::process::id()));
    let _ = std::fs::remove_file(&user_db);
    let model = Arc::new(Mutex::new(Model::open(root.join("data/model.db"), &user_db).unwrap()));
    let (mut pass, mut fail, mut first) = (0, 0, None::<String>);
    for (ci, cs) in cases.iter().enumerate() {
        let keys = cs["keys"].as_array().unwrap();
        let steps = cs["steps"].as_array().unwrap();
        let mut comp = Composer::new(model.clone());
        comp.full_punct = cs["full_punct"].as_bool().unwrap_or(false);
        let mut bad: Option<String> = None;
        for (i, k) in keys.iter().enumerate() {
            let b = |j: usize| k[j].as_bool().unwrap();
            let r = comp.process(k[0].as_str().unwrap(), b(1), b(2), b(3), b(4));
            let e = &steps[i];
            let page: String = comp.page_cands().iter().map(|c| c.ch.as_str()).collect();
            let scores: Vec<f64> = comp.page_cands().iter().map(|c| c.score).collect();
            let exp_scores: Vec<f64> = e[7].as_array().unwrap().iter().map(|x| x.as_f64().unwrap()).collect();
            let ok = (r.handled as i64) == e[0].as_i64().unwrap()
                && r.commit == e[1].as_str().unwrap()
                && comp.code == e[2].as_str().unwrap()
                && comp.page as i64 == e[3].as_i64().unwrap()
                && comp.cursor as i64 == e[4].as_i64().unwrap()
                && (comp.chinese as i64) == e[5].as_i64().unwrap()
                && page == e[6].as_str().unwrap()
                && scores.len() == exp_scores.len()
                && scores.iter().zip(&exp_scores).all(|(a, b)| (a - b).abs() <= 1e-9);
            if !ok {
                bad = Some(format!("case {ci} step {i} key={k}\n  expected {e}\n  got handled={} commit={:?} code={} page={} cursor={} chinese={} cands={page} scores={scores:?}",
                    r.handled, r.commit, comp.code, comp.page, comp.cursor, comp.chinese));
                break;
            }
        }
        if bad.is_none() {
            let (pe, pc, cx) = (cs["preedit"].as_str().unwrap(), cs["page"].as_str().unwrap(), cs["ctx"].as_str().unwrap());
            let page: String = comp.page_cands().iter().map(|c| c.ch.as_str()).collect();
            if comp.preedit() != pe || page != pc || comp.ctx != cx {
                bad = Some(format!("case {ci} final state: expected preedit={pe} page={pc} ctx={cx}; got preedit={} page={page} ctx={}", comp.preedit(), comp.ctx));
            }
        }
        match bad { Some(d) => { fail += 1; first.get_or_insert(d); } None => pass += 1 }
    }
    let _ = std::fs::remove_file(&user_db);
    if let Some(d) = first { println!("FIRST MISMATCH:\n{d}"); }
    println!("PASSED {pass}/{} (failed {fail})", cases.len());
    assert_eq!(fail, 0);
}
