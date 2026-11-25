#Requires -Version 5.1
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'NativeUpdate.psm1') -Force
$targetDir = Join-Path $env:APPDATA 'ts-browser-ext-cryovex\native-hosts\F'
$target = Join-Path $targetDir 'ts-browser-ext-cryovex.exe'
$statePath = Join-Path $PSScriptRoot 'installed.json'
$logPath = Join-Path $PSScriptRoot 'last-check.txt'
$lock = $null
$stage = $null
try {
    # File locking also serializes manual invocations with the scheduled task.
    $lock = [IO.File]::Open((Join-Path $PSScriptRoot 'update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Firefox native helper is not installed' }
    $registered = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Mozilla\NativeMessagingHosts\io.github.cryovex.ts_browser_ext.firefox').'(default)'
    $expectedManifest = Join-Path $targetDir 'io.github.cryovex.ts_browser_ext.firefox.json'
    if ($registered -ine $expectedManifest) { throw 'Unexpected native-host registration' }
    $nativeManifest = Get-Content -LiteralPath $registered -Raw | ConvertFrom-Json
    if ($nativeManifest.path -ine $target) { throw 'Unexpected registered executable' }
    if (Test-BrowserBusy) {
        Set-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) Waiting for Firefox to close."
        exit 0
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{'User-Agent'='Cryovex-Tailnet-Browser-Updater';'Accept'='application/vnd.github+json'}
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Cryovex/ts-browser-ext/releases/latest' -Headers $headers -TimeoutSec 30
    # Validate tag before using it in any path or URL.
    if ($release.draft -or $release.prerelease -or $release.tag_name -cnotmatch '^native-v\d+\.\d+\.\d+-go\d+\.\d+\.\d+-[a-f0-9]{12}$') { throw 'No stable native update is available' }
    $stage = Join-Path $targetDir ('update-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $metadataAsset = Get-ReleaseAsset $release 'native-update.json'
    if ($metadataAsset.size -gt 64KB) { throw 'Update manifest is too large' }
    $metadataPath = Join-Path $stage 'native-update.json'
    Invoke-WebRequest -UseBasicParsing -Uri $metadataAsset.browser_download_url -OutFile $metadataPath -TimeoutSec 60 | Out-Null
    Test-DownloadedAsset $metadataPath $metadataAsset | Out-Null
    $manifest = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    Test-ReleaseManifest $manifest $release
    if (Test-Path -LiteralPath $statePath) {
        $previous = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ([long]$release.id -lt [long]$previous.releaseId -or [version]$manifest.tailscaleVersion.Substring(1) -lt [version]$previous.tailscaleVersion.Substring(1)) {
            throw 'Refusing an older release'
        }
    }
    $installedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($installedHash -cne $manifest.sha256) {
        $binaryAsset = Get-ReleaseAsset $release $manifest.filename
        if ($binaryAsset.size -ne $manifest.size -or $binaryAsset.digest -cne ('sha256:' + $manifest.sha256)) { throw 'Manifest does not match release binary' }
        $candidate = Join-Path $stage $manifest.filename
        Invoke-WebRequest -UseBasicParsing -Uri $binaryAsset.browser_download_url -OutFile $candidate -TimeoutSec 300 | Out-Null
        Test-DownloadedAsset $candidate $binaryAsset | Out-Null
        if (-not (Install-VerifiedHelper $candidate $target $manifest)) {
            Set-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) Update deferred: Firefox started."
            exit 0
        }
    }
    $state = @{releaseId=$release.id; release=$manifest.release; tailscaleVersion=$manifest.tailscaleVersion; sha256=$manifest.sha256}
    $state | ConvertTo-Json | Set-Content -LiteralPath ($statePath + '.new') -Encoding UTF8
    if (Test-Path -LiteralPath $statePath) { [IO.File]::Replace(($statePath + '.new'), $statePath, [NullString]::Value) }
    else { [IO.File]::Move(($statePath + '.new'), $statePath) }
    Set-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) Current: $($manifest.tailscaleVersion), $($manifest.release)"
} catch {
    # Do not clobber another updater's log when the lock itself was unavailable.
    if ($null -ne $lock) { Set-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) Update failed: $($_.Exception.Message)" }
    Write-Error $_
    exit 1
} finally {
    if ($null -ne $stage -and (Test-Path -LiteralPath $stage)) {
        $fullStage = [IO.Path]::GetFullPath($stage)
        $prefix = [IO.Path]::GetFullPath($targetDir).TrimEnd('\') + '\update-'
        if ($fullStage.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fullStage -Recurse -Force }
    }
    if ($null -ne $lock) { $lock.Dispose() }
}
