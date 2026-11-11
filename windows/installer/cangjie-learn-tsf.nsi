; 倉頡學習版（TSF 原生版）安裝程式。由 windows/package-tsf.sh 編譯：makensis -DVERSION=... -DSTAGE=<組好的檔案目錄>
; 實際步驟都在 setup-tsf.ps1；這裡只負責解壓、提權、移除程式項目。
Unicode true
; 英文版 Windows 的對話框預設字型沒有中文字（標題、按鈕會變方塊）：指定 Windows 10 起內建的微軟正黑體
SetFont "Microsoft JhengHei UI" 9
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

Name "倉頡學習版"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\CangjieLearn"
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\CangjieLearn"
; NSIS 是 32 位元：一律叫 64 位元的 PowerShell（Sysnative），登錄檔與 Program Files 才不會被轉向
!define PS '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File'

!define MUI_WELCOMEPAGE_TEXT "倉頡三代＋上下文選字＋自動學習，標點仿酷倉（加 Ctrl 出全形）。$\r$\n$\r$\n這一版是 Windows 原生輸入法，不需要 PIME。$\r$\n若裝過舊的 PIME 版倉頡學習版，會自動換掉，學習紀錄照樣保留（PIME 與酷倉不受影響）。"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "TradChinese"

Section "Install"
  SetOutPath "$PLUGINSDIR\payload"
  File /r "${STAGE}\x64"
  File /r "${STAGE}\x86"
  File "${STAGE}\model.db"
  File "${STAGE}\tsfreg.exe"
  File "${STAGE}\cjlearn.ico"
  File "${STAGE}\cjlearn-sync.exe"
  File "${STAGE}\MinGit-*-64-bit.zip"
  SetOutPath "$INSTDIR"
  File "${STAGE}\setup-tsf.ps1"

  DetailPrint "安裝中（記錄：%TEMP%\cangjie-learn-setup.log）"
  nsExec::ExecToLog '${PS} "$INSTDIR\setup-tsf.ps1" -Source "$PLUGINSDIR\payload"'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "安裝失敗，原因寫在 %TEMP%\cangjie-learn-setup.log。"
    SetOutPath "$TEMP"
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "倉頡學習版"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\cjlearn.ico"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "xmac"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  StrCpy $1 ""
  IfSilent +3
  MessageBox MB_YESNO|MB_DEFBUTTON2 "也要刪除學習資料（你的用字紀錄）嗎？$\r$\n選「否」會保留，之後重裝可以接著用。" IDNO +2
  StrCpy $1 "-RemoveUserData"
  ; 解除安裝程式就在 $INSTDIR 裡：先把 setup-tsf.ps1 複製出去再跑，它才刪得掉整個資料夾
  CopyFiles /SILENT "$INSTDIR\setup-tsf.ps1" "$TEMP\cangjie-learn-uninstall.ps1"
  nsExec::ExecToLog '${PS} "$TEMP\cangjie-learn-uninstall.ps1" -Uninstall $1'
  Pop $0
  Delete "$TEMP\cangjie-learn-uninstall.ps1"
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "移除失敗，原因寫在 %TEMP%\cangjie-learn-setup.log。"
    Abort
  ${EndIf}
  Delete "$INSTDIR\setup-tsf.ps1"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "倉頡學習版只支援 64 位元 Windows。"
    Abort
  ${EndIf}
  SetRegView 64
  InitPluginsDir
FunctionEnd

Function un.onInit
  SetRegView 64
FunctionEnd
