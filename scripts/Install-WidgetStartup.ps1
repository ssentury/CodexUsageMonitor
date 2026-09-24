<# Register startup for the current Windows user only. Running again updates the same shortcut. #>
$ErrorActionPreference = 'Stop'
$startupDirectory = [Environment]::GetFolderPath('Startup')
$shell = New-Object -ComObject WScript.Shell
$shortcutPath = Join-Path $startupDirectory 'Codex Usage Monitor.lnk'
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'Ensure-Monitor.ps1') + '"'
$shortcut.WorkingDirectory = Split-Path -Parent $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = 'Codex Usage Monitor service and desktop cost widget'
$shortcut.Save()
Write-Output "Login startup registered: $shortcutPath"
