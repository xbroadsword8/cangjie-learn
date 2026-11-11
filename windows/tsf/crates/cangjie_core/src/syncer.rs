//! 學習資料同步程式（對應 cjlearn/sync.py 的 export／adopt／Git／sync／write_status／main）。
//! 輸出格式與 Python 版逐位元組相同（別台電腦用 Python 版推同一個版本庫）。
use crate::settings;
use crate::sync::{read_status, STATUS_FILE, SYNC_DIR};
use rusqlite::Connection;
use serde_json::Value;
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const KEY_FILE: &str = "sync_key";

type Res<T> = Result<T, String>;

fn e<E: std::fmt::Display>(err: E) -> String { err.to_string() }

pub struct Export {
    pub name: String,
    pub uni: BTreeMap<String, i64>,
    pub bi: BTreeMap<String, i64>,
}

pub fn export(user_db: &Path, name: &str) -> Res<Export> {
    let con = Connection::open(user_db).map_err(e)?;
    let read = |sql: &str| -> rusqlite::Result<BTreeMap<String, i64>> {
        let mut st = con.prepare(sql)?;
        let rows = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
        rows.collect()
    };
    let (uni, bi) = match (read("select ch, n from uni"), read("select s, n from bi")) {
        (Ok(u), Ok(b)) => (u, b),
        _ => (BTreeMap::new(), BTreeMap::new()),   // 同 Python：沒有表就當空的
    };
    Ok(Export { name: name.to_string(), uni, bi })
}

fn jstr(s: &str) -> String { serde_json::to_string(s).unwrap() }

/// 同 Python json.dumps(data, ensure_ascii=False, indent=0) + "\n"：每個元素一行、無縮排；空 dict 為 {}。
fn export_json(x: &Export) -> String {
    let block = |m: &BTreeMap<String, i64>| -> String {
        if m.is_empty() { return "{}".into(); }
        let items: Vec<String> = m.iter().map(|(k, n)| format!("{}: {}", jstr(k), n)).collect();
        format!("{{\n{}\n}}", items.join(",\n"))
    };
    format!("{{\n\"name\": {},\n\"uni\": {},\n\"bi\": {}\n}}\n", jstr(&x.name), block(&x.uni), block(&x.bi))
}

/// 自己的學習資料是空的、版本庫裡卻有同名的檔 → 匯入。回傳匯入筆數。
pub fn adopt(user_db: &Path, own_file: &Path) -> Res<usize> {
    let con = Connection::open(user_db).map_err(e)?;
    con.execute_batch(
        "create table if not exists uni (ch text primary key, n int) without rowid;\
         create table if not exists bi (s text primary key, n int) without rowid;").map_err(e)?;
    let cnt: i64 = con.query_row("select count(*) from uni", [], |r| r.get(0)).map_err(e)?;
    if cnt != 0 || !own_file.exists() { return Ok(0); }
    let text = std::fs::read_to_string(own_file).map_err(e)?;
    let d: Value = serde_json::from_str(&text).map_err(e)?;
    let mut rows = 0;
    for table in ["uni", "bi"] {
        if let Some(Value::Object(m)) = d.get(table) {
            for (k, n) in m {
                if let Some(n) = n.as_i64().filter(|n| *n > 0) {
                    con.execute(&format!("insert into {table} values (?1,?2) on conflict do update set n=n+excluded.n"),
                                rusqlite::params![k, n]).map_err(e)?;
                    rows += 1;
                }
            }
        }
    }
    Ok(rows)
}

pub fn default_name() -> String {
    #[cfg(windows)]
    let host = std::env::var("COMPUTERNAME").unwrap_or_default();
    #[cfg(not(windows))]
    let host = std::fs::read_to_string("/proc/sys/kernel/hostname")
        .or_else(|_| std::fs::read_to_string("/etc/hostname"))
        .unwrap_or_default();
    let n = host.trim().split('.').next().unwrap_or("").to_lowercase();
    let s: String = n.chars().map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '-' }).collect();
    if s.is_empty() { "pc".into() } else { s }
}

pub struct Git {
    repo: PathBuf,
    git: String,
    ssh_command: String,
}

pub struct Out { pub code: i32, pub stderr: String }

impl Git {
    pub fn new(repo: &Path, git: &str, ssh: &str, key: &Path, known_hosts: &Path) -> Self {
        let q = |p: &str| format!("\"{}\"", p.replace('\\', "/"));
        let s = |p: &Path| p.to_string_lossy().into_owned();
        let ssh_command = format!(
            "{} -i {} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 \
             -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile={}",
            q(ssh), q(&s(key)), q(&s(known_hosts)));
        Git { repo: repo.to_path_buf(), git: git.to_string(), ssh_command }
    }

    pub fn run(&self, args: &[&str], check: bool) -> Res<Out> {
        let mut c = Command::new(&self.git);
        c.arg("-C").arg(&self.repo).args(args)
            .env("GIT_SSH_COMMAND", &self.ssh_command).env("GIT_TERMINAL_PROMPT", "0");
        #[cfg(windows)]
        {   // 排程執行時 git.exe 不跳出主控台視窗
            use std::os::windows::process::CommandExt;
            c.creation_flags(0x08000000);
        }
        let o = c.output().map_err(e)?;
        let code = o.status.code().unwrap_or(-1);
        let stderr = String::from_utf8_lossy(&o.stderr).into_owned();
        if check && code != 0 {
            return Err(format!("git {}：{}", args.join(" "), stderr.trim()));
        }
        Ok(Out { code, stderr })
    }
    fn ok(&self, args: &[&str]) -> Res<()> { self.run(args, true).map(|_| ()) }
    fn code(&self, args: &[&str]) -> Res<i32> { self.run(args, false).map(|o| o.code) }
}

