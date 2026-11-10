// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Kan-Ru Chen

use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, GetKeyboardState, VIRTUAL_KEY, VK_CAPITAL, VK_CONTROL, VK_LWIN, VK_MENU,
    VK_RWIN, VK_SHIFT,
};

/// TSF 回呼收到的一次按鍵：虛擬鍵碼與當下的鍵盤狀態（修飾鍵、CapsLock）。
#[derive(Debug, Clone, Copy)]
pub(super) struct SystemKeyboardEvent {
    pub(super) vk: u16,
    key_state: [u8; 256],
}

impl SystemKeyboardEvent {
    pub(super) fn new(vk: u16) -> SystemKeyboardEvent {
        let mut key_state = [0u8; 256];
        unsafe {
            if GetKeyboardState(&mut key_state).is_err() {
                key_state.fill(0);
            }
        }
        SystemKeyboardEvent { vk, key_state }
    }
    fn is_key_down(&self, vk: VIRTUAL_KEY) -> bool {
        self.key_state[vk.0 as usize] & (1 << 7) != 0
    }
    pub(super) fn shift(&self) -> bool {
        self.is_key_down(VK_SHIFT)
    }
    pub(super) fn ctrl(&self) -> bool {
        self.is_key_down(VK_CONTROL)
    }
    pub(super) fn alt(&self) -> bool {
        self.is_key_down(VK_MENU)
    }
    pub(super) fn caps_lock(&self) -> bool {
        self.key_state[VK_CAPITAL.0 as usize] & 1 != 0
    }
    /// 這個事件本身就是 Win 鍵。
    pub(super) fn is_win_key(&self) -> bool {
        self.vk == VK_LWIN.0 || self.vk == VK_RWIN.0
    }
    /// Win 鍵是否按著（Win+Shift+S 之類的系統快速鍵）。除了執行緒的鍵盤狀態，也看實體按鍵狀態，
    /// 因為系統快速鍵可能在這個執行緒的狀態表更新前就先吃掉按鍵。
    pub(super) fn win_down(&self) -> bool {
        self.is_key_down(VK_LWIN)
            || self.is_key_down(VK_RWIN)
            || unsafe { GetAsyncKeyState(VK_LWIN.0 as i32) < 0 }
            || unsafe { GetAsyncKeyState(VK_RWIN.0 as i32) < 0 }
    }
}
