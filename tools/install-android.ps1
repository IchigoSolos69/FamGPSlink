$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskTooling = Join-Path $taskRoot '.tooling'
New-Item -ItemType Directory -Force -Path $taskTooling | Out-Null
$taskJava = Join-Path $taskTooling 'java'
if (-not (Test-Path $taskJava)) {
    Invoke-WebRequest -Uri 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse' -OutFile (Join-Path $taskTooling 'jdk.zip')
    Expand-Archive -LiteralPath (Join-Path $taskTooling 'jdk.zip') -DestinationPath $taskJava
}
$env:JAVA_HOME = (Get-ChildItem -LiteralPath $taskJava -Directory | Select-Object -First 1).FullName
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$taskCli = Join-Path $taskTooling 'android-cli'
if (-not (Test-Path $taskCli)) {
    Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' -OutFile (Join-Path $taskTooling 'android-cli.zip')
    Expand-Archive -LiteralPath (Join-Path $taskTooling 'android-cli.zip') -DestinationPath $taskCli
}
$taskSdk = Join-Path $taskTooling 'android-sdk'
$taskManager = Join-Path $taskCli 'cmdline-tools/bin/sdkmanager.bat'
1..100 | ForEach-Object { 'y' } | & $taskManager "--sdk_root=$taskSdk" --licenses
& $taskManager "--sdk_root=$taskSdk" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'cmdline-tools;latest'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK installation failed.' }
& (Join-Path $taskRoot '.tooling/flutter/bin/flutter.bat') config --android-sdk $taskSdk --jdk-dir $env:JAVA_HOME
Write-Output "Android SDK: $taskSdk"
