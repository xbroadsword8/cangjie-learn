# 倉頡學習版

[English](README.en.md) | [繁體中文](README.md)

[![下載倉頡學習版](https://img.shields.io/github/v/release/xbroadsword8/cangjie-learn?label=%E4%B8%8B%E8%BC%89%20Windows%20%E7%89%88&style=for-the-badge&logo=windows)](https://github.com/xbroadsword8/cangjie-learn/releases/latest)

下載安裝程式，雙擊執行，裝好就能用。

**倉頡學習版**是一套會學習的倉頡輸入法：選字時會參考你前面打了什麼，也會記住你常用哪個字，越用越順手。支援 Windows 10／11、Linux（IBus）與 macOS。

## 為什麼做這個輸入法

倉頡同碼字很多，傳統倉頡輸入法只用固定字頻排序，同一個碼永遠給同一個字。例如「已」和「己」同碼，打「已經」和「自己」總有一邊要手動選字。

倉頡學習版改成：

- **看上下文選字**：參考前 1–3 個字，以及候選字能不能和它們組成常用詞。打「自」之後給「己」，打「而」之後給「已」，句首打「已經」也不會被「自己」打多了而帶歪。
- **記住你的用字**：手動選了別的字，就當成你在糾正，下次會排前面。
- **完整碼優先**：完整碼對到的字，永遠排在「還沒打完」的補完候選前面。補完候選後面用橘色小字顯示還沒打的部件，順便學字根。
- **標點習慣仿酷倉**：中文模式下標點鍵出半形，**加 Ctrl 才出中文標點**，打程式碼、網址不用一直切換。也可以改成和微軟倉頡一樣直接出全形。

## 下載與安裝（Windows）

從 [Releases](https://github.com/xbroadsword8/cangjie-learn/releases/latest) 下載 `cangjie-learn-setup-<日期>.exe`：

1. 雙擊安裝程式，Windows 詢問是否允許變更時按「是」。
2. 安裝完成後，「倉頡學習版」會自動加進「中文（台灣）」的輸入法清單。
3. 按 **Win＋空白鍵**切換到倉頡學習版。工作列會出現「倉」圖示，旁邊的「中／英」表示目前的輸入模式。

安裝程式沒有程式碼簽章，第一次執行時 Windows SmartScreen 可能出現「Windows 已保護您的電腦」，按「其他資訊 → 仍要執行」。

- **更新**：直接執行新版安裝程式，舊版會自動移除，學習資料保留。
- **移除**：「設定 → 應用程式 → 已安裝的應用程式」找到「倉頡學習版」解除安裝。學習資料預設保留。

Linux 與 macOS 目前要自己從原始碼建置，見下方「建置」。

## 使用方式

| 按鍵 | 作用 |
|---|---|
| 單按 Shift | 切換中文／英文 |
| Shift＋空白 | 切換全形／半形英數（Windows 版） |
| 空白 | 送出第一個候選字 |
| 1–9 | 選字 |
| `-` `=` 或 PageUp／PageDown | 翻頁 |
| Enter | 把打到一半的碼當英文字母送出 |
| Esc | 取消 |

### Ctrl＋標點

| 按鍵 | 出 | 按鍵 | 出 |
|---|---|---|---|
| Ctrl+, | ， | Ctrl+. | 。 |
| Ctrl+; | ； | Ctrl+Shift+; | ： |
| Ctrl+Shift+/ | ？ | Ctrl+Shift+1 | ！ |
| Ctrl+' 或 Ctrl+\ | 、 | Ctrl+[ / ] | 「 」 |
| Ctrl+Shift+[ / ] | 『 』 | Ctrl+Shift+9 / 0 | （ ） |
| Ctrl+Shift+, / . | 《 》 | Ctrl+Shift+6 | …… |
| Ctrl+Shift+- | —— | Ctrl+Shift+` | ～ |

### 選項

在工作列的「倉」或「中／英」圖示上**按右鍵**（Linux 在 IBus 輸入法選單、Mac 在選單列輸入法選單）：

- **打錯碼按空白清掉**（預設開）：碼打錯、沒有候選字時，按空白直接清掉，不會卡在那裡。
- **標點直接出全形**（預設關）：給用慣微軟倉頡的人，不用加 Ctrl 就出 `，。；：？！（）「」` 等全形標點。網址、email、算式常用的 `@ # - = /` 照舊出半形。
- **全形英數**：同 Shift＋空白。

## 學習資料與隱私

- 學習資料只存在你自己的電腦上，輸入法本身**不連網**：
  - Windows：`%APPDATA%\PIME\cjlearn\user.db`
  - Linux：`~/.local/share/cangjie-learn/user.db`
  - macOS：`~/Library/Application Support/CangjieLearn/user.db`
- 想讓多台電腦共用學習資料，可以自行設定一個 git 版本庫來同步（預設關閉），做法見[開發筆記](docs/開發筆記.md#學習資料同步三個平台共用)。

## 限制

- Windows 版只支援 Windows 10／11（x64）。
- Windows 11 開始功能表的搜尋框是沙箱程式，讀不到學習資料，在那裡只會照詞庫選字（不影響打字，學到的也不會存）。
- macOS 版需要自己建置並在「系統設定 → 鍵盤 → 輸入方式」手動加入；Linux 版的 `install.sh` 目前針對 GNOME 的 IBus。

## 建置

選字邏輯有三份實作，用差分測試確保逐步一致：Python（Linux）、Rust（Windows）、Swift（macOS）。

```bash
# Linux（IBus）：建詞庫、註冊到 ibus（不需 root）
./install.sh
python3 -m pytest -q tests
```

```bash
# Windows：在 Linux 交叉編譯並打包 NSIS 安裝程式（需 mingw-w64、rustup target x86_64-pc-windows-gnu）
windows/package-tsf.sh
```

```bash
# macOS：在 Mac 上編譯並安裝到 ~/Library/Input Methods（需先產生 data/model.db）
mac/build.sh
```

實作細節、測試方法與踩過的坑都寫在[開發筆記](docs/開發筆記.md)。

### 專案結構

| 目錄 | 內容 |
|---|---|
| `cjlearn/` | Python 版核心（組字、選字模型、學習）與 IBus 引擎 |
| `windows/tsf/` | Windows 版：新酷音 TSF 外殼改成倉頡（`crates/cangjie_core` 是核心的 Rust 移植，`tip/` 是外殼） |
| `windows/installer/` | Windows 安裝程式（NSIS） |
| `mac/` | macOS 版：`Core/` 核心的 Swift 移植、`App/` InputMethodKit 外殼 |
| `scripts/build_data.py` | 從碼表與詞頻產生 `data/model.db` |
| `tests/` | 邏輯測試、IBus 端到端測試、跨實作差分測試 |

## 致謝與授權

這個輸入法是站在許多人的成果上做出來的，謝謝：

- **朱邦復先生**：發明倉頡輸入法，並放棄專利，讓大家都能自由使用。
- **倉頡之友‧馬來西亞（chinesecj.com）** 與 ibus-table-chinese 的維護者（Yu Yuwei、Caius Chance、Ding-Yi Chen、Mike FABIAN 等人）：整理並開放倉頡三代碼表。本專案的碼表取自 [ibus-table-chinese](https://github.com/mike-fabian/ibus-table-chinese)。
- **新酷音（Chewing）專案團隊**：
  - Windows 版的 TSF 外殼改自 [windows-chewing-tsf](https://github.com/chewing/windows-chewing-tsf)（GPL-3.0-or-later）。我們把注音引擎換成自己的倉頡核心，其餘的視窗、圖示、安裝與相容性處理大多沿用他們多年累積的成果。原版權聲明與授權全文保留在 `windows/tsf/`。
  - 選字用的詞頻來自 [libchewing-data](https://github.com/chewing/libchewing-data)（LGPL-2.1-or-later）。
- **PIME 專案**（[EasyIME/PIME](https://github.com/EasyIME/PIME)）：舊版 Windows 輸入法（`windows/pime/`）跑在 PIME 上。
- **酷倉**：「加 Ctrl 才出中文標點」的習慣是照酷倉的用法做的。
- 安裝程式用 [NSIS](https://nsis.sourceforge.io/) 打包，內附 [MinGit](https://github.com/git-for-windows/git)（Git for Windows，GPL-2.0）供學習資料同步使用。

授權：[GPL-3.0](LICENSE)。可以自由使用、修改、再散布；再散布修改版時，必須一併公開原始碼並沿用同一授權。

本軟體依「現狀」提供，不負任何擔保。

Windows 是 Microsoft 的商標，本專案與 Microsoft 無關。
