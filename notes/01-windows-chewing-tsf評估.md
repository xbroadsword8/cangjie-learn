# windows-chewing-tsf 改裝倉頡的可行性評估（2026-11-09）

評估對象：https://codeberg.org/chewing/windows-chewing-tsf ，commit `db0cb4e`（2026-11-08，版本 26.11.724），clone 在
`（本機暫存目錄）`。
以下路徑皆相對於該 repo。**只做評估，沒有實作。**

## 1. 架構：TSF 外殼與 libchewing 的介面

- 專案是 Rust workspace：`Cargo.toml:2-8` 的成員為 `chewing_tip_core`、`chewing_tip_host`、`tsfreg`、`tip`、`xtask`；`chewing = "0.14.0-rc.1"` 見 `Cargo.toml:16`。
- **目前實際在用的是 `tip/`（cdylib，`tip/Cargo.toml:8-9`）：引擎在 DLL 內、同行程呼叫。** `crates/chewing_tip_host`（獨立 exe，經 named pipe 的 IPC，`crates/chewing_tip_core/src/ipc/messages.rs` 定義 OnKeyDown 等訊息）看起來是進行中的「引擎搬到行程外」重構：`grep ipc tip/src` 零結果，`tip` 沒有用到 IPC；`chewing_tip_host` 目前只拿來跑候選窗／通知 UI 與更新（`installer/windows-chewing-tsf.wxs` 以 URL protocol 啟動它）。**要改的以 `tip/` 為準，不要碰 host 那套（它有一份重複的 chewing.rs 353 行，之後上游若切換架構會有合併成本）。**
- 呼叫鏈（按鍵進來 → 組字／候選／送字）：
  - TSF 回呼 `tip/src/text_service/mod.rs:360 OnTestKeyDown`、`:408 OnKeyDown`、`:430 OnKeyUp`（`key_busy` 旗標在 `:411/:433`）。
  - 轉進 `tip/src/text_service/chewing.rs:384 on_test_keydown`（決定吃不吃鍵）、`:514 on_keydown`（真正處理）、`:746/:757 on_test_keyup/on_keyup`（Shift 單按切換）。
  - 虛擬鍵碼 → keysym：`tip/src/text_service/key_event.rs:69 to_keyboard_event`、表在 `:262` 起。
  - 餵引擎：`chewing.rs:612-694` 的 `self.chewing_editor.process_keyevent(evt)`；之後讀 `last_key_behavior()`（`:698`）、`display_commit()`/`ack()`（`:719-732`）、`notification()`（`:704`）。
  - 組字字串：`:997 update_preedit` 讀 `cursor()`、`syllable_buffer_display()`、`intervals()`（`:1000-1005`），再 `:1083 set_composition_string` 寫進 TSF。
  - 候選：`:1187 update_candidates` 讀 `is_selecting()`、`paginated_candidates()`、`total_page()`、`current_page_no()`（`:1189-1205`）餵 `candidate_list.set_model(Model{items: Vec<String>, …})`（`:1220`）。
  - 送字：`:1057 insert_text` 經 `edit_session.rs`（`RequestEditSession`，`edit_session.rs:30`；`SetText`，`:138`）。
- 要換引擎要動的檔案與行數（估計）：
  - `tip/src/text_service/chewing.rs`（1647 行）：與 `Editor` 耦合的區段約 800 行要重寫——按鍵處理 `:384-745`（含 chewing 專屬的選字鍵、`Ctrl+數字` 加詞、`selecting_unlearn_phrase`，`:631-690` 可整段刪）、preedit `:997-1056`（倉頡沒有注音游標分段，可大幅簡化）、候選 `:1187-1250`、設定同步 `:1403-1500`（全部是 chewing 選項，可刪光）、簡繁、全形切換 `:1254-1315`。
  - `tip/src/keybind.rs`（182 行）、`tip/src/text_service/key_event.rs`（316 行）：用到 `chewing::input::{KeyboardEvent, keysym}` 型別，可繼續依賴 chewing crate 只借型別，或自己定義（約 100 行）。
  - `crates/chewing_tip_core/src/config.rs`（752 行）：全是新酷音選項（登錄檔），倉頡版只需少數幾項，要大砍；`shell.rs:23` 用 `chewing::path::data_dir()` 找資料夾，要換。
  - `Cargo.toml`/`tip/Cargo.toml`：拿掉 `chewing`、`zhconv`（簡繁輸出），加 `rusqlite`（bundled）。
  - 新增：`tip/src/cangjie/{composer,model}.rs`（見第 6 題）。
