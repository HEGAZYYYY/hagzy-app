# Hagzy Production Build Script
# Usage: .\build_prod.ps1 -ApiUrl "https://api.hagzy.app"
param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl
)

Write-Host "Building Hagzy customer web app pointing to $ApiUrl..."
flutter build web --release `
    --dart-define=HAGZY_API_URL=$ApiUrl

Write-Host ""
Write-Host "Customer build complete: build\web\"
Write-Host ""
Write-Host "Building Hagzy admin web app..."
flutter build web --release `
    --dart-define=HAGZY_API_URL=$ApiUrl `
    --dart-define=HAGZY_ADMIN_APP=true `
    --output=build/web-admin

Write-Host ""
Write-Host "Admin build complete: build\web-admin\"
Write-Host ""
Write-Host "Deploy build\web\ to your hosting provider (Firebase, Netlify, Vercel, etc.)"
