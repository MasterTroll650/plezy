param(
    [Parameter(Mandatory)]
    [ValidateSet('Windows', 'FireTV', 'AndroidTV', 'InstallFireTV', 'StartAndroidTV', 'MirrorFireTV')]
    [string]$Action,
    [Parameter(Position = 0)]
    [string]$Device,
    [Parameter(Position = 1)]
    [string]$ReleaseDir
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $repo

function Invoke-ReleaseTool([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$(Split-Path -Leaf $Tool) ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
    }
}

function Get-Flutter {
    $sdk = $env:PLEZY_FLUTTER_SDK
    if (-not $sdk) { $sdk = Join-Path $env:USERPROFILE 'development\flutter' }
    $bin = Join-Path $sdk 'bin'
    $flutter = Join-Path $bin 'flutter.bat'
    if (Test-Path -LiteralPath $flutter -PathType Leaf) {
        $env:Path = "$bin;$env:Path"
        return $flutter
    }
    $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw 'Flutter fehlt. Setze PLEZY_FLUTTER_SDK oder fuege Flutter zum PATH hinzu.'
}

function Get-AndroidSdk {
    foreach ($sdk in @($env:PLEZY_ANDROID_SDK, $env:ANDROID_SDK_ROOT, $env:ANDROID_HOME,
            (Join-Path $env:USERPROFILE 'development\android-sdk'), (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if ($sdk -and (Test-Path -LiteralPath (Join-Path $sdk 'platform-tools\adb.exe') -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $sdk).Path
        }
    }
    throw 'Android SDK mit ADB fehlt. Setze PLEZY_ANDROID_SDK.'
}

function Get-AndroidBuildTool([string]$Sdk, [string]$Name) {
    $versions = Get-ChildItem -LiteralPath (Join-Path $Sdk 'build-tools') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending
    foreach ($version in $versions) {
        $tool = Join-Path $version.FullName $Name
        if (Test-Path -LiteralPath $tool -PathType Leaf) { return $tool }
    }
    throw "Android Build Tool fehlt: $Name"
}

function New-ReleaseFolder([string]$Platform, [string[]]$Files, [string]$WindowsBundle) {
    $name = 'Plezy-' + $Platform + '-' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff')
    $destination = Join-Path $repo $name
    $stage = Join-Path $repo ('.plezy-package-' + [guid]::NewGuid().ToString('N'))
    $temporaryZip = $stage + '.zip'
    try {
        if ($WindowsBundle) {
            Compress-Archive -Path (Join-Path $WindowsBundle '*') -DestinationPath $temporaryZip
            Expand-Archive -LiteralPath $temporaryZip -DestinationPath $stage
            if (-not (Test-Path -LiteralPath (Join-Path $stage 'plezy.exe') -PathType Leaf)) {
                throw 'plezy.exe fehlt im Archiv.'
            }
            Move-Item -LiteralPath $temporaryZip -Destination (Join-Path $stage ($name + '.zip'))
        } else {
            $null = New-Item -ItemType Directory -Path $stage
            Copy-Item -LiteralPath $Files -Destination $stage
        }
        [IO.Directory]::Move($stage, $destination)
        return $destination
    } finally {
        if (Test-Path -LiteralPath $temporaryZip -PathType Leaf) { Remove-Item -LiteralPath $temporaryZip -Force }
        if ((Test-Path -LiteralPath $stage -PathType Container) -and
            [IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $stage).Path) -eq $repo) {
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
    }
}

function Initialize-NuGet {
    if (Get-Command nuget.exe -ErrorAction SilentlyContinue) { return }
    $directory = Join-Path $repo '.dart_tool\plezy-build'
    $nuget = Join-Path $directory 'nuget.exe'
    if (-not (Test-Path -LiteralPath $nuget -PathType Leaf)) {
        $ProgressPreference = 'SilentlyContinue'
        $null = New-Item -ItemType Directory -Path $directory -Force
        $download = Join-Path $directory 'nuget.download.exe'
        Invoke-WebRequest -UseBasicParsing 'https://dist.nuget.org/win-x86-commandline/v6.14.0/nuget.exe' -OutFile $download
        $signature = Get-AuthenticodeSignature -LiteralPath $download
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation') {
            throw 'Die NuGet-Signatur konnte nicht verifiziert werden.'
        }
        Move-Item -LiteralPath $download -Destination $nuget
    }
    $env:Path = "$directory;$env:Path"
}

function Build-WindowsRelease {
    $flutter = Get-Flutter
    Invoke-ReleaseTool $flutter @('pub', 'get', '--enforce-lockfile', '--no-example')
    Invoke-ReleaseTool $flutter @('precache', '--windows')
    Invoke-ReleaseTool powershell.exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'windows\tool\install-patched-engine.ps1')
    Initialize-NuGet
    Invoke-ReleaseTool $flutter @('build', 'windows', '--release', '--no-pub')
    $bundle = Join-Path $repo 'build\windows\x64\runner\Release'
    foreach ($file in @('plezy.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'data\app.so')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $file) -PathType Leaf)) { throw "Builddatei fehlt: $file" }
    }
    $outputDir = New-ReleaseFolder -Platform 'Windows-x64' -WindowsBundle $bundle
    Write-Host "ZIP: $(Join-Path $outputDir ((Split-Path -Leaf $outputDir) + '.zip'))"
    Write-Host "Start: $(Join-Path $outputDir 'plezy.exe')"
}

function Get-AndroidJavaHome {
    $localFile = Join-Path $repo '.plezy-java-home'
    $localJdk = if (Test-Path -LiteralPath $localFile -PathType Leaf) {
        (Get-Content -LiteralPath $localFile -Raw).Trim()
    }
    $javaDir = Join-Path $env:ProgramFiles 'Java'
    $installedJdks = Get-ChildItem -LiteralPath $javaDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^jdk-21(?:[.-]|$)' } | Select-Object -ExpandProperty FullName
    $studioJdk = Join-Path $env:ProgramFiles 'Android/Android Studio/jbr'
    foreach ($jdk in @($env:PLEZY_JAVA_HOME, $localJdk, $env:JAVA_HOME, $studioJdk) + $installedJdks) {
        if (-not $jdk -or -not (Test-Path -LiteralPath (Join-Path $jdk 'bin/java.exe') -PathType Leaf)) { continue }
        $release = Join-Path $jdk 'release'
        if (-not (Test-Path -LiteralPath $release -PathType Leaf)) { continue }
        $version = Select-String -LiteralPath $release '^JAVA_VERSION="(\d+)' | Select-Object -First 1
        if ($version -and [int]$version.Matches[0].Groups[1].Value -in 21..26) {
            return (Resolve-Path -LiteralPath $jdk).Path
        }
    }
    throw 'Java fuer Gradle fehlt. Setze PLEZY_JAVA_HOME auf ein JDK 21.'
}

function Build-AndroidRelease([bool]$FireTV) {
    $flutter = Get-Flutter
    $sdk = Get-AndroidSdk
    $signer = Get-AndroidBuildTool $sdk 'apksigner.bat'
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    $env:Path = "$(Join-Path $sdk 'platform-tools');$env:Path"
    $env:JAVA_HOME = Get-AndroidJavaHome
    $env:PLEZY_LOCAL_ANDROID_BUILD = '1'
    $env:Path = "$(Join-Path $env:JAVA_HOME 'bin');$env:Path"

    if ($FireTV) {
        $env:AMAZON = '1'
        $target = 'android-arm,android-arm64'
        $platform = 'FireTV'
        $abis = @('armeabi-v7a', 'arm64-v8a')
    } else {
        Remove-Item Env:AMAZON -ErrorAction SilentlyContinue
        $target = 'android-x64'
        $platform = 'AndroidTV-x64'
        $abis = @('x86_64')
    }
    Invoke-ReleaseTool $flutter @('pub', 'get', '--enforce-lockfile', '--no-example')
    Invoke-ReleaseTool $flutter @('build', 'apk', '--release', '--no-pub', '--split-per-abi', '--target-platform', $target)

    $apks = foreach ($abi in $abis) {
        $apk = Join-Path $repo "build\app\outputs\flutter-apk\app-$abi-release.apk"
        if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw "APK fehlt: $apk" }
        Invoke-ReleaseTool $signer @('verify', $apk) | Out-Host
        $apk
    }
    $outputDir = New-ReleaseFolder -Platform $platform -Files $apks
    foreach ($apk in $apks) { Write-Host "APK: $(Join-Path $outputDir (Split-Path -Leaf $apk))" }
    if (-not $FireTV) {
        $adb = Join-Path $sdk 'platform-tools\adb.exe'
        Write-Host "Emulator: ""$adb"" -s emulator-5554 install -r ""$(Join-Path $outputDir 'app-x86_64-release.apk')"""
    }
}

function Get-FireTVSerial {
    $serial = $Device
    if (-not $serial) { $serial = $env:PLEZY_FIRETV_SERIAL }
    $localConfig = Join-Path $repo '.plezy-firetv-serial'
    if (-not $serial -and (Test-Path -LiteralPath $localConfig -PathType Leaf)) {
        $serial = (Get-Content -LiteralPath $localConfig -Raw).Trim()
    }
    if (-not $serial -or $serial -notmatch '^[a-zA-Z0-9_.:\[\]-]+$' -or $serial.StartsWith('-')) {
        throw 'Fire-TV-Adresse fehlt oder ist ungueltig. Als erstes Argument, PLEZY_FIRETV_SERIAL oder in .plezy-firetv-serial angeben.'
    }
    return $serial
}

function Connect-FireTV([string]$Adb, [string]$Serial) {
    if ($Serial.Contains(':')) { Invoke-ReleaseTool $Adb @('connect', $Serial) }
    $state = & $Adb -s $Serial get-state
    if ($LASTEXITCODE -ne 0 -or "$state".Trim() -ne 'device') {
        throw "Fire TV $Serial ist nicht per ADB verbunden. Pruefe ADB-Debugging und die Freigabe am Fernseher."
    }
}

function Install-FireTVRelease {
    $folder = $ReleaseDir
    if (-not $folder) {
        $latest = Get-ChildItem -LiteralPath $repo -Directory -Filter 'Plezy-FireTV-*' |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) { $folder = $latest.FullName }
    }
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw 'Kein Fire-TV-Release gefunden. Fuehre zuerst build-firetv-release.bat aus.'
    }
    $sdk = Get-AndroidSdk
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    $aapt = Get-AndroidBuildTool $sdk 'aapt2.exe'
    $serial = Get-FireTVSerial
    Connect-FireTV $adb $serial
    $abiList = & $adb -s $serial shell getprop ro.product.cpu.abilist
    if ($LASTEXITCODE -ne 0) { throw 'Die Fire-TV-Architektur konnte nicht ermittelt werden.' }
    $abis = "$abiList".Trim() -split ','
    $abi = if ($abis -contains 'arm64-v8a') { 'arm64-v8a' } elseif ($abis -contains 'armeabi-v7a' -or $abis -contains 'armeabi') {
        'armeabi-v7a'
    } else { throw "Unbekannte Fire-TV-Architektur: $abiList" }
    $apk = Join-Path $folder "app-$abi-release.apk"
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw "APK fehlt: $apk" }

    $badging = & $aapt dump badging $apk
    $manifest = $badging | Select-String "^package: name='([A-Za-z][A-Za-z0-9_.]*)'" | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $manifest) { throw "Paket-ID konnte nicht gelesen werden: $apk" }
    $package = $manifest.Matches[0].Groups[1].Value
    Write-Host "Installiere: $apk"
    Invoke-ReleaseTool $adb @('-s', $serial, 'install', '-r', $apk)
    Invoke-ReleaseTool $adb @('-s', $serial, 'shell', 'am', 'start', '-n', "$package/com.edde746.plezy.MainActivity")
}

