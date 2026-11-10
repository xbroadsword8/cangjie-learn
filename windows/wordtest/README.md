# Word 輸入法相容性測試（Win11 測試機 實機）

重現 PIME 1.3 的「Word 拖曳尺規後中文打不出字」bug（PIME #748／#840／#859），並拿來驗收新的 TSF 外殼。

- `wordtest.ps1`：在互動桌面跑。Word 開兩份文件，每回合「打一個『我』→ 貼圖或拖尺規 → 再打 → 切文件二打」，用 COM 讀回文字判斷成敗；
  失敗時再按數字 5 區分「輸入法壞了」（5 打得進去）和「按鍵沒送到」（5 也打不進去）。
- `runwt.ps1 <紀錄名> <按鍵> <回合> [ruler]`：從 ssh（session 0）用排程在登入者桌面跑 wordtest.ps1，等它結束並印出紀錄。
  按鍵：倉頡學習版 `h,q,i,space`、新酷音 `j,i,3,return`。
- `setime.ps1 <InputTip>`：把輸入法加進中文清單並設為新程式的預設；`restore.ps1`：恢復 Win11 測試機 測試前的清單順序（GUID 寫死）。
- `dumpui.ps1`：開 Word 截圖並列出相關 UIA 元素（找尺規位置用）。

⚠ 尺規座標寫死為 Win11 測試機（2560×1440、Word 最大化）左縮排方塊 (996,184)。Word 的尺規沒有 UIA，換機器要先用 dumpui.ps1 截圖重量。
⚠ 在 Word 裡不能用「按 Alt 取得前景」的技巧：單按 Alt 會叫出功能區快速鍵，後面的字母全被吃掉。
⚠ PowerShell 參數字串以 `-` 開頭會被當成參數名稱，所以排程參數在 runwt.ps1 內組，不從外面傳。

## 長文件重打（retype）與截圖測試（snip）

- `gen_plan.py <論文.docx> <data/raw> <輸出目錄>`（需 `parse_thesis.py`）：把文件片段轉成操作清單 plan.json（中文→新酷音注音鍵，以 tsi.csv 最長詞比對決定破音字），並抽出用到的圖片。
- `retype.ps1`（經 `runwt.ps1 retype-<名> x 99999 "" <秒>`）：照清單在 Word 打字、標點、英數（Shift 切英文）、頁首、分節、分頁、表格（Tab 換格）、註腳、
  書目引用（CITATION）、圖說（SEQ）、拖尺規、四種放圖（AddPicture／剪貼簿貼上／複製文件內圖再貼／真的 Win+Shift+S）、最後產生目錄；每步用 Word COM 讀回驗證。
- `snip.ps1`（`runwt.ps1 snip-chewing|snip-pime x <回合>`）：只測 Win+Shift+S 截圖貼上，失敗時依序試恢復方式。
- `kb.ps1`：共用按鍵、`UseTip`（用 ITfInputProcessorProfileMgr::ActivateProfile 切整個工作階段的輸入法，並打一個「我」確認）。

⚠ **一定要確認目前真的是要測的輸入法**：Set-WinDefaultInputMethodOverride 對已登入工作階段不一定生效（2026-11-09 兩輪「新酷音」探測其實測到倉頡學習版）。用 `UseTip`。
⚠ 判斷「輸入法死了」要排除自己的錯：不存在的注音（如把「表」寫成ㄈㄧㄢˇ）也會什麼都不出；英文模式下 Enter 會換段，只看目前段落會漏掉打出的字母——讀整個 story。
⚠ 副作用：在文件加書目來源，Word 會同步寫進 `%APPDATA%\Microsoft\Bibliography\Sources.xml`（主要來源清單）；測完要清掉（2026-11-10 已移到 cjtest）。存檔的 docx 會進 Word 最近使用清單。
⚠ PowerShell 參數傳字串 "0" 是 true（`$Limit -and ...`），不限制要傳大數字。
