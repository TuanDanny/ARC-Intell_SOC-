@echo off
setlocal EnableExtensions

set "MODE=full"

if /I "%~1"=="full" set "MODE=full"
if /I "%~1"=="dsp" set "MODE=dsp"

if not "%~1"=="" (
    if /I not "%~1"=="full" if /I not "%~1"=="dsp" goto :usage
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
    set "DO_FILE_TCL=simulation/questa/run_dsp_upgrades_codex.do"
    set "RUN_TITLE=DSP-focused GUI regression (tb_dsp_upgrades)"
) else (
    set "DO_FILE_TCL=simulation/questa/In_SOC_run_msim_rtl_verilog_codex.do"
    set "RUN_TITLE=Full SoC GUI regression (tb_professional)"
)

echo.
echo ============================================================
echo  In_SOC ModelSim GUI Launcher
echo ============================================================
echo  Mode        : %MODE%
echo  Description : %RUN_TITLE%
echo  Project root: %CD%
echo  DO file     : %DO_FILE_TCL%
echo ============================================================
echo.
echo [INFO] Dang mo Questa/ModelSim GUI...

start "" vsim -gui -do "do %DO_FILE_TCL%"
set "START_RC=%ERRORLEVEL%"

if "%START_RC%"=="0" (
    echo [OK] GUI da duoc goi. Cua so ModelSim/Questa se tu mo.
    goto :done_popd
) else (
    echo [ERROR] Khong goi duoc ModelSim/Questa GUI. Exit code = %START_RC%
    goto :fail_popd
)

:usage
echo.
echo CACH DUNG:
echo   %~nx0
echo   %~nx0 full
echo   %~nx0 dsp
echo.
exit /b 1

:fail_popd
popd >nul

:fail
exit /b 1

:done_popd
popd >nul
exit /b 0