- 可原封不動沿用：候選窗（`tip/src/text_service/ui_elements/candidate_list.rs` 750 行＋`tip/src/ui/gfx.rs`、`window.rs`，Direct2D/DirectComposition）、通知窗（`ui_elements/notification.rs`）、語言列按鈕與中／英圖示（`lang_bar.rs` 337 行、`icons.rs`、`tip/rc/*.ico`）、COM/DLL 註冊樣板（`com.rs`、`lib.rs`）、顯示屬性（`display_attribute.rs`）、`tsfreg`（`crates/tsfreg`，204 行，只需改 GUID 與名稱）、`FpGuard` 浮點環境保護（`quirk.rs:79-149`）、`edit_session.rs` 的送字／組字機制。
- **偏好設定程式**不在這個 repo：README 寫「preferences contains…」但 workspace 沒有它；MSI 只裝預先建好的 `ChewingPreferences.exe`／`chewing-editor.exe`（`installer/windows-chewing-tsf.wxs:19-28`）。倉頡版不需要，直接從 wxs 拿掉即可（連同 `WebView2Loader.dll`、`chewing-cli.exe`）。

## 2. 我們需要的功能，它有沒有

| 需求 | 結果 | 出處與要做的事 |
|---|---|---|
| Ctrl＋標點在按鍵處理中直接送字 | **沒有，且預設相反** | `chewing.rs:458-474`：只要 Ctrl 按著就 `return Ok(false)` 放行給應用程式（唯一例外是組字中的數字與 `easy_symbols_with_shift_ctrl`）。要在這裡加「Ctrl＋標點 → 回 true」分支，`on_keydown` 再用 `insert_text` 送字。**風險：我們 Linux 版發現 Chrome 會丟掉「Ctrl 還按著時送的字」（README 第 18-19 行）；TSF 的 edit session 在 Ctrl 按住時送字，在各 Windows 應用程式的行為沒有證據，要實測；退路是比照 Linux 在 Ctrl 放開（`on_keyup`）才送。** |
| 單按 Shift 切中英 | **有** | `chewing.rs:402-409`（keydown 記錄 `ShiftKeyState::Down(Instant)`）＋`:757-790`（keyup 在 `shift_key_sensitivity` 毫秒內放開就 `toggle_lang_mode`）；選項 `switch_lang_with_shift`。可直接沿用。 |
| 候選字旁灰色未打字根 | **沒有** | 候選項只有 `items: Vec<String>`（`candidate_list.rs:81`），繪製迴圈 `:445-500` 每項只畫一次 `DrawText`。要加：Model 加 `hints: Vec<String>`，在 `:467-492` 的文字後面用淡色筆刷（仿 `selkey_brush`）多畫一段，並在 `calculate_client_rect`（`:221-300`）把寬度算進去。約 60-100 行，單純。 |
| 輸入法選單的勾選選項 | **有機制** | 選單來自資源檔 `tip/rc/ChewingTextService.rc:117-143`（`IDR_MENU`，現有「輸出全形英數字母」「輸出簡體中文」兩個勾選項）；顯示時 `CheckMenuItem(self.popup_menu, ID_SWITCH_SHAPE, …)`（`chewing.rs:1521-1529`），點擊在 `on_command`（`:926-996`）。加「打錯碼按空白清掉」「標點直接出全形」＝改 rc、加 `resource.h` ID、兩個 `CheckMenuItem`＋寫 `settings.json`（serde_json 已是依賴，`Cargo.toml:21-22`）。約 80 行。選單的右鍵觸發點是語言列「中／英」圖示（`:927-945`），與我們現行 PIME 版的位置一致。 |

