// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Kan-Ru Chen
//
// 倉頡學習版的 TSF 外殼：按鍵、組字、候選窗、語言列與選單。
// 選字邏輯全部在 cangjie_core（Composer／Model）；這裡只負責把 TSF 事件餵給核心、把結果畫出來。
// 行為規格來自 PIME 版外殼（windows/pime/cjlearn/cjlearn_ime.py）。

use std::ffi::c_void;
use std::mem;
use std::path::PathBuf;
use std::rc::{Rc, Weak};
use std::cell::RefCell;
use std::sync::atomic::Ordering;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use cangjie_core::composer::{PAGE, radical};
use cangjie_core::keymap::{self, keysym_name};
use cangjie_core::settings::{self, Settings};
use cangjie_core::sync::{self, PeerWatcher};
use cangjie_core::{Composer, KeyResult, Model};
use log::{debug, error, info};
use scoped_error::impl_context_error;
use scoped_error::{ErrorExt, expect_error};
use windows::Win32::Foundation::{GetLastError, HINSTANCE, HMODULE, POINT, RECT};
use windows::Win32::System::LibraryLoader::GetModuleFileNameW;
use windows::Win32::System::Variant::VARIANT;
use windows::Win32::UI::Input::KeyboardAndMouse::GetFocus;
use windows::Win32::UI::TextServices::{
    GUID_COMPARTMENT_EMPTYCONTEXT, GUID_COMPARTMENT_KEYBOARD_DISABLED,
    GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, GUID_LBI_INPUTMODE, ITfCompartmentMgr, ITfComposition,
    ITfCompositionSink, ITfContext, ITfLangBarItemButton, ITfLangBarItemMgr, ITfThreadMgr,
    TF_ATTR_INPUT, TF_DISPLAYATTRIBUTE, TF_ES_ASYNC, TF_ES_READ, TF_ES_READWRITE, TF_ES_SYNC,
    TF_LBI_STYLE_BTN_BUTTON, TF_LS_DOT, TF_LS_SOLID, TF_SD_READONLY,
};
use windows::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CheckMenuItem, DeleteMenu, GetCursorPos, HICON, HMENU, MF_BYCOMMAND, MF_CHECKED,
    MF_GRAYED, MF_STRING, MF_UNCHECKED, TPM_BOTTOMALIGN, TPM_LEFTALIGN, TPM_LEFTBUTTON,
    TPM_NONOTIFY, TPM_RETURNCMD, TrackPopupMenu,
};
use windows_core::{ComObject, ComObjectInner, GUID, HSTRING, Interface};

use super::CommandType;
use super::GUID_INPUT_DISPLAY_ATTRIBUTE_1;
use super::GUID_INPUT_DISPLAY_ATTRIBUTE_2;
use super::display_attribute::register_display_attribute;
use super::edit_session::InsertText;
use super::edit_session::{EndComposition, SelectionRect, SetCompositionString};
use super::key_event::SystemKeyboardEvent;
use super::lang_bar::LangBarButton;
use super::menu::Menu;
use super::resources::*;
use super::ui_elements::{CandidateList, Model as CandidateModel, Notification, NotificationModel};
use crate::com::G_HINSTANCE;
use crate::text_service::TextService;
use crate::text_service::edit_session::request_edit_session;
use crate::text_service::icons::LangIconSet;
use crate::text_service::lang_bar::LangBarFactory;
use crate::ui::gfx::color_s;

const GUID_MODE_BUTTON: GUID = GUID::from_u128(0xEB45F7B4_E73A_4420_9853_967E0D13EC04);

impl_context_error!(TsfError);

/// TSF 偶爾對同一個按鍵重複呼叫 OnTestKeyDown；這段時間內的重複不再餵給核心（核心的 process 會改狀態）。
const DUP_FILTER: Duration = Duration::from_millis(50);
/// 同步資料夾最多每隔多久檢查一次有沒有變。
const PEER_POLL_INTERVAL: Duration = Duration::from_secs(60);
const SEL_KEYS: &str = "123456789";

// 候選窗與提示的外觀（沿用上游預設值）
const FONT_FAMILY: &str = "Segoe UI";
const FONT_SIZE: f32 = 16.0;
const FG: &str = "000000FF";
const BG: &str = "FAFAFAFF";
const HIGHLIGHT_FG: &str = "FFFFFFFF";
const HIGHLIGHT_BG: &str = "000000FF";
const NUMBER_FG: &str = "0000FFFF";
const BORDER: &str = "D6D9DBFF";
const NOTIFY_BG: &str = "FCFBDAFF";
/// 補完候選後面字根提示的顏色（橘色，與黑字、藍色序號區分；一般／被選中）
const HINT_FG: &str = "C2410CFF";
const HINT_HIGHLIGHT_FG: &str = "FDBA74FF";

// --- 行程內共用的狀態：學習資料、選項、同步 ---

struct Shared {
    model: Arc<Mutex<Model>>,
    peers: PeerWatcher,
}

/// 一個行程只開一份 Model（所有 text service 實例共用）。
static SHARED: Mutex<Option<Shared>> = Mutex::new(None);
static SETTINGS: LazyLock<Mutex<Settings>> =
    LazyLock::new(|| Mutex::new(settings::load(settings_file())));

