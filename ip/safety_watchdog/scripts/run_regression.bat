@echo off
setlocal EnableExtensions

set "IP_ROOT=%~dp0.."
pushd "%IP_ROOT%" >nul || (
    echo [WDT-IP][ERROR] Could not enter IP root: %IP_ROOT%
    exit /b 1
)

where vsim >nul 2>&1
if errorlevel 1 (
    echo [WDT-IP][ERROR] Could not find vsim in PATH.
    popd >nul
    exit /b 1
)

if exist transcript del /q transcript >nul 2>&1

echo ============================================================
echo  safety_watchdog IP regression
echo ============================================================
echo  IP root : %CD%
echo  DO file : scripts\run_questa.do
echo ============================================================

vsim -c -do "do scripts/run_questa.do; quit -f"
set "RC=%ERRORLEVEL%"

echo ============================================================
echo  Transcript tail
echo ============================================================
if exist transcript (
    powershell -NoProfile -Command "Get-Content -Path 'transcript' -Tail 40"
) else (
    echo [WDT-IP][WARN] Transcript was not created.
    set "RC=1"
)
echo ============================================================

if exist transcript (
    findstr /C:"[WDT-IP] SUMMARY PASS=5 FAIL=0" transcript >nul || set "RC=1"
)

if "%RC%"=="0" (
    echo [WDT-IP][OK] Regression completed successfully.
) else (
    echo [WDT-IP][ERROR] Regression failed with exit code %RC%.
)

popd >nul
exit /b %RC%
