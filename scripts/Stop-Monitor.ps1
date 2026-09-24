<# Stops only the verified Codex Usage Monitor process recorded in its PID file. #>
$ErrorActionPreference = 'Stop'
$stateRoot = if ($env:CODEX_USAGE_MONITOR_STATE_ROOT) {
    $env:CODEX_USAGE_MONITOR_STATE_ROOT
}
else {
    Join-Path $env:USERPROFILE '.codex-usage-monitor'
}
$pidPath = Join-Path $stateRoot 'service.pid'

if (-not (Test-Path -LiteralPath $pidPath)) {
    Write-Output 'Codex Usage Monitor is not running.'
    exit 0
}

$servicePid = [int](Get-Content -LiteralPath $pidPath -Encoding UTF8 -Raw)
$health = Invoke-RestMethod -Uri 'http://127.0.0.1:47831/api/health' -TimeoutSec 2
if ($health.app -ne 'codex-usage-monitor') {
    throw 'Port 47831 is not owned by Codex Usage Monitor; no process was stopped.'
}
Stop-Process -Id $servicePid -ErrorAction Stop
Write-Output "Stopped Codex Usage Monitor process $servicePid."
