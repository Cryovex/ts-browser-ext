param([switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\scripts\NativeUpdate.psm1') -Force
function Assert-Throws([scriptblock]$Action) {
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw 'Expected operation to fail' }
}
function Assert-Equal($Actual, $Expected) {
    if ($Actual -cne $Expected) { throw "Expected '$Expected', got '$Actual'" }
}
$commit = 'a' * 40
$tag = 'native-v1.104.7-go1.27.4-' + $commit.Substring(0,12)
$manifest = [pscustomobject]@{schemaVersion=1;platform='windows-amd64';filename='ts-browser-ext-cryovex.exe';release=$tag;sourceCommit=$commit;sha256=('b'*64);size=100;tailscaleVersion='v1.104.7';goVersion='go1.27.4'}
$asset = [pscustomobject]@{name='ts-browser-ext-cryovex.exe';browser_download_url="https://github.com/Cryovex/ts-browser-ext/releases/download/$tag/ts-browser-ext-cryovex.exe";digest=('sha256:'+('b'*64));size=100}
$release = [pscustomobject]@{draft=$false;prerelease=$false;tag_name=$tag;assets=@($asset)}
Test-ReleaseManifest $manifest $release
Assert-Equal (Get-ReleaseAsset $release 'ts-browser-ext-cryovex.exe').name 'ts-browser-ext-cryovex.exe'
$release.prerelease=$true
Assert-Throws { Test-ReleaseManifest $manifest $release }
$release.prerelease=$false
$manifest.tailscaleVersion='v1.105.0'
Assert-Throws { Test-ReleaseManifest $manifest $release }
$manifest.tailscaleVersion='v1.104.7'
$manifest.release='native-v1.104.6-go1.27.4-aaaaaaaaaaaa'
Assert-Throws { Test-ReleaseManifest $manifest $release }
$manifest.release=$tag
$manifest.size=151MB
Assert-Throws { Test-ReleaseManifest $manifest $release }
$manifest.size=100
$asset.browser_download_url='https://example.org/malicious.exe'
Assert-Throws { Get-ReleaseAsset $release 'ts-browser-ext-cryovex.exe' }
$asset.browser_download_url="https://github.com/Cryovex/ts-browser-ext/releases/download/$tag/ts-browser-ext-cryovex.exe"
$asset.digest=$null
Assert-Throws { Get-ReleaseAsset $release 'ts-browser-ext-cryovex.exe' }
$asset.digest='sha256:'+('b'*64)
$release.assets=@($asset,$asset)
Assert-Throws { Get-ReleaseAsset $release 'ts-browser-ext-cryovex.exe' }
$release.assets=@($asset)
$build=[pscustomobject]@{tailscaleVersion='v1.104.7';release=$tag;sourceCommit=$commit;goVersion='go1.27.4'}
Test-HelperBuildInfo $build $manifest
$build.tailscaleVersion='v1.98.2'
Assert-Throws { Test-HelperBuildInfo $build $manifest }
$build.tailscaleVersion='v1.104.7'
Write-Output 'PASS: stable-release, manifest, URL, duplicate asset, digest and build-identity validation.'
if ($ReadOnly) { return }

$testDir = Join-Path ([IO.Path]::GetTempPath()) ('cryovex-updater-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
try {
    $target=Join-Path $testDir 'helper.exe'
    $candidate=Join-Path $testDir 'candidate.exe'
    [IO.File]::WriteAllText($target,'old helper')
    [IO.File]::WriteAllText($candidate,'new helper')
    $manifest.sha256=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    $asset.digest='sha256:'+$manifest.sha256
    $asset.size=(Get-Item -LiteralPath $candidate).Length
    Assert-Equal (Test-DownloadedAsset $candidate $asset) $manifest.sha256
    [IO.File]::AppendAllText($candidate,'corrupted')
    Assert-Throws { Test-DownloadedAsset $candidate $asset }
    Assert-Throws { Install-VerifiedHelper $candidate $target $manifest }
    Assert-Equal ([IO.File]::ReadAllText($target)) 'old helper'
    [IO.File]::WriteAllText($candidate,'new helper')
    # Exercise the real atomic replacement with version/process probes stubbed.
    $module=Get-Module NativeUpdate
    & $module {
        param($Expected)
        $script:fakeBuild=$Expected
        $script:busy=$true
        $script:postFailure=$false
        function script:Test-BrowserBusy { return $script:busy }
        function script:Get-HelperBuildInfo {
            param($Path)
            if ($script:postFailure -and $Path.EndsWith('helper.exe')) { throw 'simulated post-install failure' }
            return $script:fakeBuild
        }
    } $build
    Assert-Equal (Install-VerifiedHelper $candidate $target $manifest) $false
    Assert-Equal ([IO.File]::ReadAllText($target)) 'old helper'
    & $module { $script:busy=$false; $script:postFailure=$true }
    Assert-Throws { Install-VerifiedHelper $candidate $target $manifest }
    Assert-Equal ([IO.File]::ReadAllText($target)) 'old helper'
    [IO.File]::WriteAllText($candidate,'new helper')
    & $module { $script:postFailure=$false }
    Assert-Equal (Install-VerifiedHelper $candidate $target $manifest) $true
    Assert-Equal ([IO.File]::ReadAllText($target)) 'new helper'
    Assert-Equal ([IO.File]::ReadAllText($target+'.previous')) 'old helper'
    Write-Output 'PASS: corrupt download rejected, busy-browser deferral, atomic installation and rollback.'
} finally {
    $resolved=[IO.Path]::GetFullPath($testDir)
    $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\cryovex-updater-test-'
    if ($resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Force -Recurse }
}
