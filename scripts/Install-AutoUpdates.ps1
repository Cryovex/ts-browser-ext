#Requires -Version 5.1
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$taskName = 'Cryovex Tailnet Browser Engine Update'
if ($Remove) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output 'Automatic updates disabled. The helper and login are unchanged.'
    exit 0
}
$target = Join-Path $env:APPDATA 'ts-browser-ext-cryovex\native-hosts\F\ts-browser-ext-cryovex.exe'
if (-not (Test-Path -LiteralPath $target)) { throw 'Install the Firefox native helper first.' }
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw 'This updater supports Windows x64.' }
$updateDir = Join-Path $env:APPDATA 'ts-browser-ext-cryovex\updater'
New-Item -ItemType Directory -Path $updateDir -Force | Out-Null
foreach ($name in @('Update-NativeHelper.ps1', 'NativeUpdate.psm1')) {
    $source = Join-Path $PSScriptRoot $name
    $destination = Join-Path $updateDir $name
    if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($destination)) { Copy-Item -LiteralPath $source -Destination $destination -Force }
}
$script = Join-Path $updateDir 'Update-NativeHelper.ps1'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$action = New-ScheduledTaskAction -Execute $powershell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script)
$daily = New-ScheduledTaskTrigger -Daily -At '12:00'
$login = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
# Retry regularly while logged in, so a closed browser does not have to wait a day.
$hourly = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 1)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($daily,$login,$hourly) -Principal $principal -Settings $settings -Description 'Updates only the Cryovex Firefox Tailscale helper while Firefox is closed.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output "Automatic engine updates enabled. Status: $updateDir\last-check.txt"