## 3. 編譯（實測）

環境：x86_64 Linux、無 sudo、rustup stable 1.96.0、已有 `x86_64-w64-mingw32-gcc` 13-win32 與 `i686-w64-mingw32-gcc`（系統已裝）。

實際執行：
```bash
cd .../wct/windows-chewing-tsf
CARGO_TARGET_DIR=$PWD/../target cargo build -p chewing_tip --release --target x86_64-pc-windows-gnu
```
結果：`Finished release profile in 1m 31s`（含下載相依套件）。產物 `target/x86_64-pc-windows-gnu/release/chewing_tip.dll`，5,220,216 位元組，`file` 回報 `PE32+ executable (DLL) (console) x86-64`；`objdump -p` 顯示只匯入系統 DLL（kernel32、user32、msctf、ole32、d2d1、d3d11、dcomp、dwrite、msvcrt…），**沒有 mingw 執行階段 DLL 相依**。

32 位元：
```bash
rustup target add i686-pc-windows-gnu      # 下載 rust-std 成功
CARGO_TARGET_DIR=$PWD/../target cargo build -p chewing_tip --release --target i686-pc-windows-gnu
```
結果：`Finished release profile in 1m 20s`，成功。

結論：
- **不必在 Windows 上裝 Visual Studio，這台 Linux 用 mingw（gnu 目標）就能交叉編出 x64 與 x86 兩個 DLL。** 上游自己的 CI 也在 Fedora 上用 nix 交叉編（`.forgejo/workflows/ci.yml:28-41`），`xtask/src/installer.rs:40-52` 支援 `gnu`／`gnullvm`／`msvc` 三種目標。
- 32 位元 DLL 的處理方式：xtask 另外用 `i686-pc-windows-*` 目標編一份放 `build/installer/x86`（`installer.rs:112, 165-172`），安裝到 SysWOW64（wxs 的 `SystemFolder`＋`Bitness="always32"`，`windows-chewing-tsf.wxs` 末段）；x64 另有 arm64x 轉發 DLL（`platform/arm64x`，我們用不到 ARM 可略）。
- 未驗證：xtask 的 `build-installer` 全流程（它會 `cargo install chewing-cli`、需 `wix` 與 `RUSTFLAGS=+crt-static`，`installer.rs:74-83`）；我只編了 `chewing_tip`，沒有跑 xtask、沒有跑 `wix build`。加上 rusqlite（bundled，要編 C）後 mingw 能否過，要試（預期可以）。
- 副作用殘留（只回報、不清理）：`~/.cargo/registry`（下載的 crates）、`~/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/i686-pc-windows-gnu`（我新增的 rustup target）、編譯輸出在上述 `wct/target/`。

## 4. 安裝程式

- **WiX v4（MSI）**，不是 NSIS：`installer/windows-chewing-tsf.wxs:5`（`xmlns="http://wixtoolset.org/schemas/v4/wxs"`）；打包指令 `wix build -acceptEula wix7 -arch x64 -culture zh-TW …`（`xtask/src/installer.rs:188`）。我們現行是 NSIS（`windows/installer/cangjie-learn.nsi`）＋`setup.ps1`，要整套換。
- 註冊 TSF **需要系統管理員**：MSI 預設為每台機器安裝，DLL 裝到 `System64Folder`／`SystemFolder`（`wxs` 的 `StandardDirectory Id="System64Folder"`、`SystemFolder`），COM 類別寫 HKLM（`Class … Context="InprocServer32"`）；`RegisterTSF` 自訂動作 `tsfreg.exe -r` 是 `Impersonate="no" Execute="deferred"`（以 SYSTEM 執行），`tsfreg` 用 `LOCAL_MACHINE` 寫登錄檔（`crates/tsfreg/src/main.rs:23`）；`EnableTIP`（`-i`）才是以使用者身分執行，把輸入法加進該使用者的輸入法清單。→ **沒有免系統管理員的安裝路線。**（我們現行 PIME 版安裝程式是否免 admin 另當別論，這是行為差異。）
- 改造時必須換掉：CLSID `13F2EF08-…`、兩個 profile GUID（`tsfreg/src/main.rs:27-29`）、UpgradeCode、名稱與圖示，否則會與使用者機器上已裝的新酷音衝突。
- 簽章／防毒：上游 issue #831「預覽版 26.11.711 安裝到一半會被識別為惡意程式」、#846「無法安裝 …26.11.724.msi」（今天剛開）、#781「WIN11 26H2 安裝預覽版後系統當機無法操作」，見 https://codeberg.org/chewing/windows-chewing-tsf/issues/831 ／846／781。把 DLL 裝進 System32 的做法對防毒與穩定性都敏感，自製版沒有它們的簽章（`ci.yml` 有簽章步驟）。

