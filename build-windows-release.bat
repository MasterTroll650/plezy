@echo off
setlocal EnableExtensions

set "REPO_DIR=%~dp0"
set "FLUTTER_SDK=C:\Users\0x539\development\flutter"
set "FLUTTER_CMD=%FLUTTER_SDK%\bin\flutter.bat"
set "LOCAL_JDK=C:\Users\0x539\Documents\Codex\2026-09-15\ist\work\jdk17\jdk-17.0.20.1+1"
set "RELEASE_EXE=%REPO_DIR%build\windows\x64\runner\Release\plezy.exe"
set "PATCHED_ENGINE_DLL=%FLUTTER_SDK%\bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll"
set "PATCHED_ENGINE_SHA256=1F9FCFA3003B64AF53154FB3FFE4D1B60D5462DFAACD78B3B2B2EBD5B75DE18E"

if not exist "%FLUTTER_CMD%" (
  echo FEHLER: Flutter wurde nicht gefunden:
  echo %FLUTTER_CMD%
  pause
  exit /b 1
)

if not defined JAVA_HOME if exist "%LOCAL_JDK%\bin\java.exe" set "JAVA_HOME=%LOCAL_JDK%"
if defined JAVA_HOME set "PATH=%JAVA_HOME%\bin;%PATH%"
set "PATH=%FLUTTER_SDK%\bin;%PATH%"

pushd "%REPO_DIR%" || (
  echo FEHLER: Plezy-Verzeichnis konnte nicht geoeffnet werden.
  pause
  exit /b 1
)

echo.
echo [1/4] Flutter Windows-Artefakte pruefen...
if not exist "%PATCHED_ENGINE_DLL%" (
  echo Windows-Engine fehlt. Flutter-Precache wird gestartet...
  call "%FLUTTER_CMD%" precache --windows
  if errorlevel 1 goto :failed
) else (
  echo Windows-Engine ist vorhanden. Precache wird uebersprungen.
)

echo.
echo [2/4] Plezy-DComp-Engine pruefen...
powershell.exe -NoProfile -Command "$path = $env:PATCHED_ENGINE_DLL; if ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $env:PATCHED_ENGINE_SHA256)) { exit 0 }; exit 1"
if errorlevel 1 (
  echo Gepatchte DComp-Engine fehlt oder ist nicht aktuell. Installation wird gestartet...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO_DIR%windows\tool\install-patched-engine.ps1"
  if errorlevel 1 goto :failed
) else (
  echo Gepatchte DComp-Engine ist bereits installiert. Schritt wird uebersprungen.
)

echo.
echo [3/4] Dart-Abhaengigkeiten laden...
call "%FLUTTER_CMD%" pub get
if errorlevel 1 goto :failed

echo.
echo [4/4] Windows-Release bauen...
call "%FLUTTER_CMD%" build windows --release
if errorlevel 1 goto :failed

echo.
echo RELEASE ERFOLGREICH GEBAUT:
echo %RELEASE_EXE%
popd
exit /b 0

:failed
set "BUILD_EXIT=%ERRORLEVEL%"
if "%BUILD_EXIT%"=="0" set "BUILD_EXIT=1"
echo.
echo RELEASE-BUILD FEHLGESCHLAGEN. Fehlercode: %BUILD_EXIT%
popd
exit /b %BUILD_EXIT%
