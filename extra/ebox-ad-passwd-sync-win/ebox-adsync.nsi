; Generated NSIS script file (generated by makensitemplate.phtml 0.21)
; by 163.118.3.50 on Jun 05 02 @ 12:36

; Kervin Pierre, kervin@blueprint-tech.com
; 05JUN02

; Modified by eBox Technologies S.L. (2009-2010)

!define PRODUCT_NAME "Zentyal AD Password Sync"
!define PRODUCT_VERSION "2.0"
!define PRODUCT_PUBLISHER "eBox Technologies S.L."
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\ebox_adsync_config.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"

SetCompressor bzip2

; MUI 1.67 compatible ------
!include "MUI.nsh"

; MUI Settings
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"

; Welcome page
!insertmacro MUI_PAGE_WELCOME
; License page
!define MUI_LICENSEPAGE_CHECKBOX
!insertmacro MUI_PAGE_LICENSE "LICENSE.txt"
; Directory page
!insertmacro MUI_PAGE_DIRECTORY
; Instfiles page
!insertmacro MUI_PAGE_INSTFILES
; Finish page
!insertmacro MUI_PAGE_FINISH

; Uninstaller pages
!insertmacro MUI_UNPAGE_INSTFILES

; Language files
!insertmacro MUI_LANGUAGE "English"

; Reserve files
!insertmacro MUI_RESERVEFILE_INSTALLOPTIONS

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "zentyal-adsync-${PRODUCT_VERSION}.exe"
InstallDir "$PROGRAMFILES\ebox-adsync"
InstallDirRegKey HKEY_LOCAL_MACHINE "SOFTWARE\Account Synchronization Project\ebox-adsync" ""
ShowInstDetails show
ShowUnInstDetails show

Section "" ; (default section)
  SetOutPath "$INSTDIR"
  SetOverwrite ifnewer
  ; add files / whatever that need to be installed here.
  WriteRegStr HKEY_LOCAL_MACHINE "SYSTEM\CurrentControlSet\Control\Lsa\ebox-adsync" "workingdir" "$INSTDIR"
  WriteRegStr HKEY_LOCAL_MACHINE "Software\Microsoft\Windows\CurrentVersion\Uninstall\ebox-adsync" "DisplayName" "$(^Name) (remove only)"
  WriteRegStr HKEY_LOCAL_MACHINE "Software\Microsoft\Windows\CurrentVersion\Uninstall\ebox-adsync" "UninstallString" '"$INSTDIR\uninst.exe"'

  ; copy files
  File passwdHk.reg
  File AUTHORS.txt
  File LICENSE.txt
  File README.passwdHk.txt
  File ebox_adsync_config.exe
  ; python files
  File _ctypes.pyd
  File _socket.pyd
  File _ssl.pyd
  File bz2.pyd
  File Crypto.Cipher.AES.pyd
  File select.pyd
  File unicodedata.pyd
  File setup-service.bat
  File ebox-service-launcher.exe
  File ebox-pwdsync-service.exe
  File ebox-pwdsync-hook.exe
  File zentyal-enable-hook.exe
  File library.zip
  File python26.dll
  SetOutPath $SYSDIR
  File passwdHk.dll
  SetOutPath $INSTDIR

  ; Make Shortcuts
  ReadRegStr $OUTDIR HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" "Common Administrative Tools"
  StrCmp $OUTDIR "" nocommon
  CreateShortCut "$OUTDIR\Zentyal AD Password Sync Configuration.lnk" "$INSTDIR\ebox_adsync_config.exe"
nocommon:

  ; Install VC++ redistributable package
  SetOutPath $TEMP
  DetailPrint "Installing VC++ 2008 runtime"
  File vcredist_x86.exe
  Exec "$TEMP\vcredist_x86.exe /q"
  DetailPrint "Cleaning up"
  Delete $TEMP\vcredist_x86.exe

  SetOutPath $INSTDIR ; restore $OUTDIR

  DetailPrint "Running configuration wizard"
  ExecWait "$INSTDIR\ebox_adsync_config.exe"

  ; setup the service
  DetailPrint "Installing the service"
  ExecWait '"$INSTDIR\setup-service.bat" $INSTDIR'
  DetailPrint "Cleaning up"
  Delete "$INSTDIR\setup-service.bat"

  MessageBox MB_ICONEXCLAMATION|MB_OK "Warning: Make sure you enable the 'complexity requirements' under 'Password Policy' in 'Administrative Tools -> Domain Security Policy -> Account Policies'. Otherwise the password synchronization won't work."
  MessageBox MB_OK "Please restart before changes can take effect."

  ; write out uninstaller
  WriteUninstaller "$INSTDIR\uninst.exe"
SectionEnd ; end of default section


Function un.onUninstSuccess
  HideWindow
  MessageBox MB_ICONINFORMATION|MB_OK "$(^Name) successfully uninstalled."
FunctionEnd

Function un.onInit
  MessageBox MB_ICONQUESTION|MB_YESNO|MB_DEFBUTTON2 "Are you sure you want to uninstall $(^Name)?" IDYES +2
  Abort
FunctionEnd

Section Uninstall
  ExecWait '"$INSTDIR\ebox-service-launcher.exe" -u'
  Delete "$INSTDIR\passwdHk.reg"
  Delete "$INSTDIR\AUTHORS.txt"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\README.passwdHk.txt"
  Delete "$INSTDIR\ebox_adsync_config.exe"
  Delete "$INSTDIR\_socket.pyd"
  Delete "$INSTDIR\_ssl.pyd"
  Delete "$INSTDIR\_ctypes.pyd"
  Delete "$INSTDIR\bz2.pyd"
  Delete "$INSTDIR\Crypto.Cipher.AES.pyd"
  Delete "$INSTDIR\select.pyd"
  Delete "$INSTDIR\unicodedata.pyd"
  Delete "$INSTDIR\ebox-service-launcher.*"
  Delete "$INSTDIR\ebox-pwdsync-service.exe"
  Delete "$INSTDIR\ebox-pwdsync-hook.exe"
  Delete "$INSTDIR\zentyal-enable-hook.exe"
  Delete "$INSTDIR\library.zip"
  Delete "$INSTDIR\python26.dll"
  Delete /REBOOTOK "$SYSDIR\passwdHk.dll"
  Delete "$INSTDIR\uninst.exe"
  DeleteRegKey HKEY_LOCAL_MACHINE "SOFTWARE\Account Synchronization Project\ebox-adsync"
  DeleteRegKey HKEY_LOCAL_MACHINE "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ebox-adsync"
  DeleteRegKey HKEY_LOCAL_MACHINE "SYSTEM\CurrentControlSet\Control\Lsa\ebox-adsync"
  ReadRegStr $OUTDIR HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" "Common Administrative Tools"
  Delete "$OUTDIR\Zentyal AD Password Sync Configuration.lnk"
  RMDir "$INSTDIR"
SectionEnd

