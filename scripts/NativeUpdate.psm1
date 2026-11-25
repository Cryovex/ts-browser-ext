Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ReleaseManifest {
    param($Manifest, $Release)
    if ($Release.draft -or $Release.prerelease -or $Release.tag_name -cnotmatch '^native-v\d+\.\d+\.\d+-go\d+\.\d+\.\d+-[a-f0-9]{12}$') {
        throw 'Not a stable native-helper release'
    }
    if ($Manifest.schemaVersion -ne 1 -or $Manifest.platform -cne 'windows-amd64' -or
        $Manifest.filename -cne 'ts-browser-ext-cryovex.exe' -or $Manifest.release -cne $Release.tag_name -or
        $Manifest.sourceCommit -cnotmatch '^[a-f0-9]{40}$' -or $Manifest.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $Manifest.size -lt 1 -or $Manifest.size -gt 150MB -or
        $Manifest.tailscaleVersion -cnotmatch '^v\d+\.\d+\.\d+$') { throw 'Invalid update manifest' }
    $version = [version]$Manifest.tailscaleVersion.Substring(1)
    if ($version.Minor % 2 -ne 0 -or $version -lt [version]'1.98.2') { throw 'Unstable or obsolete engine version' }
    $expectedTag = 'native-{0}-{1}-{2}' -f $Manifest.tailscaleVersion, $Manifest.goVersion, $Manifest.sourceCommit.Substring(0,12)
    if ($expectedTag -cne $Manifest.release) { throw 'Release identity mismatch' }
}

function Get-ReleaseAsset {
    param($Release, [string]$Name)
    $assets = @($Release.assets | Where-Object { $_.name -ceq $Name })
    if ($assets.Count -ne 1) { throw "Missing or duplicate asset: $Name" }
    $asset = $assets[0]
    $expectedURL = 'https://github.com/Cryovex/ts-browser-ext/releases/download/{0}/{1}' -f $Release.tag_name, $Name
    if ($asset.browser_download_url -cne $expectedURL -or $asset.digest -cnotmatch '^sha256:[a-f0-9]{64}$') {
        throw 'Unexpected release URL or missing GitHub SHA-256 digest'
    }
    return $asset
}

function Test-DownloadedAsset {
    param([string]$Path, $Asset)
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $Path).Length -ne $Asset.size -or ('sha256:' + $hash) -cne $Asset.digest) {
        throw 'Downloaded file does not match GitHub asset digest and size'
    }
    return $hash
}

function Get-HelperBuildInfo {
    param([string]$Path)
    $start = [Diagnostics.ProcessStartInfo]::new($Path, '--version-json')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = 'Hidden'
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { throw 'Helper version check timed out' }
        if ($process.ExitCode -ne 0) { throw 'Helper version check failed' }
        return ($stdout.GetAwaiter().GetResult() | ConvertFrom-Json)
    } finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

function Test-HelperBuildInfo {
    param($Build, $Manifest)
    if ($Build.tailscaleVersion -cne $Manifest.tailscaleVersion -or $Build.release -cne $Manifest.release -or
        $Build.sourceCommit -cne $Manifest.sourceCommit -or $Build.goVersion -cne $Manifest.goVersion) {
        throw 'Executable build information does not match release'
    }
}

function Test-BrowserBusy {
    # Also defer for other profiles/users: being conservative is preferable to
    # interrupting a connection. The replacement itself is atomic if a start races us.
    return $null -ne (Get-Process -Name firefox,ts-browser-ext-cryovex -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Install-VerifiedHelper {
    param([string]$Candidate, [string]$Target, $Manifest)
    if ((Get-FileHash -LiteralPath $Candidate -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Manifest.sha256) {
        throw 'Candidate SHA-256 mismatch'
    }
    Test-HelperBuildInfo (Get-HelperBuildInfo $Candidate) $Manifest
    if (Test-BrowserBusy) { return $false }
    $backup = $Target + '.previous'
    # Same-volume atomic replace: a locked destination leaves the old file intact.
    [IO.File]::Replace($Candidate, $Target, $backup, $true)
    try {
        Test-HelperBuildInfo (Get-HelperBuildInfo $Target) $Manifest
    } catch {
        [IO.File]::Replace($backup, $Target, [NullString]::Value, $true)
        throw
    }
    return $true
}

Export-ModuleMember -Function Test-ReleaseManifest,Get-ReleaseAsset,Test-DownloadedAsset,Test-HelperBuildInfo,Test-BrowserBusy,Install-VerifiedHelper
