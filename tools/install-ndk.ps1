$ErrorActionPreference = 'Stop'
$taskSdkRoot = 'D:\FamGPSlink-tooling\android-sdk'
$taskVersion = '28.2.13676358'
$taskDestination = [IO.Path]::GetFullPath((Join-Path $taskSdkRoot "ndk\$taskVersion"))
if ($taskDestination -ne 'D:\FamGPSlink-tooling\android-sdk\ndk\28.2.13676358') { throw 'Unexpected NDK target' }
$taskJavaProcesses = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'java.exe' -and $_.CommandLine -match 'SdkManagerCli' -and $_.CommandLine -like '*ndk;28.2.13676358*' }
foreach ($taskJavaProcess in $taskJavaProcesses) { Stop-Process -Id $taskJavaProcess.ProcessId }
[xml]$taskRepository = (Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/repository2-3.xml').Content
$taskPackage = $taskRepository.DocumentElement.remotePackage | Where-Object { $_.path -eq "ndk;$taskVersion" }
$taskArchive = $taskPackage.archives.archive | Where-Object { $_.'host-os' -eq 'windows' } | Select-Object -First 1
$taskChecksum = $taskArchive.SelectSingleNode('complete/checksum').InnerText
if (-not $taskArchive.complete.url -or -not $taskChecksum) { throw 'NDK metadata not found' }
$taskZip = 'D:\FamGPSlink-tooling\ndk.zip'
Invoke-WebRequest -UseBasicParsing -Uri "https://dl.google.com/android/repository/$($taskArchive.complete.url)" -OutFile $taskZip
if ((Get-FileHash -LiteralPath $taskZip -Algorithm SHA1).Hash.ToLower() -ne $taskChecksum) { throw 'NDK checksum mismatch' }
$taskUnpack = 'D:\FamGPSlink-tooling\ndk-unpack'
Expand-Archive -LiteralPath $taskZip -DestinationPath $taskUnpack -Force
$taskExtracted = (Get-ChildItem -LiteralPath $taskUnpack -Directory | Select-Object -First 1).FullName
if (-not $taskExtracted.StartsWith('D:\FamGPSlink-tooling\ndk-unpack\') -or -not (Test-Path -LiteralPath (Join-Path $taskExtracted 'source.properties'))) { throw 'Unexpected NDK archive layout' }
if (Test-Path -LiteralPath $taskDestination) { Remove-Item -LiteralPath $taskDestination -Recurse -Force }
Move-Item -LiteralPath $taskExtracted -Destination $taskDestination
Remove-Item -LiteralPath $taskZip
Write-Output "Installed verified NDK $taskVersion at $taskDestination"
