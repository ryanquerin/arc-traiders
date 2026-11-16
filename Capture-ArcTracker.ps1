#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AppPath = '',
    [string]$ProcmonPath = '',
    [ValidatePattern('^[A-Za-z0-9_-]{1,48}$')]
    [string]$Scenario = 'xbox_login',
    [ValidateRange(64,4096)]
    [int]$MaxTraceMB = 512,
    [switch]$SkipProcmon
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '_' + $Scenario
$run = Join-Path $root ('runs\' + $runId)
$raw = Join-Path $run 'raw'
New-Item -ItemType Directory -Force -Path $raw | Out-Null
$markerFile = Join-Path $raw 'markers.jsonl'
$traceFile = Join-Path $raw 'windows.etl'
$procmonFile = Join-Path $raw 'procmon.pml'
$connections = Join-Path $raw 'connections.jsonl'
$stopFlag = Join-Path $raw 'stop-poll.flag'
$manifestFile = Join-Path $run 'manifest.json'
$startUTC = (Get-Date).ToUniversalTime().ToString('o')
$netshStarted = $false
$procmonStarted = $false
$pollProcess = $null
$errors = [System.Collections.Generic.List[string]]::new()

function Add-Marker([string]$name) {
    $event = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        event_type = 'marker'
        label = $name
    }
    $line = $event | ConvertTo-Json -Compress
    [System.IO.File]::AppendAllText($markerFile, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Host ('MARKED ' + $name + ' @ ' + $event.timestamp_utc) -ForegroundColor Cyan
}

function Save-Manifest([string]$status) {
    $binary = $null
    if ($AppPath -and (Test-Path -LiteralPath $AppPath -PathType Leaf)) {
        $file = Get-Item -LiteralPath $AppPath
        $sig = Get-AuthenticodeSignature -FilePath $AppPath
        $binary = [ordered]@{
            path = $file.FullName
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $AppPath -Algorithm SHA256).Hash
            signature_status = $sig.Status.ToString()
            signer_subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
        }
    }
    $files = @()
    Get-ChildItem -LiteralPath $raw -File -ErrorAction SilentlyContinue | ForEach-Object {
        $files += [ordered]@{ name=$_.Name; bytes=$_.Length }
    }
    $os = Get-CimInstance Win32_OperatingSystem
    $report = [ordered]@{
        run_id = $runId
        scenario = $Scenario
        status = $status
        started_utc = $startUTC
        updated_utc = (Get-Date).ToUniversalTime().ToString('o')
        system = [ordered]@{ caption=$os.Caption; version=$os.Version; build=$os.BuildNumber; timezone=(Get-TimeZone).Id }
        application = $binary
        collectors = [ordered]@{ netsh_started=$netshStarted; procmon_started=$procmonStarted; socket_poll_started=($null -ne $pollProcess) }
        errors = @($errors.ToArray())
        raw_files = @($files)
    }
    $report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $manifestFile -Encoding UTF8
}

