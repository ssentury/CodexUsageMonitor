<# Starts one native widget per desktop session without opening a browser. #>
$ErrorActionPreference = 'Stop'
$created = $false
$probe = New-Object Threading.Mutex($false, 'Local\CodexUsageMonitorWidget', [ref]$created)
$probe.Dispose()
if (-not $created) { return }
$widgetScript = Join-Path $PSScriptRoot 'Widget.ps1'
# Normalize duplicate Path/PATH variables inherited from some launchers.
$processPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable('PATH', $null, [EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable('Path', $processPath, [EnvironmentVariableTarget]::Process)
Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$widgetScript`"") `
    -WindowStyle Hidden