/// 學習資料位置沿用 PIME 版：%APPDATA%\PIME\cjlearn（user.db、settings.json、sync\）。
/// DLL 旁有 data_dir.txt 時改用它寫的資料夾（可含 %VAR%），測試時用來隔開真正的學習資料與同步。
fn data_dir() -> PathBuf {
    static DIR: LazyLock<PathBuf> = LazyLock::new(|| {
        if let Some(p) = dll_dir()
            .and_then(|d| std::fs::read_to_string(d.join("data_dir.txt")).ok())
            .map(|s| expand_env(s.trim().trim_start_matches('\u{feff}')))
            .filter(|s| !s.is_empty())
        {
            return PathBuf::from(p);
        }
        let base = std::env::var_os("APPDATA")
            .map(PathBuf::from)
            .or_else(|| {
                std::env::var_os("USERPROFILE")
                    .map(|p| PathBuf::from(p).join("AppData").join("Roaming"))
            })
            .unwrap_or_else(std::env::temp_dir);
        base.join("PIME").join("cjlearn")
    });
    DIR.clone()
}

/// 把 %VAR% 換成環境變數值（找不到的照原樣留著）。
fn expand_env(s: &str) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(i) = rest.find('%') {
        out.push_str(&rest[..i]);
        let after = &rest[i + 1..];
        match after.find('%') {
            Some(j) => {
                let name = &after[..j];
                match std::env::var(name) {
                    Ok(v) if !name.is_empty() => out.push_str(&v),
                    _ => { out.push('%'); out.push_str(name); out.push('%'); }
                }
                rest = &after[j + 1..];
            }
            None => { out.push('%'); rest = after; }
        }
    }
    out.push_str(rest);
    out
}

fn settings_file() -> PathBuf {
    data_dir().join("settings.json")
}

/// 這支 DLL 所在的資料夾。
fn dll_dir() -> Option<PathBuf> {
    let mut buf = [0u16; 1024];
    let hmodule = HMODULE(G_HINSTANCE.load(Ordering::Relaxed) as *mut c_void);
    let len = unsafe { GetModuleFileNameW(Some(hmodule), &mut buf) } as usize;
    if len == 0 || len >= buf.len() {
        return None;
    }
    Some(PathBuf::from(String::from_utf16_lossy(&buf[..len])).parent()?.to_path_buf())
}

/// model.db 放在這支 DLL 旁邊。
fn model_db_path() -> Option<PathBuf> {
    Some(dll_dir()?.join("model.db"))
}

/// 學習資料夾讀不到（沙箱程式，例如 Win11 開始功能表的搜尋 SearchHost）。
/// 要先用一般檔案操作判斷：交給 SQLite 開的話，它遇到「拒絕存取」會重試好幾秒（防毒軟體對策），
/// 程式在那段時間打不出字。資料夾還不存在＝第一次用，不算讀不到。
fn data_dir_denied() -> bool {
    match std::fs::read_dir(data_dir()) {
        Ok(_) => false,
        Err(e) => e.kind() != std::io::ErrorKind::NotFound,
    }
}

/// 取得（必要時開啟）共用 Model，順便檢查同步資料夾有沒有更新。
fn shared_model() -> Option<Arc<Mutex<Model>>> {
    let mut guard = SHARED.lock().ok()?;
    if guard.is_none() {
        let dir = data_dir();
        let db = model_db_path()?;
        let denied = data_dir_denied();
        let opened = if denied {
            Err(format!("access denied: {}", dir.display()))
        } else {
            Model::open(&db, dir.join("user.db")).map_err(|e| e.to_string())
        };
        match opened {
            Ok(model) => {
                info!("model opened: {}", db.display());
                *guard = Some(Shared {
                    model: Arc::new(Mutex::new(model)),
                    peers: PeerWatcher::new(dir, PEER_POLL_INTERVAL),
                });
            }
            Err(error) => {
                // 開始功能表的搜尋（Win11 SearchHost）等沙箱程式讀不到 %APPDATA% 的學習資料：
                // 改用記憶體裡的空白學習資料，至少能照詞庫選字打中文（學到的不存檔）。
                error!("unable to open user data, falling back to memory: {error}");
                keylog(format_args!("user.db open failed ({error}); using :memory:"));
                match Model::open(&db, ":memory:") {
                    Ok(model) => {
                        *guard = Some(Shared {
                            model: Arc::new(Mutex::new(model)),
                            peers: PeerWatcher::new(dir, PEER_POLL_INTERVAL),
                        });
                    }
                    Err(error) => {
                        error!("unable to open model {}: {error}", db.display());
                        keylog(format_args!("model.db open failed ({error})"));
                        return None;
                    }
                }
            }
        }
    }
    let shared = guard.as_mut()?;
    shared.peers.poll(&shared.model);
    Some(shared.model.clone())
}

/// 除錯用按鍵紀錄：學習資料夾裡有 keylog.on 時才寫 keylog.txt（程式啟動時決定）。
/// 只記鍵碼與狀態；字母、數字一律記成 vk=key，不記打了哪個字、也不記送出的文字。
/// 沙箱程式（讀不到學習資料夾）改寫到它自己的暫存資料夾，除錯時從那裡撈。
static KEYLOG: LazyLock<Option<PathBuf>> = LazyLock::new(|| {
    let d = data_dir();
    if d.join("keylog.on").exists() {
        Some(d.join("keylog.txt"))
    } else if data_dir_denied() {
        Some(std::env::temp_dir().join("cjlearn-keylog.txt"))
    } else {
        None
    }
});

fn keylog(line: std::fmt::Arguments) {
    let Some(path) = KEYLOG.as_ref() else { return };
    use std::io::Write;
    if std::fs::metadata(path).is_ok_and(|m| m.len() > 4_000_000) {
        let _ = std::fs::rename(path, path.with_extension("old.txt"));
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);
        let _ = writeln!(f, "{ms} pid={} {line}", std::process::id());
    }
}

