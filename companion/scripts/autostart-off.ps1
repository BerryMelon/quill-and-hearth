# Stop starting the Quill & Hearth companion with Windows, and stop the running instance.
# Usage: npm run autostart:off
$launcher = Join-Path ([Environment]::GetFolderPath("Startup")) "QuillAndHearthCompanion.vbs"
if (Test-Path $launcher) {
    Remove-Item $launcher
    Write-Host "Autostart disabled."
} else {
    Write-Host "Autostart was not enabled."
}
Push-Location (Join-Path $PSScriptRoot "..")
try { npx tsx src/index.ts --stop } finally { Pop-Location }
