//! 選字模型：碼表查詢＋上下文排序＋使用者學習（對應 cjlearn/model.py）。
use rusqlite::{params, Connection, OpenFlags};
use std::collections::HashMap;
use std::path::Path;

pub const CTX_LEN: usize = 3;
pub const W_USER_BI: f64 = 3.0;
pub const W_USER_UNI: f64 = 2.0;
pub const CORRECTION_BOOST: i64 = 3;
pub const W_CONTAINED: f64 = 0.3; // Python 保留常數（build_data 用）
pub const MAX_COMPLETIONS: usize = 60;

fn w_ngram(k: usize) -> f64 {
    match k { 1 => 1.5, 2 => 2.0, _ => 2.5 }
}

/// 取字串最後 n 個碼點（Python 的 s[-n:]）。
pub fn tail_chars(s: &str, n: usize) -> &str {
    let count = s.chars().count();
    if count <= n { return s; }
    let (idx, _) = s.char_indices().nth(count - n).unwrap();
    &s[idx..]
}

#[derive(Clone, Debug)]
pub struct Candidate {
    pub ch: String,
    pub code: String,
    pub exact: bool,
    pub score: f64,
}

pub struct Model {
    db: Connection,
    user: Connection,
    uni: HashMap<String, i64>,
    user_uni: HashMap<String, i64>,
    user_bi: HashMap<String, i64>,
    peer_uni: HashMap<String, i64>,
    peer_bi: HashMap<String, i64>,
    ngram_cache: HashMap<String, i64>,
}

fn pairs(c: &Connection, sql: &str) -> rusqlite::Result<HashMap<String, i64>> {
    let mut st = c.prepare(sql)?;
    let rows = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
    rows.collect()
}

impl Model {
    pub fn open(model_db: impl AsRef<Path>, user_db: impl AsRef<Path>) -> rusqlite::Result<Model> {
        let db = Connection::open_with_flags(model_db, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        let uni = pairs(&db, "select ch, freq from uni")?;
        if let Some(dir) = user_db.as_ref().parent() {
            if !dir.as_os_str().is_empty() { let _ = std::fs::create_dir_all(dir); }
        }
        let user = Connection::open(user_db)?;
        user.execute_batch(
            "create table if not exists uni (ch text primary key, n int) without rowid;\
             create table if not exists bi (s text primary key, n int) without rowid;",
        )?;
        let user_uni = pairs(&user, "select ch, n from uni")?;
        let user_bi = pairs(&user, "select s, n from bi")?;
        Ok(Model {
            db, user, uni, user_uni, user_bi,
            peer_uni: HashMap::new(), peer_bi: HashMap::new(), ngram_cache: HashMap::new(),
        })
    }

    fn ngram(&mut self, s: &str) -> i64 {
        if let Some(v) = self.ngram_cache.get(s) { return *v; }
        let v = self
            .db
            .query_row("select freq from ngram where s=?", [s], |r| r.get::<_, i64>(0))
            .unwrap_or(0);
        if self.ngram_cache.len() > 200_000 { self.ngram_cache.clear(); }
        self.ngram_cache.insert(s.to_string(), v);
        v
    }

    pub fn score(&mut self, ch: &str, ctx: &str) -> f64 {
        let mut s = (*self.uni.get(ch).unwrap_or(&0) as f64).ln_1p();
        let n = ctx.chars().count();
        for k in 1..=3usize {
            if n >= k {
                let key = format!("{}{}", tail_chars(ctx, k), ch);
                let f = self.ngram(&key);
                if f != 0 { s += w_ngram(k) * (f as f64).ln_1p(); }
            }
        }
        if n > 0 {
            let k = format!("{}{}", tail_chars(ctx, 1), ch);
            let v = self.user_bi.get(&k).unwrap_or(&0) + self.peer_bi.get(&k).unwrap_or(&0);
            s += W_USER_BI * (v as f64).ln_1p();
        }
        let v = self.user_uni.get(ch).unwrap_or(&0) + self.peer_uni.get(ch).unwrap_or(&0);
        s += W_USER_UNI * (v as f64).ln_1p();
        s
    }

    /// 查 (code, ch)；資料庫出錯回空清單。DLL 跑在 Word 等宿主程式裡，panic=abort 會把宿主一起帶掛。
    fn rows(&self, sql: &str, args: &[&str]) -> Vec<(String, String)> {
        let Ok(mut st) = self.db.prepare(sql) else { return vec![] };
        let out = match st.query_map(rusqlite::params_from_iter(args.iter()), |r| Ok((r.get(0)?, r.get(1)?))) {
            Ok(it) => it.filter_map(Result::ok).collect(),
            Err(_) => vec![],
        };
        out
    }

    /// 完整碼命中的字排前面；其後是以 code 為前綴的補完字。兩組各自依分數排序（穩定）。
    pub fn candidates(&mut self, code: &str, ctx: &str) -> Vec<Candidate> {
        if code.is_empty() { return vec![]; }
        let ctx = tail_chars(ctx, CTX_LEN).to_string();
        let rows = self.rows("select code, ch from code where code=? order by rank", &[code]);
        let mut exact: Vec<Candidate> = rows
            .into_iter()
            .map(|(c, ch)| { let score = self.score(&ch, &ctx); Candidate { ch, code: c, exact: true, score } })
            .collect();
        exact.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        let mut seen: std::collections::HashSet<String> = exact.iter().map(|c| c.ch.clone()).collect();
        let hi = format!("{}{{", code);
        let rows = self.rows("select code, ch from code where code > ? and code < ? order by length(code), rank",
                             &[code, hi.as_str()]);
        let mut comp = Vec::new();
        for (c, ch) in rows {
            if seen.insert(ch.clone()) {
                let score = self.score(&ch, &ctx);
                comp.push(Candidate { ch, code: c, exact: false, score });
            }
        }
        comp.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        comp.truncate(MAX_COMPLETIONS);
        exact.extend(comp);
        exact
    }

    /// 其他電腦學到的次數（sync.py 讀出的 uni／bi），選字時與自己的相加。
    pub fn set_peers(&mut self, uni: HashMap<String, i64>, bi: HashMap<String, i64>) {
        self.peer_uni = uni;
        self.peer_bi = bi;
    }

    pub fn learn(&mut self, ch: &str, prev: &str, corrected: bool) {
        let n = if corrected { CORRECTION_BOOST } else { 1 };
        *self.user_uni.entry(ch.to_string()).or_insert(0) += n;
        let _ = self.user.execute(
            "insert into uni values (?1,?2) on conflict(ch) do update set n=n+?2", params![ch, n]);
        if !prev.is_empty() {
            let s = format!("{}{}", tail_chars(prev, 1), ch);
            *self.user_bi.entry(s.clone()).or_insert(0) += n;
            let _ = self.user.execute(
                "insert into bi values (?1,?2) on conflict(s) do update set n=n+?2", params![s, n]);
        }
    }

    /// 目前自己學到的次數（供同步端讀取）。
    pub fn user_counts(&self) -> (&HashMap<String, i64>, &HashMap<String, i64>) {
        (&self.user_uni, &self.user_bi)
    }
}