fn vk_label(vk: u16) -> String {
    match vk {
        0x30..=0x39 | 0x41..=0x5A | 0x60..=0x69 => "key".into(),
        _ => format!("{vk:#04x}"),
    }
}

fn reload_settings() -> Settings {
    let fresh = settings::load(settings_file());
    if let Ok(mut s) = SETTINGS.lock() {
        *s = fresh.clone();
    }
    fresh
}

fn current_settings() -> Settings {
    SETTINGS.lock().map(|s| s.clone()).unwrap_or_default()
}

/// 切換一個選項並存進 settings.json（讀檔再改再存，不蓋掉同步用的其他欄位）。
fn toggle_setting(f: impl Fn(&mut Settings) + Copy) {
    let updated = settings::update(settings_file(), f).unwrap_or_else(|error| {
        error!("unable to save settings: {error}");
        let mut s = current_settings();
        f(&mut s);
        s
    });
    if let Ok(mut s) = SETTINGS.lock() {
        *s = updated;
    }
}

pub(super) struct CompositionString {
    pub(super) commit: String,
    pub(super) preedit: String,
    pub(super) segments: Vec<(usize, usize)>,
    pub(super) cursor: usize,
}

pub(super) struct CangjieTextService {
    thread_mgr: ITfThreadMgr,
    tid: u32,
    input_da_atom: [VARIANT; 2],
    _menu: Menu,
    popup_menu: HMENU,
    lang_icons: LangIconSet,
    lang_bar_buttons: Vec<ITfLangBarItemButton>,
    composition_sink: ITfCompositionSink,

    switch_lang_button: ComObject<LangBarButton>,
    ime_mode_button: ComObject<LangBarButton>,

    /// 模型打不開（找不到 model.db）時為 None，所有按鍵放行給應用程式。
    composer: Option<Composer>,
    /// 鍵盤 OpenClose 為開（false 時所有按鍵不處理）。
    keyboard_open: bool,
    /// OnTestKeyDown 已經餵給核心並吃掉的鍵，等 OnKeyDown 輸出。
    pending_down: Option<(u16, KeyResult)>,
    last_test_down: Option<(u16, Instant)>,
    /// Shift＋空白剛切換全形／半形，OnKeyDown 時顯示提示。
    shape_changed: bool,
    /// 鍵盤被程式關閉（OpenClose＝0）時按下了 Shift、之後沒按別的鍵
    closed_shift: bool,
    /// 關閉狀態下單按了 Shift：OnKeyUp 要把輸入法打開回到中文
    reopen: bool,

    has_focus: bool,
    notification: Option<ComObject<Notification>>,
    candidate_list: Option<ComObject<CandidateList>>,
    composition: Rc<RefCell<Option<ITfComposition>>>,
    pending_edit: Weak<RefCell<Option<CompositionString>>>,
}

impl CangjieTextService {
    pub(super) fn new(
        thread_mgr: ITfThreadMgr,
        tid: u32,
        ts: ComObject<TextService>,
    ) -> Result<CangjieTextService> {
        let da = TF_DISPLAYATTRIBUTE {
            lsStyle: TF_LS_DOT,
            bAttr: TF_ATTR_INPUT,
            ..Default::default()
        };
        let input_da_atom_1 = register_display_attribute(&GUID_INPUT_DISPLAY_ATTRIBUTE_1, da)?;
        let da = TF_DISPLAYATTRIBUTE {
            lsStyle: TF_LS_SOLID,
            bAttr: TF_ATTR_INPUT,
            ..Default::default()
        };
        let input_da_atom_2 = register_display_attribute(&GUID_INPUT_DISPLAY_ATTRIBUTE_2, da)?;

        let g_hinstance = HINSTANCE(G_HINSTANCE.load(Ordering::Relaxed) as *mut c_void);
        let menu = Menu::load(g_hinstance, IDR_MENU);

        CandidateList::window_register_class(g_hinstance);
        Notification::window_register_class(g_hinstance);

        let lang_bar_item_mgr: ITfLangBarItemMgr = thread_mgr.cast()?;

        // 右鍵選單掛在中／英圖示上（與 PIME 版相同位置）
        let popup_menu = menu.sub_menu(0);
        let factory = LangBarFactory::new(
            g_hinstance,
            lang_bar_item_mgr,
            thread_mgr.clone(),
            popup_menu,
        );
        let switch_lang_button = factory.create_button(
            GUID_MODE_BUTTON,
            TF_LBI_STYLE_BTN_BUTTON,
            IDS_SWITCH_LANG,
            IDI_CJ,
            HMENU::default(),
            ID_SWITCH_LANG,
        )?;
        // Windows 8 systray IME mode icon
        let ime_mode_button = factory.create_button(
            GUID_LBI_INPUTMODE,
            TF_LBI_STYLE_BTN_BUTTON,
            IDS_SWITCH_LANG,
            IDI_CHI,
            HMENU::default(),
            ID_MODE_ICON,
        )?;
        let lang_bar_buttons = vec![switch_lang_button.cast()?, ime_mode_button.cast()?];

        let mut cts = CangjieTextService {
            thread_mgr,
            tid,
            composition_sink: ts.cast()?,
            input_da_atom: [input_da_atom_1, input_da_atom_2],
            _menu: menu,
            popup_menu,
            lang_icons: LangIconSet::load(),
            lang_bar_buttons,
            switch_lang_button,
            ime_mode_button,
            composer: None,
            keyboard_open: true,
            pending_down: None,
            last_test_down: None,
            shape_changed: false,
            closed_shift: false,
            reopen: false,
            has_focus: true,
            notification: Default::default(),
            candidate_list: Default::default(),
            composition: Default::default(),
            pending_edit: Weak::new(),
        };

        if let Err(error) = cts.init_openclose(tid) {
            error!("unable to initialize openclose: {error:#}");
        }
        reload_settings();
        cts.ensure_composer();
        cts.refresh_menu();
        let _ = cts.update_lang_buttons();

        Ok(cts)
    }

