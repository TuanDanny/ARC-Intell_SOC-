@echo off
setlocal EnableExtensions
set "PAUSE_AT_END=1"
if /I "%~1"=="--no-pause" set "PAUSE_AT_END=0"

set "IP_ROOT=%~dp0..\..\..\ip\logic_bist"
set "RC=0"
pushd "%IP_ROOT%" >nul || (
    echo [BIST-IP][ERROR] Could not enter IP root: %IP_ROOT%
    set "RC=1"
    goto :done
)

where vsim >nul 2>&1
if errorlevel 1 (
    echo [BIST-IP][ERROR] Could not find vsim in PATH.
    set "RC=1"
    goto :done
)

if exist transcript del /q transcript >nul 2>&1

echo ============================================================
echo  logic_bist IP regression
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
    echo [BIST-IP][WARN] Transcript was not created.
    set "RC=1"
)
echo ============================================================

if exist transcript (
    findstr /C:"[BIST-IP] SUMMARY PASS=5 FAIL=0" transcript >nul || set "RC=1"
)

if "%RC%"=="0" (
    echo [BIST-IP][OK] Regression completed successfully.
) else (
    echo [BIST-IP][ERROR] Regression failed with exit code %RC%.
)

:done
popd >nul 2>nul
if "%PAUSE_AT_END%"=="1" pause
exit /b %RC%