## 5. 上游 Word／Office 相容性

程式碼：
- `grep -rniE "word|winword|office|excel|powerpoint" --include=*.rs` 只有三處有意義：`tip/src/text_service/mod.rs:299`（`// Excel switches document upon first key down. Skip this superflos focus change.` → `key_busy` 時略過 `OnSetFocus`）、`tip/src/quirk.rs:15`（唯一的 exe 黑名單是 `\MyAB.exe`，跳過 IMM32 patch，與 Office 無關）、`CHANGELOG.md:87`（「restore Excel workaround to avoid premature commits」）。**沒有任何針對 Word／WINWORD 的特殊處理。**
- 它還有 `tip/src/w32/imm32.rs`（115 行）對 IMM32 做 patch，是相容舊程式用，與 Word 貼上無關。

Issue（API 全量抓下 430 筆，以標題／內文比對 word／office／excel／貼上／截圖／尺規，檔案 `scratchpad/issues.json`）：
- #64（2013，已關）「在 word 中突然無法輸入中文，切換中英都是英文」——原因被判為 CapsLock 設定，後來作者說在 Windows Live Writer 也一樣、關閉輸入法重開才行（**症狀與我們 PIME 的 bug 很像，但沒有解法紀錄**）：https://codeberg.org/chewing/windows-chewing-tsf/issues/64
- #145、#406、#101、#66、#179、#217（2013-2024，已關）Office 變黑方塊／黑底看不到字：靠 2024-12 nightly 修（#217：「Word 2019 輸入未選字部分已不會全黑」）；#179 作者當時「無法重現」，使用者另報 PPT 仍黑塊。
- #309（2025，已關）、#706（2026-05，已關）Excel 格子直接打字會多出第一個注音；作者在 #706 回：「之前拿掉一個 Excel 的例外修正，以為已經沒問題了，結果在某些情況還是需要」→ 即 `mod.rs:299` 的現況 workaround。
- **#768（2026-08-24，仍開）「當焦點轉到 PowerPoint 會無法輸入中文」：回報者在 PowerPoint 只能打英數、Shift 無法切回中文，要 Ctrl+Shift 兩次才恢復，從 PPT 切到 MSSQL 也會；作者追問是不是鍵盤 OpenClose 關閉（顯示 (X)）；使用者 2026-10-13 回報 26.9.0.547 後頻率降低但「偶爾仍出現」。這和我們在 Word 遇到的「焦點／內容變化後就打不出中文」很像，上游尚未根治。** https://codeberg.org/chewing/windows-chewing-tsf/issues/768
- 另有「選字窗不會關閉」#809（開）、#775（開）、#763，以及 #707「開始功能表無法輸入」（開）、#788 RustDesk（開）、#734 通話軟體（開）：TSF 版在特殊 UI 元件下的相容問題仍不少。
- 沒有任何回報提到「貼上截圖」或「拖曳尺規」後打不出字；搜尋「截圖」「尺規」零結果。

判讀：改走 TSF **不保證**解掉 Word 這個 bug。TSF 原生版有它自己的 Office 問題史（黑方塊、Excel 錯位、PPT 失效），且最像我們症狀的 #768 還沒修。但 PIME 的 bug 多半出在 PIME 的行程外 IPC＋輸入法橋接層，換成同行程 TSF 理論上少一層；**這必須用實機驗證，而不是推論**（見結論的前置步驟）。