    pub(super) fn deactivate(mut self) -> ITfThreadMgr {
        if let Ok(lang_bar_item_mgr) = self.thread_mgr.cast::<ITfLangBarItemMgr>() {
            for button in self.lang_bar_buttons.drain(0..) {
                if let Err(error) = unsafe { lang_bar_item_mgr.RemoveItem(&button) } {
                    error!("unable to remove lang bar item: {error}");
                }
            }
        }
        // TSF doc: The corresponding ITfTextInputProcessor::Deactivate
        // method that shuts down the text service must release all references
        // to the ptim parameter.
        self.thread_mgr
    }

    fn ensure_composer(&mut self) {
        if self.composer.is_none()
            && let Some(model) = shared_model()
        {
            self.composer = Some(Composer::new(model));
        }
    }

    fn chinese(&self) -> bool {
        self.composer.as_ref().is_none_or(|c| c.chinese)
    }

    pub(super) fn on_kill_focus(&mut self, context: Option<ITfContext>) {
        debug!("on_kill_focus");
        keylog(format_args!("kill_focus"));
        self.has_focus = false;
        // 焦點改變：丟掉組字並斷開上文（PIME 版 onCompositionTerminated(forced) 同）
        if let Some(c) = self.composer.as_mut() {
            c.reset();
        }
        self.pending_down = None;
        if self.is_composing()
            && let Some(context) = context
        {
            // 清掉組字區裡的字根再結束，不然字根會被留在文件裡
            if let Err(error) = self.render(&context, String::new()) {
                error!("unable to clear composition: {error:#}");
            }
        }
        self.hide_candidates();
        self.hide_message();
    }

    pub(super) fn on_focus(&mut self) {
        debug!("on_focus");
        keylog(format_args!("focus chinese={}", self.chinese() as u8));
        self.has_focus = true;
        if let Some(c) = self.composer.as_mut() {
            c.reset();
        }
    }

    pub(super) fn on_thread_focus(&mut self) -> Result<()> {
        keylog(format_args!("thread_focus composer={}", self.composer.is_some() as u8));
        // 別的行程可能改了選項或同步了新資料
        reload_settings();
        self.ensure_composer();
        self.sync_keyboard_openclose()?;
        self.refresh_menu();
        self.update_lang_buttons()?;
        Ok(())
    }

    fn is_context_mutable(&self, context: &ITfContext) -> Result<bool, TsfError> {
        expect_error("Failed to query ITfContext status", || {
            let status = unsafe { context.GetStatus()? };
            if status.dwDynamicFlags & TF_SD_READONLY != 0 {
                debug!("key not handled - readonly document");
                return Ok(false);
            }
            let compartment_mgr: ITfCompartmentMgr = context.cast()?;
            unsafe {
                let empty_context =
                    compartment_mgr.GetCompartment(&GUID_COMPARTMENT_EMPTYCONTEXT)?;
                let value = i32::try_from(&empty_context.GetValue()?)?;
                if value == 1 {
                    debug!("key not handled - empty context");
                    return Ok(false);
                }

                let disabled =
                    compartment_mgr.GetCompartment(&GUID_COMPARTMENT_KEYBOARD_DISABLED)?;
                let value = i32::try_from(&disabled.GetValue()?)?;
                if value == 1 {
                    debug!("key not handled - keyboard disabled");
                    return Ok(false);
                }
            }
            Ok(true)
        })
    }

    fn is_shift(ev: &SystemKeyboardEvent) -> bool {
        matches!(
            ev.vk as u32,
            keymap::VK_SHIFT | keymap::VK_LSHIFT | keymap::VK_RSHIFT
        )
    }

    /// 把一個按鍵事件餵給核心。回傳 None＝不處理（交給應用程式）。
    fn process(&mut self, ev: &SystemKeyboardEvent, release: bool) -> Option<KeyResult> {
        let before = self.chinese();
        let r = self.process_inner(ev, release);
        if KEYLOG.is_some() {
            keylog(format_args!(
                "{} vk={} shift={} ctrl={} alt={} win={} open={} chinese={}->{} code={} r={:?}",
                if release { "up  " } else { "down" },
                vk_label(ev.vk),
                ev.shift() as u8,
                ev.ctrl() as u8,
                ev.alt() as u8,
                ev.win_down() as u8,
                self.keyboard_open as u8,
                before as u8,
                self.chinese() as u8,
                self.composer.as_ref().map_or(0, |c| c.code.len()),
                r.as_ref().map(|r| (r.handled, r.commit.chars().count())),
            ));
        }
        r
    }

