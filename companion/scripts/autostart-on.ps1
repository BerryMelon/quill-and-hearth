# Start the Quill & Hearth companion automatically (hidden) whenever you sign in to Windows.
# Usage: npm run autostart:on   (undo with npm run autostart:off)
$ErrorActionPreference = "Stop"
$companion = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$node = (Get-Command node -ErrorAction Stop).Source
$tsx = Join-Path $companion "node_modules\tsx\dist\cli.mjs"
if (-not (Test-Path $tsx)) { throw "tsx not found. Run 'npm install' in $companion first." }
if (-not (Test-Path (Join-Path $companion ".env"))) { Write-Warning "companion\.env is missing; the companion will not be able to write entries until you add your GEMINI_API_KEY." }

$startup = [Environment]::GetFolderPath("Startup")
$launcher = Join-Path $startup "QuillAndHearthCompanion.vbs"

# A tiny VBScript runs the companion with no console window (window style 0).
$vbs = @"
' Quill & Hearth companion autostart (created by companion\scripts\autostart-on.ps1)
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = "$companion"
shell.Run """$node"" ""$tsx"" src\index.ts", 0, False
"@
Set-Content -Path $launcher -Value $vbs -Encoding ASCII

# Start it right away too, so you don't have to sign out and back in.
Start-Process -FilePath "wscript.exe" -ArgumentList "`"$launcher`""

Write-Host "Autostart enabled: $launcher"
Write-Host "The companion is now running in the background. Logs: $companion\data\companion.log"
