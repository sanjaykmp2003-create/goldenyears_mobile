# One-time setup for Windows: generates android/ios/web/windows platform folders around the Dart code,
# configures network permissions, and installs dependencies.
Write-Host "Setting up unicare_mobile Flutter project..." -ForegroundColor Cyan

# 1. Create platform folders
flutter create . --org com.goldenyears --project-name unicare_mobile --platforms=android,ios,web,windows

# 2. Clean default test if present
if (Test-Path "test\widget_test.dart") {
    Remove-Item "test\widget_test.dart" -Force -ErrorAction SilentlyContinue
}

# 3. Add Android permissions and allow cleartext HTTP (for local dev server)
$manifest = "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifest) {
    $content = Get-Content $manifest -Raw
    if ($content -notmatch "android.permission.INTERNET") {
        $content = $content -replace '<application', "<uses-permission android:name=`"android.permission.INTERNET`"/>`r`n    <application"
    }
    if ($content -notmatch "usesCleartextTraffic") {
        $content = $content -replace '<application', '<application android:usesCleartextTraffic="true"'
    }
    Set-Content -Path $manifest -Value $content -NoNewline
    Write-Host "Updated AndroidManifest.xml with INTERNET and cleartext permissions." -ForegroundColor Green
}

# 4. Get Flutter packages
flutter pub get

Write-Host "`nSetup complete! You can run the app in:" -ForegroundColor Green
Write-Host "  DEV (Localhost):" -ForegroundColor Cyan
Write-Host "    flutter run -d chrome --dart-define=API_URL=DEV" -ForegroundColor Yellow
Write-Host "  SIT (Cloud dev.3ii.co.in):" -ForegroundColor Cyan
Write-Host "    flutter run -d chrome --dart-define=API_URL=SIT" -ForegroundColor Yellow

