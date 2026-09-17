@echo off
setlocal

set "ANDROID_SDK_ROOT=C:\Users\0x539\development\android-sdk"
set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
set "ANDROID_USER_HOME=C:\Users\0x539\.android"
set "ANDROID_AVD_HOME=C:\Users\0x539\.android\avd"
set "EMULATOR=%ANDROID_SDK_ROOT%\emulator\emulator.exe"

if not exist "%EMULATOR%" (
  echo Android Emulator nicht gefunden: %EMULATOR%
  pause
  exit /b 1
)

start "Pleazy Android TV Emulator" "%EMULATOR%" -avd Pleazy_TV_API_36 -netdelay none -netspeed full

endlocal
