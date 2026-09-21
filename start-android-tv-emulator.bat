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

rem Kaltstart und Software-GPU vermeiden einen haengenden Quick-Boot-Snapshot
rem bzw. einen schwarzen Bildschirm bei problematischen Grafiktreibern.
start "Pleazy Android TV Emulator" "%EMULATOR%" -avd Pleazy_TV_API_36 -no-snapshot -gpu swiftshader_indirect -netdelay none -netspeed full

endlocal
