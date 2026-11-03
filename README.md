# 倉頡學習版（IBus 引擎 `cangjie-learn`）

倉頡三代碼表（取自 ibus-table），改了兩件事：

1. **選字看上下文、會學習**：候選字依「前 1–3 個字＋候選字是否組成常用詞」（libchewing 詞頻）＋「你自己的用字紀錄」排序。完整碼命中的字永遠排在補完候選前面。手動選了非第一候選＝糾正，一次記 3 筆。學習資料存在 `~/.local/share/cangjie-learn/user.db`。
2. **標點仿酷倉**：中文模式下標點鍵預設出半形，**加 Ctrl 才出中文標點**。單按一下 Shift 切換中／英。

## Ctrl＋標點對照

| 按鍵 | 出 | 按鍵 | 出 |
|---|---|---|---|
| Ctrl+, | ， | Ctrl+. | 。 |
| Ctrl+; | ； | Ctrl+Shift+; | ： |
| Ctrl+Shift+/ | ？ | Ctrl+Shift+1 | ！ |
| Ctrl+' 或 Ctrl+\ | 、 | Ctrl+[ / ] | 「 」 |
| Ctrl+Shift+[ / ] | 『 』 | Ctrl+Shift+9 / 0 | （ ） |
| Ctrl+Shift+, / . | 《 》 | Ctrl+Shift+6 | …… |
| Ctrl+Shift+- | —— | Ctrl+Shift+` | ～ |

完整對照表寫在 `cjlearn/composer.py` 的 `CJK_PUNCT`。

Ctrl＋標點的字會在**放開 Ctrl 後約 0.03 秒**才出現：Chrome 會丟掉「帶 Ctrl 的按鍵處理期間」送出的字，
在實際桌面上連「Ctrl 還按著」時送的也會丟（一般網頁：2026-10-31 在真桌面實測；DevDesk 的 xterm.js：隔離環境重現），所以一定要等放開 Ctrl。按住 Ctrl 連點幾下、或緊接著打中文字，順序都不會亂。
各應用程式的實測：`python3 tests/app_probe.py chrome|xterm|gtk4`，加 `PROBE_SEQ=burst` 或 `PROBE_SEQ=hold` 測連點與按住。

## 其他按鍵

空白鍵送出第一候選；1–9 選字；`-`／`=`／PageUp／PageDown 翻頁；方向鍵移動游標；Enter 把打到一半的碼當英文字母送出；Esc 取消。補完候選後面的灰字是還沒打的部件。

**打錯碼按空白清掉**（預設開）：碼打錯、沒有任何候選字時，按空白或數字鍵直接清掉字碼（鍵不外漏），不會停在那裡。
開關：Linux 在 IBus 輸入法選單、Windows 在工作列「中／英」圖示按右鍵、Mac 在選單列輸入法選單。
選項存在學習資料旁的 `settings.json`（`{"clear_on_error": true}`，三個平台格式相同，`cjlearn/settings.py`）。

## 安裝與移除

```text
./install.sh          # 建 data/model.db、註冊到 ibus、重啟 ibus（不需 root）
python3 -m pytest -q tests          # 邏輯測試
python3 tests/e2e_ibus.py           # 端到端：隔離的 ibus-daemon，不碰使用者的 ibus 與學習資料
python3 tests/app_probe.py chrome   # 隔離 Xvfb＋真的 Chrome／xterm／GTK4，模擬實體按鍵
```

安裝做的事：`~/.local/libexec/ibus-engine-cangjie-learn`（啟動殼）、`~/.local/share/cangjie-learn/component/cangjie-learn.xml`、
systemd drop-in `~/.config/systemd/user/org.freedesktop.IBus.session.GNOME.service.d/cangjie-learn.conf`（設 `IBUS_COMPONENT_PATH`）。
⚠ `IBUS_COMPONENT_PATH` 會**取代**系統路徑，所以一定要含 `/usr/share/ibus/component`，否則 ibus 起不來（2026-10-28 踩過）。

移除：刪掉上面三個檔、`systemctl --user daemon-reload && systemctl --user restart org.freedesktop.IBus.session.GNOME.service`，再從 GNOME 輸入來源拿掉「倉頡學習版」。

## 資料來源

- 碼表：`/usr/share/ibus-table/tables/cangjie3.db`
- 詞頻：libchewing-data `tsi.csv`／`word.csv`（LGPL-2.1-or-later），放 `data/raw/`；`scripts/build_data.py` 產生 `data/model.db`

紀錄：引擎 log 在 `~/.cache/cangjie-learn/engine.log`。

## Windows 版（PIME）

外殼在 `windows/pime/cjlearn/`（`cjlearn_ime.py` 接 PIME、`keymap.py` 把 Windows 鍵碼翻成 keysym），核心直接沿用 `cjlearn/model.py`、`composer.py`。
⚠ PIME 1.3 的 DLL 只在 onKeyDown／onKeyUp 給 edit session；filterKeyDown／filterKeyUp／onCommand 的回覆若帶 showMessage，會對空指標取值讓宿主程式當掉（`PIMEClient.cpp:133`，2026-11-01 讓 explorer.exe 當掉過）。畫面相關回覆一律留到 onKeyDown／onKeyUp，`test_no_session_replies_are_safe` 守著這條。
與 Linux 版差異：Ctrl＋標點是當下就出字（TSF 在按鍵處理中送字沒問題，不用等放開 Ctrl）；組字中按 Tab 等鍵會送出第一候選並吃掉該鍵。

```text
windows/build.sh                     # 組出 windows/build/cjlearn/（外殼＋核心＋data/model.db）
python3 -m pytest -q tests           # 含 test_windows_pime.py：用 PIME 1.3 的 textService.py 模擬 Windows 按鍵
```

**安裝程式**：`windows/package.sh` → `windows/dist/cangjie-learn-pime-setup-<日期>.exe`（NSIS 外殼＋`windows/installer/setup.ps1` 做實際步驟，附 PIME 1.3.0 官方安裝檔，sha256 寫在 package.sh）。
makensis 不需 root：`apt-get download nsis nsis-common` 後 `dpkg -x` 到 `~/.local/opt/nsis`（package.sh 會自動做）。
setup.ps1 流程：找 PIME（沒有就開附帶的安裝程式）→ 複製 → 用 PIME 的 Python 跑 smoke_pime.py（沒過就撤回）→ regsvr32 → 重開後端 → 加入輸入法清單。移除會清 TSF profile 與清單、預設保留學習資料。
2026-11-02 在 Win11 測試機 實測 `/S` 安裝（蓋舊版、全新）與移除皆正確，酷倉不受影響；**「沒有 PIME 的電腦」路徑未實測**。成品放 Google Drive `倉頡學習版/`。

手動安裝（Win11 測試機，PIME 1.3.0、內建 Python 3.8.10 32 位元；2026-10-31 裝）：
1. 把 `windows/build/cjlearn` 複製到 `C:\Program Files (x86)\PIME\python\input_methods\cjlearn`
2. 系統管理員執行 `System32\regsvr32 /s PIME\x64\PIMETextService.dll` 與 `SysWOW64\regsvr32 /s PIME\x86\PIMETextService.dll`（註冊時會掃 input_methods 的 ime.json）
3. 結束 PIME 的 `python.exe server.py`，PIMELauncher 會自動重開並載入新輸入法
學習資料：`%APPDATA%\PIME\cjlearn\user.db`。移除：刪掉該目錄後重做第 2、3 步。
在 Windows 上冒煙測試：`PIME\python\python3\python.exe windows\smoke_pime.py <含 input_methods\cjlearn 的目錄> <PIME\python>`

## Mac 版（InputMethodKit）

`mac/Core/`：核心的 Swift 移植（Model、Composer），`mac/App/`：IMK 外殼（KeyMap 用實體鍵位碼、自繪候選窗、Shift／Ctrl 處理）。
model.db／user.db 格式與 Linux／Windows 相同；學習資料在 `~/Library/Application Support/CangjieLearn/user.db`。

```text
mac/build.sh                 # 在 Mac 上：編譯 → ~/Library/Input Methods/CangjieLearn.app → 註冊（需先把 data/model.db 帶過去）
python3 mac/tests/gen_cases.py   # 產生差分測試 cases.json（要在 Mac 上跑：log1p 在 glibc 與 macOS libm 差 1 ulp，Linux 產生的預期值會有 279/3000 不符）
```
- 差分測試：`swiftc -O mac/Core/*.swift mac/tests/DiffTest.swift -o difftest && ./difftest data/model.db mac/tests/cases.json <暫存 user.db>`，3000 組隨機按鍵與 Python 版逐步比對（2026-11-03：3000/3000）。
- 外殼測試：`mac/tests/ShellTest.swift` 用假輸入框＋合成 NSEvent 驅動控制器（編譯指令寫在檔頭；IMKInputController 建立時 client 要給 nil，假 client 只在呼叫時傳）。2026-11-03：19/19，把逗號鍵位改錯會抓到。
- 從 ssh 執行 `TISEnableInputSource` 不會生效，第一次要在「系統設定 → 鍵盤 → 輸入方式」手動加入。
- 開發機 Mac 測試機 `~/cjlearn-dev/`。
