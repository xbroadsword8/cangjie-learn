; 倉頡學習版（PIME）安裝程式。由 windows/package.sh 編譯：makensis -DVERSION=... -DSTAGE=<組好的檔案目錄>
; 實際步驟都在 setup.ps1；這裡只負責解壓、提權、移除程式項目。
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"

Name "倉頡學習版 (PIME)"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\CangjieLearnPIME"
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\CangjieLearnPIME"

!define MUI_WELCOMEPAGE_TEXT "倉頡三代＋上下文選字＋自動學習，標點仿酷倉（加 Ctrl 出全形）。$\r$\n$\r$\n需要 PIME 1.3；這台電腦沒有的話，安裝過程會先開啟附帶的 PIME 1.3.0 安裝程式。"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "TradChinese"


Section "Install"
  SetOutPath "$PLUGINSDIR\payload"
  File /r "${STAGE}\cjlearn"
  File "${STAGE}\smoke_pime.py"
  File "${STAGE}\PIME-1.3.0-stable-setup.exe"
  File "${STAGE}\MinGit-*-64-bit.zip"
  SetOutPath "$INSTDIR"
  File "${STAGE}\setup.ps1"

  DetailPrint "安裝中（記錄：%TEMP%\cangjie-learn-setup.log）"
  nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\setup.ps1" -Source "$PLUGINSDIR\payload" -PimeSetup "$PLUGINSDIR\payload\PIME-1.3.0-stable-setup.exe"'
  Pop $0
  ${If} $0 != 0
    SetOutPath "$TEMP"
    RMDir /r "$INSTDIR"
    MessageBox MB_ICONSTOP "安裝失敗，原因寫在 %TEMP%\cangjie-learn-setup.log。"
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "倉頡學習版 (PIME)"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
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
  nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\setup.ps1" -Uninstall $1'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "移除失敗，原因寫在 %TEMP%\cangjie-learn-setup.log。"
    Abort
  ${EndIf}
  Delete "$INSTDIR\setup.ps1"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd

Function .onInit
  SetRegView 64
  InitPluginsDir
FunctionEnd

Function un.onInit
  SetRegView 64
FunctionEnd