    fn process_inner(&mut self, ev: &SystemKeyboardEvent, release: bool) -> Option<KeyResult> {
        // 鍵盤 OpenClose 關閉時不處理，只看是不是單按 Shift（要用它重新打開）。
        // 有些程式換欄位時會自己把輸入法關掉；不這樣做的話 Shift 就沒反應、卡在英文。
        if !self.keyboard_open {
            if Self::is_shift(ev) && !ev.ctrl() && !ev.alt() && !ev.win_down() {
                if !release {
                    self.closed_shift = true;
                } else if mem::take(&mut self.closed_shift) {
                    self.reopen = true;
                }
            } else if !release {
                self.closed_shift = false;
            }
            return None;
        }
        let comp = self.composer.as_mut()?;
        if ev.is_win_key() {
            if !release {
                // 先按 Shift 再按 Win 時，Shift 之後不該算「單按」：用「Ctrl＋Shift」按下事件
                // 讓核心放棄這次單按（核心對這種事件不改其他狀態）。
                comp.process("Shift_L", true, false, false, false);
            }
            return None;
        }
        // Win 鍵按著時所有按鍵都不處理，包含 Shift 的按下與放開
        // （Win＋Shift＋S 截圖不能被當成單按 Shift 切中英）
        if ev.win_down() {
            return None;
        }
        let (shift, ctrl, alt) = (ev.shift(), ev.ctrl(), ev.alt());
        let name = keysym_name(ev.vk as u32, shift, ctrl, ev.caps_lock())?;
        let s = current_settings();
        comp.clear_on_error = s.clear_on_error;
        comp.full_punct = s.full_punct;
        comp.full_shape = s.full_shape;
        let r = comp.process(name, ctrl, shift, alt, release);
        let shape = comp.full_shape;
        if shape != s.full_shape {
            // 全形／半形是全域選項（存 settings.json），其他程式切回焦點時會讀到
            toggle_setting(move |x| x.full_shape = shape);
            self.shape_changed = true;
        }
        Some(r)
    }

    /// 決定吃不吃這個鍵。核心的 process 會改狀態，所以在這裡就處理、暫存結果，OnKeyDown 只負責輸出。
    pub(super) fn on_test_keydown(
        &mut self,
        context: &ITfContext,
        ev: SystemKeyboardEvent,
    ) -> Result<bool> {
        let now = Instant::now();
        if self.pending_down.is_some()
            && self
                .last_test_down
                .is_some_and(|(vk, t)| vk == ev.vk && now.duration_since(t) < DUP_FILTER)
        {
            keylog(format_args!("test_down dup vk={}", vk_label(ev.vk)));
            return Ok(true);
        }
        self.last_test_down = Some((ev.vk, now));
        // Shift 的按下一定要讓核心看到（單按判斷靠它），其他鍵在唯讀／無效的文件裡不處理
        if !Self::is_shift(&ev) && !self.is_context_mutable(context)? {
            return Ok(false);
        }
        let Some(r) = self.process(&ev, false) else {
            return Ok(false);
        };
        // TSF 只能在 OnKeyDown 裡送字，所以「沒吃掉但要先送出第一候選」的鍵也一併吃掉
        if r.handled || !r.commit.is_empty() {
            self.pending_down = Some((ev.vk, r));
            return Ok(true);
        }
        Ok(false)
    }

    pub(super) fn on_keydown(
        &mut self,
        context: &ITfContext,
        ev: SystemKeyboardEvent,
    ) -> Result<bool> {
        let r = match self.pending_down.take() {
            Some((vk, r)) if vk == ev.vk => r,
            _ => {
                // 沒經過 OnTestKeyDown 就直接來（少數程式）：現在處理
                if !Self::is_shift(&ev) && !self.is_context_mutable(context)? {
                    return Ok(false);
                }
                match self.process(&ev, false) {
                    Some(r) if r.handled || !r.commit.is_empty() => r,
                    _ => return Ok(false),
                }
            }
        };
        debug!(commit = r.commit; "on_keydown");
        self.render(context, r.commit)?;
        if mem::take(&mut self.shape_changed) {
            let full = current_settings().full_shape;
            let msg = HSTRING::from(if full { "全形" } else { "半形" });
            if let Err(error) = self.show_message(context, &msg, Duration::from_secs(1)) {
                error!("{}", error.report());
            }
        }
        Ok(true)
    }

    pub(super) fn on_test_keyup(
        &mut self,
        context: &ITfContext,
        ev: SystemKeyboardEvent,
    ) -> Result<bool> {
        self.on_keyup(context, ev)
    }

    /// 單按 Shift 切中英：把放開事件餵給核心（它自己判斷是不是單按）。
    /// 一律回傳 false（不吃放開事件），免得應用程式看到 Shift 卡住；切換的畫面更新在這裡直接做。
    pub(super) fn on_keyup(
        &mut self,
        context: &ITfContext,
        ev: SystemKeyboardEvent,
    ) -> Result<bool> {
        let was_chinese = self.chinese();
        let Some(r) = self.process(&ev, true) else {
            if mem::take(&mut self.reopen) {
                self.reopen_keyboard(context)?;
            }
            return Ok(false);
        };
        let chinese = self.chinese();
        if chinese != was_chinese || !r.commit.is_empty() {
            debug!(chinese; "mode changed by key release");
            self.update_lang_buttons()?;
            // 切換前打到一半的字母一併送出，並清掉組字畫面
            self.render(context, r.commit)?;
            let msg = HSTRING::from(if chinese { "中" } else { "英" });
            if let Err(error) = self.show_message(context, &msg, Duration::from_secs(1)) {
                error!("{}", error.report());
            }
        }
        Ok(false)
    }

