@echo off
setlocal EnableExtensions

set "REPO_DIR=%~dp0"
set "FLUTTER_SDK=C:\Users\0x539\development\flutter"
set "FLUTTER_CMD=%FLUTTER_SDK%\bin\flutter.bat"
set "ANDROID_SDK=C:\Users\0x539\development\android-sdk"
set "APKSIGNER=%ANDROID_SDK%\build-tools\36.1.0\apksigner.bat"
set "LOCAL_JDK=C:\Program Files\Java\jdk-27"
set "ARM32_APK=%REPO_DIR%build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk"
set "ARM64_APK=%REPO_DIR%build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"

if not exist "%FLUTTER_CMD%" (
  echo FEHLER: Flutter wurde nicht gefunden:
  echo %FLUTTER_CMD%
  pause
  exit /b 1
)

if not exist "%ANDROID_SDK%\platform-tools\adb.exe" (
  echo FEHLER: Android SDK wurde nicht gefunden:
  echo %ANDROID_SDK%
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
echo [2/3] Fire-TV-Release-APKs fuer ARM 32-Bit und ARM 64-Bit bauen...
set "AMAZON=1"
call "%FLUTTER_CMD%" build apk --release --split-per-abi --target-platform android-arm,android-arm64
if errorlevel 1 goto :failed

if not exist "%ARM32_APK%" (
  echo FEHLER: Das erwartete 32-Bit-APK wurde nicht gefunden:
  echo %ARM32_APK%
  goto :failed
)

if not exist "%ARM64_APK%" (
  echo FEHLER: Das erwartete 64-Bit-APK wurde nicht gefunden:
  echo %ARM64_APK%
  goto :failed
)

echo.
echo [3/3] APK-Signaturen pruefen...
call "%APKSIGNER%" verify "%ARM32_APK%"
if errorlevel 1 goto :failed
call "%APKSIGNER%" verify "%ARM64_APK%"
if errorlevel 1 goto :failed

echo.
echo FIRE-TV-RELEASE ERFOLGREICH GEBAUT.
echo.
echo Fuer 32-Bit-Fire-TV:
echo %ARM32_APK%
echo.
echo Fuer 64-Bit-Fire-TV:
echo %ARM64_APK%
echo.
echo Fire-TV-ABI pruefen: adb shell getprop ro.product.cpu.abilist
popd
exit /b 0

:failed
set "BUILD_EXIT=%ERRORLEVEL%"
if "%BUILD_EXIT%"=="0" set "BUILD_EXIT=1"
echo.
echo FIRE-TV-BUILD FEHLGESCHLAGEN. Fehlercode: %BUILD_EXIT%
popd
exit /b %BUILD_EXIT%