## 6. 工作量粗估（單人、含除錯；Windows 實機測試機另計）

| 項目 | 內容 | 估計 |
|---|---|---|
| 引擎移植 | `cjlearn/composer.py`（225 行）＋`model.py`（101 行）→ Rust，約 500-650 行；SQLite 用 rusqlite（bundled）讀 `model.db` 3.6 MB、寫 `user.db`；`settings.py` 36 行（serde_json）；`sync.py` 235 行（Windows 現行是排程跑 git，`sync` 資料格式為 json，**可選擇不移植、沿用現有排程**，但輸入法讀取其他台次數 `set_peers` 要實作）。可對照 Mac 的 `mac/Core/Composer.swift`（260 行）／`Model.swift`（196 行）逐段翻。 | 3-4 天 |
| 外殼改造 | 重寫 `chewing.rs` 約 800 行（按鍵處理／preedit／候選／選項）、Ctrl＋標點分支（含放開 Ctrl 才送的退路）、灰色打字根提示（60-100 行）、選單兩個勾選項（rc＋約 80 行）、`config.rs` 精簡、去掉簡繁／注音／keybind 動作、去掉自動更新檢查（`chewing_tip_core/src/update*`）、換名稱圖示 GUID。 | 6-8 天 |
| 安裝與註冊 | 改 wxs：拿掉詞庫／偏好設定／編輯器／chewing-cli／WebView2，加 `model.db`、換 GUID／UpgradeCode；`tsfreg` 改名；把學習資料同步排程（`CangjieLearnSync`＋MinGit，現在在 `windows/installer/setup.ps1`）併進 MSI 或另跑；與現行 PIME 版的移轉與共存；32 位元 DLL；`wix` 在 Linux 上的打包流程要實跑。 | 3-4 天 |
| 測試 | Rust 單元測試讀 `mac/tests/cases.json`（由 `gen_cases.py` 產生 3000 組）做差分，可比照 `mac/tests/DiffTest.swift`：1-1.5 天；Windows 實機（Word 貼上截圖＋拖尺規、Excel、PowerPoint、Chrome、記事本、遠端桌面、UAC 視窗）逐項實測，TSF 的時序（Ctrl＋標點、Shift 切換）要反覆試：3-4 天。 | 4-5 天 |
| 合計 | | **約 16-21 個工作天（3-4 週）** |

另需注意：上游節奏很快（近 50 筆 commit 內有 chewing 0.14 rc、Windows on ARM、IPC 架構重構、arm64x 轉發 DLL），**fork 後合併上游修正的成本會持續存在**；授權為 GPL-3.0-or-later（`README.md`、`tip/Cargo.toml:5`），我們的衍生版要以 GPL-3 釋出原始碼（自用則無影響）。

## 結論：**有條件做**

條件（前置驗證，約 0.5-1 天，成本極低）：**先在有 Word 的 Windows 機器上裝上游現成的 26.11.724 MSI（或 nightly），重現「貼截圖／拖尺規」流程。** 能重現（同樣打不出中文）→ 不建議做，改找 PIME 以外的方向或修 PIME；**不能重現（TSF 版撐得住）→ 建議做**，按上表約 3-4 週。

最大的三個風險：
1. **Word bug 不一定因換殼而消失**：上游自己有 Office 相關的懸案（#768 PowerPoint 焦點後無法輸入、仍開；Excel 錯位要靠 workaround #706；歷史上 Word/PPT 黑方塊 #179/#217），且沒有任何針對 Word 的程式碼處理（第 5 題）。不先實測就投入 3-4 週，可能換到另一組 Office 問題。
2. **Ctrl＋標點在 TSF 的行為未知**：上游設計是 Ctrl 一律放行（`chewing.rs:458-474`），我們要攔截；Linux 上已證實 Chrome 會丟 Ctrl 按住時送的字，Windows 各應用程式是否也如此沒有證據，可能要改成放開 Ctrl 才送，牽動 keyup 路徑與時序。
3. **安裝／部署與維護負擔**：MSI 必須系統管理員、DLL 進 System32，上游自己就有安裝被防毒誤判（#831）、無法安裝（#846）、系統當機（#781）的回報；我們沒有程式碼簽章；另外 fork 之後要長期追上游（架構正從同行程改為行程外 IPC，`crates/chewing_tip_host` 與 `ipc/`），合併成本高。

