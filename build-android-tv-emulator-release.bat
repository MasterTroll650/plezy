@echo off
setlocal EnableExtensions

set "REPO_DIR=%~dp0"
set "FLUTTER_SDK=C:\Users\0x539\development\flutter"
set "FLUTTER_CMD=%FLUTTER_SDK%\bin\flutter.bat"
set "ANDROID_SDK=C:\Users\0x539\development\android-sdk"
set "ADB=%ANDROID_SDK%\platform-tools\adb.exe"
set "APKSIGNER=%ANDROID_SDK%\build-tools\36.1.0\apksigner.bat"
set "LOCAL_JDK=C:\Program Files\Java\jdk-27"
set "EMULATOR_APK=%REPO_DIR%build\app\outputs\flutter-apk\app-x86_64-release.apk"

if not exist "%FLUTTER_CMD%" (
  echo FEHLER: Flutter wurde nicht gefunden:
  echo %FLUTTER_CMD%
  pause
  exit /b 1
)

if not exist "%ADB%" (
  echo FEHLER: ADB wurde nicht gefunden:
  echo %ADB%
  pause
  exit /b 1
)

if not exist "%APKSIGNER%" (
  echo FEHLER: APK-Signaturpruefung wurde nicht gefunden:
  echo %APKSIGNER%
  pause
  exit /b 1
)

if not defined JAVA_HOME if exist "%LOCAL_JDK%\bin\java.exe" set "JAVA_HOME=%LOCAL_JDK%"
if defined JAVA_HOME set "PATH=%JAVA_HOME%\bin;%PATH%"
set "ANDROID_HOME=%ANDROID_SDK%"
set "ANDROID_SDK_ROOT=%ANDROID_SDK%"
set "PATH=%ANDROID_SDK%\platform-tools;%FLUTTER_SDK%\bin;%PATH%"

pushd "%REPO_DIR%" || (
  echo FEHLER: Pleazy-Verzeichnis konnte nicht geoeffnet werden.
  pause
  exit /b 1
)

echo.
echo [1/3] Dart-Abhaengigkeiten laden...
call "%FLUTTER_CMD%" pub get
if errorlevel 1 goto :failed

echo.
echo [2/3] Pleazy-Release-APK fuer den x86_64-Android-TV-Emulator bauen...
call "%FLUTTER_CMD%" build apk --release --split-per-abi --target-platform android-x64
if errorlevel 1 goto :failed

if not exist "%EMULATOR_APK%" (
  echo FEHLER: Die erwartete Emulator-APK wurde nicht gefunden:
  echo %EMULATOR_APK%
  goto :failed
)

echo.
echo [3/3] APK-Signatur pruefen...
call "%APKSIGNER%" verify "%EMULATOR_APK%"
if errorlevel 1 goto :failed

echo.
echo ANDROID-TV-EMULATOR-RELEASE ERFOLGREICH GEBAUT:
echo %EMULATOR_APK%
echo.
echo Bei laufendem Emulator installieren mit:
echo "%ADB%" -s emulator-5554 install -r "%EMULATOR_APK%"
popd
exit /b 0

:failed
set "BUILD_EXIT=%ERRORLEVEL%"
if "%BUILD_EXIT%"=="0" set "BUILD_EXIT=1"
echo.
echo ANDROID-TV-EMULATOR-BUILD FEHLGESCHLAGEN. Fehlercode: %BUILD_EXIT%
popd
exit /b %BUILD_EXIT%