    pub(super) fn on_composition_terminated(
        &mut self,
        ecwrite: u32,
        composition: &ITfComposition,
    ) -> Result<()> {
        unsafe {
            let composition_range = composition
                .GetRange()
                .inspect_err(|_| debug!("failed to get composition range"))?;
            let doc_mgr = self
                .thread_mgr
                .GetFocus()
                .context("failed to get current ITfDocumentMgr")?;
            let context = doc_mgr
                .GetTop()
                .context("failed to get current ITfContext")?;

            // When a composition is interrupted by the application we only need to
            // clear the display attributes. When I tested this, clearing the display attribute
            // is not necessary, but this is what mozc was doing.
            //
            // In pure TSF mode, the composition string is automatically committed on termination.
            // In TSF/IMM32 bridge mode, the bridge sets a default property which we override to
            // have the same commit on unselect behavior. See [`TextService_Impl::Activate`].
            let disp_attr_prop =
                context.GetProperty(&windows::Win32::UI::TextServices::GUID_PROP_ATTRIBUTE)?;
            disp_attr_prop
                .Clear(ecwrite, &composition_range)
                .inspect_err(|_| debug!("failed to clear display attribute"))?;
        }
        self.on_composition_terminated_tail()
    }

    // SAFETY: this method must not cause TSF callback reentrant
    pub(super) fn on_composition_terminated_tail(&mut self) -> Result<()> {
        debug!(has_focus=self.has_focus; "on_composition_terminated_tail");
        if self.candidate_list.is_some() {
            self.hide_candidates();
        }
        // 切換視窗等被迫結束：丟掉組字並斷開上文
        if let Some(c) = self.composer.as_mut() {
            c.reset();
        }
        self.pending_down = None;
        if let Some(cell) = self.pending_edit.upgrade() {
            debug!("Clear pending edits to avoid double commits");
            cell.replace(None);
        }
        self.pending_edit = Weak::new();
        self.composition.replace(None);
        Ok(())
    }

    /// 鍵盤 OpenClose 隔間改變（Ctrl+Space 等）：照隔間的值開關，關閉時丟掉組字。
    pub(super) fn on_compartment_change(&mut self, guid: &GUID) -> Result<()> {
        debug!(has_focus=self.has_focus; "on_compartment_change");
        keylog(format_args!("compartment_change {guid:?} open={}", self.keyboard_open as u8));
        if guid == &GUID_COMPARTMENT_KEYBOARD_OPENCLOSE && self.has_focus {
            let was_open = self.keyboard_open;
            self.sync_keyboard_openclose()?;
            self.closed_shift = false;
            keylog(format_args!("openclose -> {}", self.keyboard_open as u8));
            self.update_lang_buttons()?;
            if was_open && !self.keyboard_open {
                if let Some(c) = self.composer.as_mut() {
                    c.reset();
                }
                self.pending_down = None;
                if let Ok(context) = self.focus_context() {
                    self.render(&context, String::new())?;
                }
            }
        }
        Ok(())
    }

    /// 程式把鍵盤關掉後使用者單按 Shift：打開並切回中文。
    fn reopen_keyboard(&mut self, context: &ITfContext) -> Result<()> {
        keylog(format_args!("reopen by shift"));
        let compartment_mgr: ITfCompartmentMgr = self.thread_mgr.cast()?;
        unsafe {
            let compartment =
                compartment_mgr.GetCompartment(&GUID_COMPARTMENT_KEYBOARD_OPENCLOSE)?;
            compartment.SetValue(self.tid, &1i32.into())?;
        }
        self.keyboard_open = true;
        if let Some(c) = self.composer.as_mut() {
            c.reset();
            c.chinese = true;
        }
        self.update_lang_buttons()?;
        if let Err(error) = self.show_message(context, &HSTRING::from("中"), Duration::from_secs(1)) {
            error!("{}", error.report());
        }
        Ok(())
    }

    fn sync_keyboard_openclose(&mut self) -> Result<()> {
        let compartment_mgr: ITfCompartmentMgr = self.thread_mgr.cast()?;
        unsafe {
            let compartment =
                compartment_mgr.GetCompartment(&GUID_COMPARTMENT_KEYBOARD_OPENCLOSE)?;
            self.keyboard_open = i32::try_from(&compartment.GetValue()?).map_or(true, |v| v != 0);
        }
        debug!(open = self.keyboard_open; "sync_keyboard_openclose");
        Ok(())
    }

    fn init_openclose(&self, tid: u32) -> Result<()> {
        let compartment_mgr: ITfCompartmentMgr = self.thread_mgr.cast()?;
        unsafe {
            let compartment =
                compartment_mgr.GetCompartment(&GUID_COMPARTMENT_KEYBOARD_OPENCLOSE)?;
            let _ = compartment.GetValue()?;
            let _ = compartment.SetValue(tid, &1i32.into());
        }
        Ok(())
    }

    fn focus_context(&self) -> Result<ITfContext> {
        unsafe {
            let doc_mgr = self
                .thread_mgr
                .GetFocus()
                .context("failed to get current ITfDocumentMgr")?;
            doc_mgr.GetTop().context("failed to get current ITfContext")
        }
    }

