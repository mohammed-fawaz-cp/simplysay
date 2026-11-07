# SimplySay Automated Call Test Runner (Maestro + ADB)
param(
    [string]$Suite = "single", # 'single', 'dual', or 'backend'
    [switch]$Headless = $false
)

$env:Path = "$env:USERPROFILE\.maestro\maestro\bin;$env:USERPROFILE\.android\sdk\platform-tools;$env:Path"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " SimplySay Automated Test Suite " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Check Backend Tests
if ($Suite -eq "backend" -or $Suite -eq "all") {
    Write-Host "`n[1/3] Running Backend Signaling Tests..." -ForegroundColor Yellow
    Push-Location "server"
    python test_signaling.py
    Pop-Location
}

# 2. Check Device Connectivity
Write-Host "`n[2/3] Checking Connected Android Devices / Emulators..." -ForegroundColor Yellow
$devices = adb devices | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] }

if ($devices.Count -eq 0) {
    Write-Host "No running emulators detected." -ForegroundColor DarkYellow
    Write-Host "Available AVDs:"
    Get-ChildItem -Path "$env:USERPROFILE\.android\avd" -Filter "*.ini" | ForEach-Object { $_.BaseName }
    Write-Host "`nTo start an emulator, run: emulator -avd <avd_name> -no-snapshot"
    exit 0
}

Write-Host "Found $($devices.Count) active device(s): $($devices -join ', ')" -ForegroundColor Green

# Ensure all devices are awake and keyguard dismissed
foreach ($d in $devices) {
    adb -s $d shell "svc power stayon true; settings put system screen_off_timeout 2147483647; wm dismiss-keyguard; input keyevent 82" | Out-Null
}

# 3. Run Maestro Flows
if ($devices.Count -eq 1 -or $Suite -eq "single") {
    $targetDevice = $devices[0]
    Write-Host "`n[3/3] Running Single-Device Test on $targetDevice..." -ForegroundColor Yellow
    maestro --device $targetDevice test "$PSScriptRoot\.maestro\flows\01_launch_and_permissions.yaml"
} elseif ($devices.Count -ge 2 -and ($Suite -eq "dual" -or $Suite -eq "all")) {
    $devCaller = $devices[0]
    $devCallee = $devices[1]
    Write-Host "`n[3/3] Running Dual-Device E2E Call Scenario..." -ForegroundColor Yellow
    Write-Host "Caller: $devCaller | Callee: $devCallee" -ForegroundColor Green

    $calleeFlowPath = "$PSScriptRoot\.maestro\flows\05_dual_device_callee.yaml"
    $callerFlowPath = "$PSScriptRoot\.maestro\flows\04_dual_device_caller.yaml"

    # Start callee listener in background
    $calleeJob = Start-Job -ScriptBlock {
        param($callee, $flowPath)
        $env:Path = "$env:USERPROFILE\.maestro\maestro\bin;$env:USERPROFILE\.android\sdk\platform-tools;$env:Path"
        maestro --device $callee test $flowPath
    } -ArgumentList $devCallee, $calleeFlowPath

    Start-Sleep -Seconds 2

    # Start caller flow
    maestro --device $devCaller test $callerFlowPath

    # Wait for both devices to reach host code & join dialog
    Receive-Job -Job $calleeJob -Wait
    Remove-Job -Job $calleeJob

    Write-Host "`n[4/4] Bridging Instant Call Code & Verifying Connected Call..." -ForegroundColor Yellow
    python "$PSScriptRoot\scripts\bridge_instant_call.py" $devCaller $devCallee
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Call connection verification failed!" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nTest execution completed successfully!" -ForegroundColor Green

