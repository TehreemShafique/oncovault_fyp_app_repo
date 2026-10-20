# scripts/setup_android_usb.ps1
# OncoVault — USB Reverse Port Forwarding for Physical Android FYP Demonstration
# Zero-cost local routing via USB cable.

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " OncoVault Physical Android USB ADB Reverse Setup" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Locate adb.exe
$adbPath = "adb"
if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
    $fallbackPaths = @(
        "D:\Android\Sdk\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "C:\Android\Sdk\platform-tools\adb.exe"
    )
    foreach ($path in $fallbackPaths) {
        if (Test-Path $path) {
            $adbPath = $path
            break
        }
    }
}

if (-not (Get-Command $adbPath -ErrorAction SilentlyContinue) -and -not (Test-Path $adbPath)) {
    Write-Host "[ERROR] adb.exe not found. Please ensure Android SDK platform-tools is installed." -ForegroundColor Red
    exit 1
}

Write-Host "[+] Using ADB binary: $adbPath" -ForegroundColor Green

# 2. Check connected physical devices
Write-Host "`n[+] Checking connected Android devices..." -ForegroundColor Yellow
$devices = & $adbPath devices -l
$attachedDevices = $devices | Where-Object { $_ -match "\bdevice\b" -and $_ -notmatch "List of devices attached" }

if (-not $attachedDevices) {
    Write-Host "[!] No physical Android device detected over USB." -ForegroundColor Yellow
    Write-Host "    Checklist:" -ForegroundColor Yellow
    Write-Host "    1. Connect physical Android phone to laptop using a USB data cable."
    Write-Host "    2. On phone: Go to Settings -> About Phone -> tap 'Build number' 7 times."
    Write-Host "    3. On phone: Go to Developer Options -> turn ON 'USB debugging'."
    Write-Host "    4. On phone: Accept the prompt 'Allow USB debugging from this computer'."
    Write-Host "    5. Re-run this script once device is plugged in.`n"
    Write-Host "[STATUS] Physical Android device testing is currently PENDING device connection." -ForegroundColor Magenta
    exit 0
}

Write-Host "[+] Connected device found:" -ForegroundColor Green
$attachedDevices | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }

# 3. Configure reverse port forwarding for all OncoVault local services
Write-Host "`n[+] Establishing ADB Reverse Port Forwarding..." -ForegroundColor Yellow

$portMappings = @(
    @{ Port = 9099; Service = "Firebase Auth Emulator" },
    @{ Port = 8080; Service = "Firebase Firestore Emulator" },
    @{ Port = 5001; Service = "Firebase Cloud Functions Emulator (Callable API)" },
    @{ Port = 8000; Service = "Python NLP, Whisper & AI Diagnostics Engine" },
    @{ Port = 5050; Service = "Hyperledger Fabric Gateway Backend (Optional)" },
    @{ Port = 9199; Service = "Firebase Cloud Storage Emulator" }
)

foreach ($mapping in $portMappings) {
    $p = $mapping.Port
    $s = $mapping.Service
    & $adbPath reverse "tcp:$p" "tcp:$p"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [OK] tcp:$p -> tcp:$p ($s)" -ForegroundColor Green
    } else {
        Write-Host "    [WARN] Failed to reverse tcp:$p ($s)" -ForegroundColor Red
    }
}

# 4. Display active reverse routes
Write-Host "`n[+] Active ADB Reverse Routes on Device:" -ForegroundColor Cyan
& $adbPath reverse --list

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " USB Reverse Tunneling Active!" -ForegroundColor Green
Write-Host " Your physical Android phone can now connect to:" -ForegroundColor Green
Write-Host " - 127.0.0.1:9099 (Auth Emulator)" -ForegroundColor White
Write-Host " - 127.0.0.1:8080 (Firestore Emulator)" -ForegroundColor White
Write-Host " - 127.0.0.1:5001 (Functions Emulator)" -ForegroundColor White
Write-Host " - 127.0.0.1:8000 (Python NLP/AI Engine)" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
