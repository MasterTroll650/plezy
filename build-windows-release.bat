@echo off
setlocal EnableExtensions
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
cd /d "%~dp0" || exit /b 1

if not defined PLEZY_FLUTTER_SDK set "PLEZY_FLUTTER_SDK=%USERPROFILE%\development\flutter"
set "PLEZY_FLUTTER=%PLEZY_FLUTTER_SDK%\bin\flutter.bat"
if exist "%PLEZY_FLUTTER%" (
    set "PATH=%PLEZY_FLUTTER_SDK%\bin;%PATH%"
) else (
    where flutter.bat >nul 2>&1 || (
        echo Flutter wurde nicht gefunden.
        goto :failed
    )
    set "PLEZY_FLUTTER=flutter.bat"
)

call "%PLEZY_FLUTTER%" pub get --enforce-lockfile --no-example || goto :failed
call "%PLEZY_FLUTTER%" precache --windows || goto :failed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "windows\tool\install-patched-engine.ps1" || goto :failed
where nuget.exe >nul 2>&1 || (
    if not exist ".dart_tool\plezy-build\nuget.exe" (
        powershell.exe -NoProfile -Command "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; $dir = '.dart_tool\plezy-build'; $null = New-Item -ItemType Directory -Path $dir -Force; $temp = Join-Path $dir 'nuget.download.exe'; Invoke-WebRequest -UseBasicParsing 'https://dist.nuget.org/win-x86-commandline/v6.14.0/nuget.exe' -OutFile $temp; $signature = Get-AuthenticodeSignature -LiteralPath $temp; if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation') { throw 'NuGet signature verification failed' }; Move-Item -LiteralPath $temp -Destination (Join-Path $dir 'nuget.exe')" || goto :failed
    )
    set "PATH=%CD%\.dart_tool\plezy-build;%PATH%"
)

call "%PLEZY_FLUTTER%" build windows --release --no-pub || goto :failed

powershell.exe -NoProfile -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$root = (Get-Location).Path; $release = Join-Path $root 'build\windows\x64\runner\Release';" ^
    "foreach ($file in @('plezy.exe','flutter_windows.dll','libmpv-2.dll','data\app.so')) { if (-not (Test-Path -LiteralPath (Join-Path $release $file) -PathType Leaf)) { throw ('Builddatei fehlt: ' + $file) } };" ^
    "$name = 'Plezy-Windows-x64-' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff');" ^
    "$folder = Join-Path $root $name; $stage = Join-Path $root ('.plezy-package-' + [guid]::NewGuid().ToString('N'));" ^
    "$stagedZip = $stage + '.zip';" ^
    "try {" ^
    "    Compress-Archive -Path (Join-Path $release '*') -DestinationPath $stagedZip;" ^
    "    Expand-Archive -LiteralPath $stagedZip -DestinationPath $stage;" ^
    "    if (-not (Test-Path -LiteralPath (Join-Path $stage 'plezy.exe') -PathType Leaf)) { throw 'plezy.exe fehlt im Archiv.' };" ^
    "    Move-Item -LiteralPath $stagedZip -Destination (Join-Path $stage ($name + '.zip'));" ^
    "    [IO.Directory]::Move($stage, $folder);" ^
    "    Write-Host ('ZIP: ' + (Join-Path $folder ($name + '.zip')));" ^
    "    Write-Host ('Start: ' + (Join-Path $folder 'plezy.exe'));" ^
    "} finally {" ^
    "    if (Test-Path -LiteralPath $stagedZip) { Remove-Item -LiteralPath $stagedZip -Force };" ^
    "    if ((Test-Path -LiteralPath $stage) -and [IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $stage).Path) -eq $root) { Remove-Item -LiteralPath $stage -Recurse -Force }" ^
    "}" || goto :failed

exit /b 0

:failed
echo.
echo Der Windows-Build oder das Verpacken ist fehlgeschlagen.
exit /b 1
