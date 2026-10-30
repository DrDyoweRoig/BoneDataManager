# Builds both editions into dist\:
#   dist\BoneDataManager.apk, dist\BoneDataManager-windows.zip          — team build (built-in server, needs app\cloud_config.json)
#   dist\public\BoneDataManager.apk, dist\public\BoneDataManager-windows.zip — public build (no server; each team connects its own)
# Native tools print warnings on stderr; failures are detected by exit code below.
$env:Path += ';C:\src\flutter\bin'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$root = Split-Path $PSScriptRoot -Parent
Set-Location "$root\app"

function Zip-Windows([string]$target) {
  $stage = "$env:TEMP\bdm_dist\Bone Data Manager"
  Remove-Item -Recurse -Force "$env:TEMP\bdm_dist" -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $stage | Out-Null
  Copy-Item 'build\windows\x64\runner\Release\*' $stage -Recurse
  foreach ($d in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item "C:\Windows\System32\$d" $stage -ErrorAction SilentlyContinue
  }
  Compress-Archive -Path $stage -DestinationPath $target -Force
}

function Build([string]$out, [string[]]$extra) {
  New-Item -ItemType Directory -Force $out | Out-Null
  flutter build apk --release @extra
  if ($LASTEXITCODE -ne 0) { throw "apk build failed ($out)" }
  Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' "$out\BoneDataManager.apk" -Force
  flutter build windows @extra
  if ($LASTEXITCODE -ne 0) { throw "windows build failed ($out)" }
  Zip-Windows "$out\BoneDataManager-windows.zip"
}

Build "$root\dist\public" @()
Build "$root\dist" @('--dart-define-from-file=cloud_config.json')   # last, so build\windows holds the team build
"done"