function Start-AndroidTV {
    $sdk = Get-AndroidSdk
    $emulator = Join-Path $sdk 'emulator\emulator.exe'
    if (-not (Test-Path -LiteralPath $emulator -PathType Leaf)) { throw "Android Emulator fehlt: $emulator" }
    $avd = $env:PLEZY_ANDROID_AVD
    if (-not $avd) { $avd = 'Pleazy_TV_API_36' }
    if ($avd -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'Ungueltiger AVD-Name.' }
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    Start-Process -FilePath $emulator -ArgumentList @('-avd', $avd, '-no-snapshot', '-gpu', 'swiftshader_indirect', '-netdelay', 'none', '-netspeed', 'full')
}

function Mirror-FireTV {
    $adb = Join-Path (Get-AndroidSdk) 'platform-tools\adb.exe'
    $scrcpy = $env:PLEZY_SCRCPY
    if (-not $scrcpy) { $scrcpy = (Get-Command scrcpy.exe -ErrorAction SilentlyContinue).Source }
    if (-not $scrcpy) {
        $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        $scrcpy = Get-ChildItem -LiteralPath $winget -Directory -Filter 'Genymobile.scrcpy_*' -ErrorAction SilentlyContinue |
            Get-ChildItem -Recurse -File -Filter 'scrcpy.exe' |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $scrcpy -or -not (Test-Path -LiteralPath $scrcpy -PathType Leaf)) {
        throw 'scrcpy fehlt. Setze PLEZY_SCRCPY oder fuege scrcpy zum PATH hinzu.'
    }
    $serial = Get-FireTVSerial
    $env:ADB = $adb
    Connect-FireTV $adb $serial
    Invoke-ReleaseTool $scrcpy @('--serial', $serial, '--max-size', '1280', '--max-fps', '60',
        '--video-bit-rate', '12M', '--video-buffer', '0')
}

try {
    switch ($Action) {
        'Windows' { Build-WindowsRelease }
        'FireTV' { Build-AndroidRelease $true }
        'AndroidTV' { Build-AndroidRelease $false }
        'InstallFireTV' { Install-FireTVRelease }
        'StartAndroidTV' { Start-AndroidTV }
        'MirrorFireTV' { Mirror-FireTV }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
