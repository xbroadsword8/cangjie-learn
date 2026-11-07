# Windows 安裝程式 VM 測試

libvirt 主機上的 VM `cj-win10`（從示波器專案的 VM 複製，Windows 10 LTSC 評估版，開機自動登入，ssh 經主機轉發埠）。
快照：`base4`（中文（台灣）、VC++、Windows Update 關閉、Chrome／Firefox／Edge／記事本／檔案總管開著、沒有 PIME）、
`pime-only`（再加 PIME 1.3 `/S` 並重開機）、`installed`（裝過倉頡學習版）。

```text
export CJ_LIBVIRT_HOST=<libvirt 主機的 ssh 名稱> CJ_VM_HOST=<轉發 VM ssh 的位址> CJ_VM_PORT=<轉發埠> CJ_VM_USER=<VM 帳號> CJ_VM_KEY=<私鑰路徑>
export CJ_VMTEST_DIR=<放 w、shot、*.ps1、kh 的工作目錄，也是 trials/ 的輸出處>
SETUP=windows/dist/cangjie-learn-pime-setup-<日期>.exe $CJ_VMTEST_DIR/trial.sh <回合> <快照>
```
`trial.sh`：還原快照 → 在互動桌面開偵測（probe.ps1，每 0.5 秒對所有視窗送 WM_NULL）與自動點按鈕（autoclick.ps1）→ 執行安裝程式 →
在舊記事本打 abc、在新記事本（預設輸入法設成倉頡學習版）打 hqi␣ → 讀回文字＋安裝紀錄＋卡死紀錄，存到 `trials/<回合>/`。
重點：ssh 進來是 session 0，看不到桌面；要碰桌面一律用 `runi.ps1`（Interactive 排程）。PowerShell 5.1 讀中文腳本要 UTF-8 BOM。
