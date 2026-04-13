@echo off
setlocal EnableExtensions

set "MODE=full"
set "PAUSE_AT_END=1"

if /I "%~1"=="full" set "MODE=full"
if /I "%~1"=="dsp" set "MODE=dsp"
if /I "%~1"=="--no-pause" set "PAUSE_AT_END=0"
if /I "%~2"=="--no-pause" set "PAUSE_AT_END=0"

if not "%~1"=="" (
    if /I not "%~1"=="full" if /I not "%~1"=="dsp" if /I not "%~1"=="--no-pause" goto :usage
)

set "ROOT=%~dp0"
pushd "%ROOT%" >nul || (
    echo [ERROR] Khong vao duoc project root: %ROOT%
    goto :fail
)

where vsim >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Khong tim thay lenh vsim trong PATH.
    echo         Hay mo Questa/ModelSim command shell, hoac them thu muc bin vao PATH.
    goto :fail_popd
)

if /I "%MODE%"=="dsp" (
    set "DO_FILE=simulation\questa\run_dsp_upgrades_codex.do"
    set "DO_FILE_TCL=simulation/questa/run_dsp_upgrades_codex.do"
    set "RUN_TITLE=DSP-focused regression (tb_dsp_upgrades)"
    set "SUMMARY_TOKEN=[DSP-UPG] SUMMARY"
) else (
    set "DO_FILE=simulation\questa\In_SOC_run_msim_rtl_verilog_codex.do"
    set "DO_FILE_TCL=simulation/questa/In_SOC_run_msim_rtl_verilog_codex.do"
    set "RUN_TITLE=Full SoC regression (tb_professional)"
    set "SUMMARY_TOKEN=EXTRA SCENARIOS"
)

if exist transcript del /q transcript >nul 2>&1

echo.
echo ============================================================
echo  In_SOC ModelSim Launcher
echo ============================================================
echo  Mode        : %MODE%
echo  Description : %RUN_TITLE%
echo  Project root: %CD%
echo  DO file     : %DO_FILE%
echo ============================================================
echo.

vsim -c -do "do %DO_FILE_TCL%; quit -f"
set "VSIM_RC=%ERRORLEVEL%"

echo.
echo ============================================================
echo  Transcript tail
echo ============================================================
if exist transcript (
    powershell -NoProfile -Command "Get-Content -Path 'transcript' -Tail 40"
) else (
    echo [WARN] Khong tim thay file transcript sau khi chay.
)
echo ============================================================
echo.

if exist transcript (
    findstr /C:"Cannot open macro file" transcript >nul && set "VSIM_RC=1"
    findstr /C:"%SUMMARY_TOKEN%" transcript >nul || set "VSIM_RC=1"
)

if "%VSIM_RC%"=="0" (
    echo [OK] Mo phong da chay xong. Exit code = 0
) else (
    echo [ERROR] Mo phong ket thuc voi exit code = %VSIM_RC%
)

goto :done_popd

:usage
echo.
echo CACH DUNG:
echo   %~nx0
echo   %~nx0 full
echo   %~nx0 dsp
echo   %~nx0 full --no-pause
echo   %~nx0 dsp --no-pause
echo.
set "VSIM_RC=1"
goto :done

:fail_popd
set "VSIM_RC=1"
goto :done_popd

:fail
set "VSIM_RC=1"
goto :done

:done_popd
popd >nul

:done
if "%PAUSE_AT_END%"=="1" pause
exit /b %VSIM_RC%