try {
    $admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { throw 'Administrator PowerShell required for netsh trace. Reopen PowerShell as Administrator and try again.' }
    if ($AppPath -and -not (Test-Path -LiteralPath $AppPath -PathType Leaf)) { throw ('AppPath not found: ' + $AppPath) }
    if ($AppPath -and ($AppPath -match '(?i)setup|installer')) { throw 'AppPath appears to be an installer. Point to the installed ARC Tracker Link executable instead.' }
    if (-not $ProcmonPath -and -not $SkipProcmon) {
        foreach ($candidate in @('procmon64.exe','procmon.exe')) {
            $found = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($found) { $ProcmonPath = $found.Source; break }
        }
    }
    Write-Host "`nARC Tracker trace: $runId" -ForegroundColor Green
    Write-Host "Raw output (private): $raw"
    Write-Host 'The raw capture may contain sensitive account and network information. Do NOT upload the raw directory.' -ForegroundColor Yellow
    Save-Manifest 'starting'
    $netArgs = @('trace','start','scenario=InternetClient','capture=yes',('tracefile='+ $traceFile),'maxsize='+$MaxTraceMB,'filemode=circular','report=no','persistent=no')
    & netsh.exe @netArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw ('netsh trace start failed with exit code ' + $LASTEXITCODE + '. Stop any pre-existing netsh trace before retrying.') }
    $netshStarted = $true
    Add-Marker 'trace_started'

    if (-not $SkipProcmon -and $ProcmonPath) {
        if ((Get-Process -Name 'Procmon','Procmon64' -ErrorAction SilentlyContinue)) {
            $errors.Add('ProcMon already running; skipping automated ProcMon control to avoid modifying existing session.')
        } else {
            try {
                & $ProcmonPath /AcceptEula /Quiet /Minimized /BackingFile $procmonFile /WaitForIdle | Out-Null
                $procmonStarted = $true
                Write-Host 'ProcMon capture started.'
            } catch { $errors.Add('ProcMon unavailable: ' + $_.Exception.Message) }
        }
    } elseif (-not $SkipProcmon) {
        $errors.Add('ProcMon not found. Pass -ProcmonPath to add file/registry capture.')
    }

    $poller = Join-Path $root 'scripts\poll-connections.ps1'
    $shell = Join-Path $PSHOME 'powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $poller + '" -OutFile "' + $connections + '" -StopFlag "' + $stopFlag + '"'
    try {
        $pollProcess = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Write-Host ('Connection poller PID: ' + $pollProcess.Id)
    } catch { $errors.Add('Socket polling unavailable: ' + $_.Exception.Message) }

    Add-Marker 'ready_for_login'
    if ($AppPath) {
        Write-Host ('Starting installed application: ' + $AppPath)
        Start-Process -FilePath $AppPath | Out-Null
        Add-Marker 'app_launch_requested'
    } else {
        Write-Host 'Launch ARC Tracker Link yourself now. For auto-launch, re-run with -AppPath pointing to its installed executable.'
    }
    Write-Host "`nMark actions by typing a number and pressing Enter:"
    Write-Host '1 = xbox_link_clicked; 2 = xbox_prompt; 3 = login_success; 4 = login_error'
    Write-Host '5 = sync_started; 6 = sync_complete; 7 = app_closed; 0 = stop_capture'
    $labels = @{'1'='xbox_link_clicked';'2'='xbox_prompt';'3'='login_success';'4'='login_error';'5'='sync_started';'6'='sync_complete';'7'='app_closed'}
    while ($true) {
        $choice = Read-Host 'Event'
        if ($choice -eq '0') { Add-Marker 'stop_requested'; break }
        if ($labels.ContainsKey($choice)) { Add-Marker $labels[$choice] } else { Write-Host 'Use a listed number; labels intentionally exclude free-form credentials.' }
    }
} catch {
    $errors.Add($_.Exception.Message)
    Write-Host ('CAPTURE ERROR: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($pollProcess) {
        New-Item -ItemType File -Force -Path $stopFlag | Out-Null
        try { Wait-Process -Id $pollProcess.Id -Timeout 8 -ErrorAction SilentlyContinue } catch {}
        if (-not $pollProcess.HasExited) { Stop-Process -Id $pollProcess.Id -ErrorAction SilentlyContinue }
    }
    if ($procmonStarted) {
        try { & $ProcmonPath /Terminate /Quiet | Out-Null } catch { $errors.Add('ProcMon stop failed: ' + $_.Exception.Message) }
    }
    if ($netshStarted) {
        try {
            & netsh.exe trace stop | Out-Host
            if ($LASTEXITCODE -ne 0) { $errors.Add('netsh stop failed; check netsh trace status.') }
        } catch { $errors.Add('netsh stop failed: ' + $_.Exception.Message) }
    }
    if ($netshStarted) { Add-Marker 'trace_stopped' }
    Save-Manifest $(if ($errors.Count -gt 0) { 'partial' } else { 'completed' })
    Write-Host "`nRun saved: $run" -ForegroundColor Green
    Write-Host 'To build a sanitized timeline: python scripts\analyze-run.py "' $run '"'
    if ($errors.Count -gt 0) { Write-Host ('Warning: ' + ($errors -join '; ')) -ForegroundColor Yellow }
}