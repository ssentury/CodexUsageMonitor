<# Remove only this application's current-user login shortcut. #>
$ErrorActionPreference = 'Stop'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Usage Monitor.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath
}
Write-Output 'Codex Usage Monitor login startup disabled. The running monitor is unchanged.'
