# Clears the update dismissal date so the update popup shows again on next launch.
# Usage: .\scripts\reset_update_dismiss.ps1

$prefsPath = "$env:APPDATA\com.seshu\m_storage\shared_preferences.json"

if (-not (Test-Path $prefsPath)) {
    Write-Host "shared_preferences.json not found — app hasn't been run yet." -ForegroundColor Yellow
    exit 0
}

$json = Get-Content $prefsPath -Raw | ConvertFrom-Json
if ($json.PSObject.Properties.Name -contains "flutter.update_dismissed_date") {
    $json.PSObject.Properties.Remove("flutter.update_dismissed_date")
    $json | ConvertTo-Json -Compress | Set-Content $prefsPath
    Write-Host "Done — update dismissal cleared. Run the app to see the popup again." -ForegroundColor Green
} else {
    Write-Host "Nothing to clear — dismissal date was not set." -ForegroundColor Cyan
}
