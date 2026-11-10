use std::{ffi::c_void, sync::atomic::Ordering};

use windows::Win32::{
    Foundation::HINSTANCE,
    UI::WindowsAndMessaging::{HICON, LoadIconW},
};
use windows_core::PCWSTR;

use crate::{
    com::G_HINSTANCE,
    text_service::resources::{IDI_CHI, IDI_ENG},
};

/// 語言列／系統匣的中、英模式圖示（與 PIME 版同一組圖）。
#[derive(Debug, Clone, Copy)]
pub(crate) struct LangIconSet {
    pub(crate) chi: HICON,
    pub(crate) eng: HICON,
}

impl LangIconSet {
    pub(crate) fn load() -> LangIconSet {
        let g_hinstance = HINSTANCE(G_HINSTANCE.load(Ordering::Relaxed) as *mut c_void);
        LangIconSet {
            chi: load_icon(g_hinstance, IDI_CHI),
            eng: load_icon(g_hinstance, IDI_ENG),
        }
    }
}

fn load_icon(hinst: HINSTANCE, icon_id: u32) -> HICON {
    unsafe { LoadIconW(Some(hinst), PCWSTR::from_raw(icon_id as *const u16)).unwrap_or_default() }
}
