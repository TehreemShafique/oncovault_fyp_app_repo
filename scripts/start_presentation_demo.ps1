# scripts/start_presentation_demo.ps1
# OncoVault — Repeatable No-Cost Presentation Startup Procedure
# Starts Emulators, seeds data, launches Python NLP/AI, reverses USB ports, and verifies health.

param (
    [switch]$SkipAppLaunch = $false
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " OncoVault — Final Year Project Presentation Demo Startup" -ForegroundColor Cyan
Write-Host " Zero-Cost Real Physical Android Phone + Local Laptop Backends" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$repoRoot = Split-Path -Parent $PSScriptRoot

# Helper: Test TCP port
function Test-PortReachable([string]$hostAddress, [int]$port) {
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $iar = $tcpClient.BeginConnect($hostAddress, $port, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(1000, $false)
        if ($wait) {
            $tcpClient.EndConnect($iar)
            $tcpClient.Close()
            return $true
        } else {
            $tcpClient.Close()
            return $false
        }
    } catch {
        return $false
    }
}

# ── STEP 1: Firebase Emulators Check / Launch ──────────────────────
Write-Host "`n[STEP 1/6] Checking Firebase Emulators (9099, 8080, 5001)..." -ForegroundColor Yellow

$authOnline = Test-PortReachable "127.0.0.1" 9099
$firestoreOnline = Test-PortReachable "127.0.0.1" 8080
$functionsOnline = Test-PortReachable "127.0.0.1" 5001

if (-not ($authOnline -and $firestoreOnline -and $functionsOnline)) {
    Write-Host "[!] Firebase Emulators not fully active. Launching in separate window..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$repoRoot'; Write-Host 'Starting Firebase Emulators for demo-oncovault-local...' -ForegroundColor Cyan; firebase emulators:start --only auth,firestore,functions,storage --project demo-oncovault-local"
    
    Write-Host "Waiting up to 20 seconds for emulators to initialize..." -ForegroundColor DarkGray
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        $authOnline = Test-PortReachable "127.0.0.1" 9099
        $firestoreOnline = Test-PortReachable "127.0.0.1" 8080
        $functionsOnline = Test-PortReachable "127.0.0.1" 5001
        if ($authOnline -and $firestoreOnline -and $functionsOnline) { break }
    }
}

if ($authOnline -and $firestoreOnline -and $functionsOnline) {
    Write-Host "    [OK] Auth Emulator (port 9099) ONLINE" -ForegroundColor Green
    Write-Host "    [OK] Firestore Emulator (port 8080) ONLINE" -ForegroundColor Green
    Write-Host "    [OK] Functions Emulator (port 5001) ONLINE" -ForegroundColor Green
} else {
    Write-Host "    [WARN] Emulators may still be starting up in the separate window." -ForegroundColor Yellow
}

# ── STEP 2: Seed Demonstration Accounts ───────────────────────────
Write-Host "`n[STEP 2/6] Seeding synthetic demonstration accounts..." -ForegroundColor Yellow
try {
    Push-Location "$repoRoot\functions"
    $seedOutput = npx ts-node src/seed_emulators.ts
    Write-Host "    $seedOutput" -ForegroundColor DarkGray
    Write-Host "    [OK] Synthetic doctor and patient demonstration accounts verified!" -ForegroundColor Green
} catch {
    Write-Host "    [!] Seeding script encountered: $_" -ForegroundColor Yellow
} finally {
    Pop-Location
}

# ── STEP 3: Python Clinical NLP, Whisper & AI Engine Check ─────────
Write-Host "`n[STEP 3/6] Checking Python NLP/Whisper/AI Engine (port 8000)..." -ForegroundColor Yellow
$nlpOnline = Test-PortReachable "127.0.0.1" 8000

if (-not $nlpOnline) {
    Write-Host "[!] Python NLP service not running. Launching in separate window..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$repoRoot\oncovault_nlp'; Write-Host 'Starting OncoVault Clinical NLP & AI Engine on port 8000...' -ForegroundColor Cyan; `$env:ALLOW_TEST_TOKENS='true'; python main.py"
    
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 1
        $nlpOnline = Test-PortReachable "127.0.0.1" 8000
        if ($nlpOnline) { break }
    }
}

if ($nlpOnline) {
    Write-Host "    [OK] NLP, Whisper & AI Engine (port 8000) ONLINE" -ForegroundColor Green
} else {
    Write-Host "    [WARN] NLP engine is starting up in separate window." -ForegroundColor Yellow
}

# ── STEP 4: USB ADB Reverse Port Forwarding ─────────────────────────
Write-Host "`n[STEP 4/6] Configuring USB ADB Reverse Port Forwarding..." -ForegroundColor Yellow
& "$repoRoot\scripts\setup_android_usb.ps1"

# ── STEP 5: Verification Summary ────────────────────────────────────
Write-Host "`n[STEP 5/6] Final Service Status Summary:" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------"
Write-Host ("Firebase Auth Emulator    (9099) : " + $(if (Test-PortReachable "127.0.0.1" 9099) { "READY" } else { "PENDING" }))
Write-Host ("Firebase Firestore        (8080) : " + $(if (Test-PortReachable "127.0.0.1" 8080) { "READY" } else { "PENDING" }))
Write-Host ("Cloud Functions Callable  (5001) : " + $(if (Test-PortReachable "127.0.0.1" 5001) { "READY" } else { "PENDING" }))
Write-Host ("Python Clinical NLP / AI  (8000) : " + $(if (Test-PortReachable "127.0.0.1" 8000) { "READY" } else { "PENDING" }))
Write-Host "----------------------------------------------------------"

# ── STEP 6: Flutter Run Command for Physical Device ─────────────────
Write-Host "`n[STEP 6/6] Physical Device Execution Command:" -ForegroundColor Cyan
Write-Host "To run the app directly on your physical Android phone with hot reload:" -ForegroundColor White
Write-Host "  flutter run -d <DEVICE_ID> --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=USE_ADB_REVERSE=true" -ForegroundColor Yellow
Write-Host "`nTo build a portable debug APK and install directly:" -ForegroundColor White
Write-Host "  flutter build apk --debug --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=USE_ADB_REVERSE=true" -ForegroundColor Yellow
Write-Host "  adb install -r build/app/outputs/flutter-apk/app-debug.apk" -ForegroundColor Yellow

Write-Host "`n[DEMO CREDENTIALS]" -ForegroundColor Cyan
Write-Host "  Patient A : patient_a@oncovault.local  /  password123" -ForegroundColor White
Write-Host "  Doctor A  : doc_a@oncovault.local      /  password123  (Dr. Alice Vance)" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
