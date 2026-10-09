param([Parameter(Mandatory=$true)][string]$Binary)
$ErrorActionPreference = 'Stop'
$binaryPath = (Resolve-Path -LiteralPath $Binary).Path
$start = [Diagnostics.ProcessStartInfo]::new($binaryPath, 'smoke-test')
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.WindowStyle = 'Hidden'
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$nativeProcess = [Diagnostics.Process]::Start($start)
$stderrTask = $nativeProcess.StandardError.ReadToEndAsync()
function Read-NativeReply {
    $header = [byte[]]::new(4)
    $nativeProcess.StandardOutput.BaseStream.ReadExactly($header)
    $length = [BitConverter]::ToUInt32($header,0)
    if ($length -gt 1048576) { throw 'Invalid native message length' }
    $body = [byte[]]::new($length)
    $nativeProcess.StandardOutput.BaseStream.ReadExactly($body)
    return ([Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json)
}
try {
    $hello = Read-NativeReply
    if (-not $hello.procRunning.port) { throw 'Missing native proxy port' }
    $body = [Text.Encoding]::UTF8.GetBytes('{"cmd":"get-status"}')
    $nativeProcess.StandardInput.BaseStream.Write([BitConverter]::GetBytes([uint32]$body.Length))
    $nativeProcess.StandardInput.BaseStream.Write($body)
    $nativeProcess.StandardInput.BaseStream.Flush()
    $status = Read-NativeReply
    if ($null -eq $status.status) { throw 'Missing framed status response' }
    $nativeProcess.StandardInput.Close()
    if (-not $nativeProcess.WaitForExit(10000)) { throw 'Native host failed to exit after browser input closed' }
    if ($nativeProcess.ExitCode -ne 0) { throw ('Native exit code: ' + $nativeProcess.ExitCode) }
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.Connect('127.0.0.1',[int]$hello.procRunning.port)
        throw 'Proxy listener remained open after exit'
    } catch [Net.Sockets.SocketException] {
        Write-Output 'PASS: framed handshake/status; stdin EOF exits cleanly; proxy port closes.'
    } finally { $client.Dispose() }
} finally {
    if (-not $nativeProcess.HasExited) { $nativeProcess.Kill(); $nativeProcess.WaitForExit() }
    $nativeProcess.Dispose()
}
