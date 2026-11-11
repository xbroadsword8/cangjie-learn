//! 學習資料同步排程用的執行檔（對應 cjlearn/sync.py 的命令列）：
//! cjlearn-sync <data_dir> [--git GIT] [--ssh SSH]
#![cfg_attr(windows, windows_subsystem = "windows")]

fn main() {
    let args: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    std::process::exit(cangjie_core::syncer::main(&args));
}
