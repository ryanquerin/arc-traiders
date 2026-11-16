#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$OutFile,[Parameter(Mandatory=$true)][string]$StopFlag)
$ErrorActionPreference = 'Continue'
$encoding = [Text.UTF8Encoding]::new($false)
while (-not (Test-Path -LiteralPath $StopFlag)) {
    $now = (Get-Date).ToUniversalTime().ToString('o')
    try {
        $sockets = Get-NetTCPConnection -ErrorAction Stop | Where-Object { $_.State -in @('Established','SynSent','CloseWait') }
        $pids = @($sockets | Select-Object -ExpandProperty OwningProcess -Unique)
        $names = @{}
        foreach ($pidnum in $pids) {
            try {
                $p = Get-Process -Id $pidnum -ErrorAction Stop
                $names[[string]$pidnum] = $p.ProcessName
            } catch { $names[[string]$pidnum] = 'unknown' }
        }
        foreach ($sock in $sockets) {
            $rec = [ordered]@{
                timestamp_utc=$now
                event_type='socket_observed'
                protocol='tcp'
                process_id=[int]$sock.OwningProcess
                process_name=$names[[string]$sock.OwningProcess]
                local_address=$sock.LocalAddress
                local_port=[int]$sock.LocalPort
                remote_address=$sock.RemoteAddress
                remote_port=[int]$sock.RemotePort
                state=[string]$sock.State
            }
            [IO.File]::AppendAllText($OutFile, (($rec | ConvertTo-Json -Compress) + [Environment]::NewLine), $encoding)
        }
    } catch {
        $err = [ordered]@{timestamp_utc=$now;event_type='poll_error';message=$_.Exception.GetType().Name}
        [IO.File]::AppendAllText($OutFile, (($err | ConvertTo-Json -Compress)+[Environment]::NewLine),$encoding)
    }
    Start-Sleep -Milliseconds 750
}