    pub(super) fn on_command(&mut self, id: u32, cmd_type: CommandType) {
        if matches!(cmd_type, CommandType::RightClick) {
            if id == ID_MODE_ICON || id == ID_SWITCH_LANG {
                self.refresh_menu();
                let mut pos = POINT::default();
                let ret = unsafe {
                    let _ = GetCursorPos(&mut pos);
                    TrackPopupMenu(
                        self.popup_menu,
                        TPM_NONOTIFY
                            | TPM_RETURNCMD
                            | TPM_LEFTALIGN
                            | TPM_BOTTOMALIGN
                            | TPM_LEFTBUTTON,
                        pos.x,
                        pos.y,
                        None,
                        GetFocus(),
                        None,
                    )
                };
                if ret.as_bool() {
                    self.on_command(ret.0 as u32, CommandType::Menu);
                } else {
                    let last_error = unsafe { GetLastError() };
                    let hresult = last_error.to_hresult();
                    error!("unable to open popup menu: {}", hresult.message());
                }
            }
        } else {
            match id {
                ID_SWITCH_LANG | ID_MODE_ICON => {
                    if let Err(error) = self.toggle_lang_mode() {
                        error!("unable to toggle lang mode: {error}");
                    }
                }
                ID_CLEAR_ON_ERROR => {
                    toggle_setting(|s| s.clear_on_error = !s.clear_on_error);
                    self.refresh_menu();
                }
                ID_FULL_PUNCT => {
                    toggle_setting(|s| s.full_punct = !s.full_punct);
                    self.refresh_menu();
                }
                ID_FULL_SHAPE => {
                    toggle_setting(|s| s.full_shape = !s.full_shape);
                    self.refresh_menu();
                }
                _ => {}
            }
        }
    }

    /// 點圖示切中英：清掉組字（PIME 版 onCommand 同；沒有 edit session，所以不提示）。
    fn toggle_lang_mode(&mut self) -> Result<()> {
        let Some(c) = self.composer.as_mut() else {
            return Ok(());
        };
        c.chinese = !c.chinese;
        keylog(format_args!("icon_toggle chinese={}", c.chinese as u8));
        c.reset();
        self.pending_down = None;
        self.update_lang_buttons()?;
        if let Ok(context) = self.focus_context() {
            self.render(&context, String::new())?;
        }
        Ok(())
    }

    /// 選單：兩個勾選項依 settings.json 打勾；有設定同步時加一行灰色的同步狀態（照 sync.status_text）。
    fn refresh_menu(&self) {
        let s = current_settings();
        let check = |on: bool| if on { MF_CHECKED.0 } else { MF_UNCHECKED.0 };
        unsafe {
            CheckMenuItem(self.popup_menu, ID_CLEAR_ON_ERROR, check(s.clear_on_error));
            CheckMenuItem(self.popup_menu, ID_FULL_PUNCT, check(s.full_punct));
            CheckMenuItem(self.popup_menu, ID_FULL_SHAPE, check(s.full_shape));
            let _ = DeleteMenu(self.popup_menu, ID_SYNC_STATUS, MF_BYCOMMAND);
            let status = sync::status_text(data_dir(), None);
            if !status.is_empty() {
                let _ = AppendMenuW(
                    self.popup_menu,
                    MF_STRING | MF_GRAYED,
                    ID_SYNC_STATUS as usize,
                    &HSTRING::from(status),
                );
            }
        }
    }

    // --- 畫面 ---

    /// 把核心目前的狀態畫出來：候選窗、組字區（字根）、以及要送出的字。
    fn render(&mut self, context: &ITfContext, commit: String) -> Result<()> {
        if let Err(error) = self.update_candidates(context) {
            error!("{}", error.report());
        }
        let preedit = self
            .composer
            .as_ref()
            .map(|c| c.preedit())
            .unwrap_or_default();
        if !preedit.is_empty() {
            let len = preedit.chars().count();
            self.set_composition_string(context, &commit, &preedit, vec![(0, len)], len)?;
        } else if !self.is_composing() {
            // 沒在組字：直接把字送出
            if !commit.is_empty() {
                self.insert_text(context, &commit)?;
            }
        } else {
            // 組字區清空：連同要送出的字一起結束組字
            self.set_composition_string(context, &commit, "", vec![], 0)?;
            // 候選窗還開著時不能結束組字
            if self.candidate_list.is_none() {
                self.end_composition(context);
            }
        }
        Ok(())
    }

    fn insert_text(&self, context: &ITfContext, text: &str) -> Result<()> {
        debug!(text; "going to request immediate text insertion");
        let htext = text.into();
        let session = InsertText::new(context.clone(), htext).into_object();
        request_edit_session(
            context,
            self.tid,
            session.as_interface(),
            TF_ES_ASYNC | TF_ES_READWRITE,
        );
        Ok(())
    }

    fn end_composition(&mut self, context: &ITfContext) {
        // Transfer the ownership of this composition to the EndComposition edit session.
        let composition = mem::replace(&mut self.composition, Rc::new(RefCell::new(None)));
        self.pending_edit = Weak::new();
        let session = EndComposition::new(context.clone(), composition).into_object();
        request_edit_session(
            context,
            self.tid,
            session.as_interface(),
            TF_ES_ASYNC | TF_ES_READWRITE,
        );
    }

    fn set_composition_string(
        &mut self,
        context: &ITfContext,
        commit: &str,
        preedit: &str,
        segments: Vec<(usize, usize)>,
        cursor: usize,
    ) -> Result<()> {
        debug!(commit, preedit; "set composition string");
        let commit = commit.into();
        let preedit = preedit.into();
        if let Some(cell) = self.pending_edit.upgrade() {
            debug!(cursor, preedit:%; "Reuse existing edit session");
            cell.replace(Some(CompositionString {
                commit,
                preedit,
                segments,
                cursor,
            }));
        } else {
            let pending = Rc::new(RefCell::new(Some(CompositionString {
                commit,
                preedit,
                segments,
                cursor,
            })));
            let session = SetCompositionString::new(
                context.clone(),
                self.composition.clone(),
                self.composition_sink.clone(),
                self.input_da_atom.clone(),
                pending.clone(),
            )
            .into_object();
            self.pending_edit = Rc::downgrade(&pending);
            request_edit_session(
                context,
                self.tid,
                session.as_interface(),
                TF_ES_ASYNC | TF_ES_READWRITE,
            );
        }
        Ok(())
    }