fn json_files(dir: &Path) -> usize {
    std::fs::read_dir(dir).map(|rd| rd.filter_map(Result::ok)
        .filter(|f| f.path().extension().is_some_and(|x| x == "json")).count()).unwrap_or(0)
}

pub fn sync(data_dir: &Path, git: &str, ssh: &str, log: &mut dyn FnMut(&str)) -> Res<i32> {
    let cfg_path = data_dir.join("settings.json");
    let cfg = settings::load(&cfg_path);
    if cfg.sync_remote.is_empty() {
        log("沒有設定 sync_remote，不同步");
        return Ok(0);
    }
    let name = if cfg.sync_name.is_empty() { default_name() } else { cfg.sync_name.clone() };
    if cfg.sync_name.is_empty() {
        settings::update(&cfg_path, |s| s.sync_name = name.clone()).map_err(e)?;
    }
    let repo = data_dir.join(SYNC_DIR);
    std::fs::create_dir_all(&repo).map_err(e)?;
    let g = Git::new(&repo, git, ssh, &data_dir.join(KEY_FILE), &data_dir.join("known_hosts"));
    if !repo.join(".git").exists() {
        g.ok(&["init", "-q"])?;
        g.ok(&["symbolic-ref", "HEAD", "refs/heads/main"])?;
    }
    if g.code(&["remote", "get-url", "origin"])? != 0 {
        g.ok(&["remote", "add", "origin", &cfg.sync_remote])?;
    } else {
        g.ok(&["remote", "set-url", "origin", &cfg.sync_remote])?;
    }
    let own = repo.join(format!("{name}.json"));
    for _ in 0..3 {
        g.ok(&["fetch", "-q", "origin"])?;
        if g.code(&["rev-parse", "-q", "--verify", "origin/main"])? == 0 {
            g.ok(&["checkout", "-q", "-f", "-B", "main", "origin/main"])?;
        } else {
            g.code(&["checkout", "-q", "-B", "main"])?;
        }
        let user_db = data_dir.join("user.db");
        let n = adopt(&user_db, &own)?;
        if n != 0 { log(&format!("從版本庫接回 {name} 的學習資料 {n} 筆")); }
        let data = export(&user_db, &name)?;
        let tmp = own.with_extension("tmp");
        std::fs::write(&tmp, export_json(&data)).map_err(e)?;
        std::fs::rename(&tmp, &own).map_err(e)?;
        let own_name = format!("{name}.json");
        g.ok(&["add", &own_name])?;
        if g.code(&["diff", "--cached", "--quiet"])? == 0 {
            log(&format!("{name}：沒有新的學習資料；其他電腦 {} 台", json_files(&repo) as i64 - own.exists() as i64));
            return Ok(0);
        }
        let (u, b) = (data.uni.len(), data.bi.len());
        g.ok(&["-c", &format!("user.name={name}"), "-c", &format!("user.email={name}@cangjie-learn"),
               "commit", "-q", "-m", &format!("{name}：{u} 字、{b} 組")])?;
        if g.code(&["push", "-q", "origin", "main"])? == 0 {
            log(&format!("{name}：已推送（{u} 字、{b} 組）"));
            return Ok(0);
        }
        log("推送被拒（別台剛推過），重試");
    }
    Err("推送失敗三次".into())
}

fn now_secs() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn write_status(data_dir: &Path, ok: bool, message: &str) -> std::io::Result<()> {
    let p = data_dir.join(STATUS_FILE);
    let now = now_secs();
    let last_ok = if ok { now } else {
        read_status(data_dir).and_then(|m| m.get("last_ok").and_then(Value::as_i64)).unwrap_or(0)
    };
    let s = format!("{{\"ok\": {}, \"time\": {}, \"message\": {}, \"last_ok\": {}}}", ok, now, jstr(message), last_ok);
    let tmp = p.with_extension("tmp");
    std::fs::write(&tmp, s)?;
    std::fs::rename(&tmp, &p)
}

/// 命令列進入點；回傳結束碼（同 Python main）。
pub fn main(args: &[OsString]) -> i32 {
    let (mut data_dir, mut git, mut ssh) = (None, "git".to_string(), "ssh".to_string());
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let s = a.to_string_lossy().into_owned();
        let val = |it: &mut std::slice::Iter<OsString>| it.next().map(|v| v.to_string_lossy().into_owned());
        if s == "--git" { match val(&mut it) { Some(v) => git = v, None => return usage() } }
        else if s == "--ssh" { match val(&mut it) { Some(v) => ssh = v, None => return usage() } }
        else if let Some(v) = s.strip_prefix("--git=") { git = v.into(); }
        else if let Some(v) = s.strip_prefix("--ssh=") { ssh = v.into(); }
        else if s.starts_with("--") || data_dir.is_some() { return usage(); }
        else { data_dir = Some(PathBuf::from(a)); }
    }
    let Some(data_dir) = data_dir else { return usage() };
    let mut msgs: Vec<String> = Vec::new();
    let mut log = |m: &str| {
        let _ = writeln!(std::io::stdout(), "{m}");
        msgs.push(m.to_string());
    };
    match sync(&data_dir, &git, &ssh, &mut log) {
        Ok(rc) => {
            let m = msgs.last().cloned().unwrap_or_default();
            let _ = write_status(&data_dir, true, &m);
            rc
        }
        Err(err) => {
            let _ = writeln!(std::io::stderr(), "同步失敗：{err}");
            let _ = write_status(&data_dir, false, &err);
            1
        }
    }
}

fn usage() -> i32 {
    let _ = writeln!(std::io::stderr(), "usage: cjlearn-sync data_dir [--git GIT] [--ssh SSH]");
    2
}