附註：第 3 題的編譯成功只證明外殼與其相依能在這台交叉編出 x64／x86 DLL；沒有在 Windows 上載入或註冊過，也沒有跑 `wix build`。

## 附錄：Word 實機對照測試（2026-11-09，Win11 測試機）

環境：Windows 11、Word 2021（16.0.14334）、PIME 1.3.0-stable＋倉頡學習版 2026.11.07、原版新酷音 v26.11.724 MSI（sha256 與官方一致）。
腳本：`windows/wordtest/`。判定以 Word COM 讀回的文字為準；失敗時以數字鍵是否打得進去區分輸入法故障與按鍵未送達。

| 組別 | 觸發 | 有效觸發次數 | 打字結果 |
|---|---|---|---|
| PIME（倉頡學習版） | 貼圖（剪貼簿放圖＋Ctrl+V） | 40 | 120/120 成功，**沒重現** |
| PIME（倉頡學習版） | 拖曳尺規左縮排 | 3 輪各在第 1–2 次有效拖曳後 | **壞掉**：兩份文件中文都打不出（字母被吃掉、數字打得進去），之後不恢復 |
| 原版新酷音 | 貼圖 | 2 | 6/6 成功 |
| 原版新酷音 | 拖曳尺規左縮排 | 20＋20（兩輪，皆以 COM 確認縮排真的改變） | **60/60＋60/60 全部成功** |

結論：Word 尺規 bug 確定在 PIME 這一層，換成 windows-chewing-tsf 的 TSF 外殼不會中。
貼圖觸發沒重現：腳本是直接放剪貼簿，少了 Win+Shift+S 截圖工具蓋住全螢幕造成的焦點切換，之後要補測。
新酷音 MSI 仍裝在 Win11 測試機（已從輸入法清單移除，「已安裝的應用程式」可解除安裝）。

### 長文件重打（2026-11-10，Win11 測試機，原版新酷音）

自己的碩士論文摘要＋第一章＋第二章前段，照原文在 Word 重打（腳本 `windows/wordtest/retype.ps1`），53 分鐘、1,918 個操作：
經輸入法中文 6,991 字、全形標點 493、英數段 381（Shift 切換約 760 次）、圖 6（四種放法）、表 5（儲存格內打字＋Tab）、註腳 4、書目引用 18、圖說 12、頁首 2、分節、分頁 4、拖尺規 11 次（5 次真的拖到）、目錄。
**輸入法全程沒有死掉**，字數警告 0。成品 docx 內容核對：圖 6、表 5、註腳 4、CITATION 18、SEQ 12、TOC 有。同音字錯（如「多聲道」→「多生到」）是注音自動選字所致，不是外殼問題。

### Win+Shift+S 截圖貼上（`snip.ps1`，各 4 回合）

| 輸入法 | 結果 |
|---|---|
| 原版新酷音 | 4/4 次截圖後被切到**英文模式**（工作列顯示「英」；Win、S 被系統截圖吃掉，新酷音只看到 Shift 按放＝單按 Shift 切換）。按一下 Shift 即恢復，輸入法沒死 |
| 倉頡學習版（PIME） | 4/4 次正常，沒被切換也沒死（`cjlearn_ime.py` 在 Win 鍵按著時不處理按鍵） |

→ fork 時要把「Win 鍵按著時 Shift 不算單按」帶進新外殼，順手修掉新酷音這個問題。
→ PIME issue 回報的「截圖後打不出字」在 Win11 測試機 沒重現；能穩定讓 PIME 死掉的是拖尺規。