    fn get_selection_rect(&self, context: &ITfContext) -> Result<RECT> {
        let session = SelectionRect::new(context.clone()).into_object();
        request_edit_session(
            context,
            self.tid,
            session.as_interface(),
            TF_ES_SYNC | TF_ES_READ,
        );
        Ok(session.rect())
    }

    fn show_message(
        &mut self,
        context: &ITfContext,
        text: &HSTRING,
        dur: Duration,
    ) -> Result<(), scoped_error::Error> {
        expect_error("Failed to show message", || {
            let hwnd = unsafe {
                let view = context.GetActiveView()?;
                // UILess console may not have valid HWND
                view.GetWnd().unwrap_or_default()
            };
            let notification = Notification::new(hwnd, self.thread_mgr.clone())?;
            notification.set_model(NotificationModel {
                text: text.clone(),
                font_family: HSTRING::from(FONT_FAMILY),
                font_size: FONT_SIZE,
                fg_color: color_s(FG),
                bg_color: color_s(NOTIFY_BG),
                border_color: color_s(BORDER),
            });
            if let Ok(rect) = self.get_selection_rect(context) {
                notification.set_position(rect.left + 50, rect.bottom + 50);
                // HACK set position again to use correct DPI setting
                notification.set_position(rect.left + 50, rect.bottom + 50);
            }
            notification.show();
            notification.set_timer(dur);
            self.notification = Some(notification);
            Ok(())
        })
    }

    fn hide_message(&mut self) {
        if let Some(notification) = self.notification.take() {
            notification.set_timer(Duration::ZERO);
            notification.end_ui_element();
        }
    }

    /// 候選窗：每頁 9 個、單欄、游標高亮；補完候選（exact == false）後面用灰色畫還沒打的字根，順便練碼。
    fn update_candidates(&mut self, context: &ITfContext) -> Result<(), scoped_error::Error> {
        expect_error("Failed to refresh candidate window", || {
            let page = match &self.composer {
                Some(c) if !c.code.is_empty() => {
                    let typed = c.code.chars().count();
                    let cands = c.page_cands();
                    let items: Vec<String> = cands.iter().map(|p| p.ch.clone()).collect();
                    let hints: Vec<String> = cands
                        .iter()
                        .map(|p| {
                            if p.exact {
                                String::new()
                            } else {
                                p.code.chars().skip(typed).map(radical).collect()
                            }
                        })
                        .collect();
                    let total_page = c.cands.len().div_ceil(PAGE) as u32;
                    (!items.is_empty()).then_some((items, hints, total_page, c.page as u32 + 1, c.cursor))
                }
                _ => None,
            };
            let Some((items, hints, total_page, current_page, cursor)) = page else {
                self.hide_candidates();
                return Ok(());
            };
            if self.candidate_list.is_none() {
                let view = unsafe { context.GetActiveView()? };
                // UILess console may not have valid HWND
                let hwnd = unsafe { view.GetWnd().unwrap_or_default() };
                let candidate_list = CandidateList::new(hwnd, self.thread_mgr.clone())?;
                self.candidate_list = Some(candidate_list);
            }
            if let Some(candidate_list) = &self.candidate_list {
                candidate_list.set_model(CandidateModel {
                    items,
                    hints,
                    selkeys: SEL_KEYS.chars().map(|k| k as u16).collect(),
                    cand_per_row: 1,
                    total_page,
                    current_page,
                    font_family: HSTRING::from(FONT_FAMILY),
                    font_size: FONT_SIZE,
                    fg_color: color_s(FG),
                    bg_color: color_s(BG),
                    highlight_fg_color: color_s(HIGHLIGHT_FG),
                    highlight_bg_color: color_s(HIGHLIGHT_BG),
                    hint_color: color_s(HINT_FG),
                    hint_highlight_color: color_s(HINT_HIGHLIGHT_FG),
                    border_color: color_s(BORDER),
                    selkey_color: color_s(NUMBER_FG),
                    use_cursor: true,
                    current_sel: cursor,
                });

                candidate_list.show();

                if let Ok(rect) = self.get_selection_rect(context) {
                    candidate_list.set_position(rect.left, rect.bottom);
                    // HACK set position again to use correct DPI setting
                    candidate_list.set_position(rect.left, rect.bottom);
                }
            }

            Ok(())
        })
    }

    fn hide_candidates(&mut self) {
        if let Some(candidate_list) = self.candidate_list.take() {
            candidate_list.hide();
            candidate_list.end_ui_element();
        }
    }

    fn update_lang_buttons(&self) -> Result<()> {
        let icon = self.get_lang_icon();
        // 自己的按鈕固定顯示「倉」，中／英看系統的輸入模式圖示
        self.switch_lang_button.set_icon(self.lang_icons.cj)?;
        self.ime_mode_button.set_icon(icon)?;
        let _ = self.ime_mode_button.set_enabled(self.keyboard_open);
        Ok(())
    }

    fn get_lang_icon(&self) -> HICON {
        // 被程式關掉時打的是英文，圖示也要顯示「英」（按 Shift 可切回中文）
        if self.keyboard_open && self.chinese() {
            self.lang_icons.chi
        } else {
            self.lang_icons.eng
        }
    }

    fn is_composing(&self) -> bool {
        // when candidate window is shown we are composing even without a composition
        self.composition.borrow().is_some() || self.candidate_list.is_some()
    }
}
