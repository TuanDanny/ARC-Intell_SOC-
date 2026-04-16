@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  In_SOC ModelSim launcher
rem
rem  How to maintain:
rem  - Only edit the TARGET_* list in :register_targets
rem  - Each target needs: ID, TITLE, DO file, SUMMARY token
rem  - You can run by target name, target number, or choose from menu
rem ============================================================

set "ROOT=%~dp0"
set "MODE_ARG=%~1"
set "EXTRA_ARG=%~2"
set "PAUSE_AT_END=1"
set "TARGET_CHOICE="
set "TARGET_INDEX="
set "VSIM_RC=0"

call :register_targets

if /I "%MODE_ARG%"=="--no-pause" (
    set "PAUSE_AT_END=0"
    set "MODE_ARG="
)
if /I "%EXTRA_ARG%"=="--no-pause" set "PAUSE_AT_END=0"

if /I "%MODE_ARG%"=="help" goto :usage
if /I "%MODE_ARG%"=="-h" goto :usage
if /I "%MODE_ARG%"=="--help" goto :usage
if /I "%MODE_ARG%"=="list" (
    call :print_targets
    goto :done
)

if not "%MODE_ARG%"=="" (
    call :resolve_target "%MODE_ARG%"
    if not defined TARGET_INDEX (
        echo [ERROR] Unknown target: %MODE_ARG%
        echo.
        call :print_targets
        set "VSIM_RC=1"
        goto :done
    )
) else (
    call :prompt_target
    if not defined TARGET_INDEX (
        set "VSIM_RC=1"
        goto :done
    )
)

call :load_target "%TARGET_INDEX%"

pushd "%ROOT%" >nul || (
    echo [ERROR] Could not enter project root: %ROOT%
    set "VSIM_RC=1"
    goto :done
)

where vsim >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not find vsim in PATH.
    echo         Open a Questa/ModelSim shell, or add the bin folder to PATH.
    set "VSIM_RC=1"
    goto :done_popd
)

if exist transcript del /q transcript >nul 2>&1

echo.
echo ============================================================
echo  In_SOC ModelSim Launcher
echo ============================================================
echo  Target      : %TARGET_ID%
echo  Description : %TARGET_TITLE%
echo  Project root: %CD%
echo  DO file     : %TARGET_DO_WIN%
echo ============================================================
echo.

vsim -c -do "do %TARGET_DO_TCL%; quit -f"
set "VSIM_RC=%ERRORLEVEL%"

echo.
echo ============================================================
echo  Transcript tail
echo ============================================================
if exist transcript (
    powershell -NoProfile -Command "Get-Content -Path 'transcript' -Tail 40"
) else (
    echo [WARN] Transcript was not created.
)
echo ============================================================
echo.

if exist transcript (
    findstr /C:"Cannot open macro file" transcript >nul && set "VSIM_RC=1"
    findstr /C:"%TARGET_SUMMARY%" transcript >nul || set "VSIM_RC=1"
)

if "%VSIM_RC%"=="0" (
    echo [OK] Simulation completed successfully. Exit code = 0
) else (
    echo [ERROR] Simulation finished with exit code = %VSIM_RC%
)

goto :done_popd

:register_targets
set "TARGET_COUNT=0"
call :add_target "full"    "Full SoC regression (tb_professional)"             "simulation\questa\In_SOC_run_msim_rtl_verilog_codex.do" "EXTRA SCENARIOS"
call :add_target "dsp"     "DSP-focused regression (tb_dsp_upgrades)"          "simulation\questa\run_dsp_upgrades_codex.do"            "[DSP-UPG] SUMMARY"
call :add_target "support" "Support blocks smoke regression (tb_support_blocks)" "simulation\questa\run_support_blocks.do"               "[SUPPORT] SUMMARY"
call :add_target "periph"  "APB peripherals smoke regression (tb_apb_peripherals)" "simulation\questa\run_apb_peripherals.do"            "[PERIPH] SUMMARY"
exit /b 0

:add_target
set /a TARGET_COUNT+=1
set "TARGET_%TARGET_COUNT%_ID=%~1"
set "TARGET_%TARGET_COUNT%_TITLE=%~2"
set "TARGET_%TARGET_COUNT%_DO_WIN=%~3"
set "TARGET_%TARGET_COUNT%_DO_TCL=%~3"
set "TARGET_%TARGET_COUNT%_DO_TCL=!TARGET_%TARGET_COUNT%_DO_TCL:\=/!"
set "TARGET_%TARGET_COUNT%_SUMMARY=%~4"
exit /b 0

:print_targets
echo.
echo Available targets:
for /L %%I in (1,1,%TARGET_COUNT%) do (
    call echo   %%I. %%TARGET_%%I_ID%% - %%TARGET_%%I_TITLE%%
)
echo.
echo Examples:
echo   %~nx0 full
echo   %~nx0 2
echo   %~nx0 periph --no-pause
echo.
exit /b 0

:prompt_target
call :print_targets
set /p TARGET_CHOICE=Select target number or name: 
if "%TARGET_CHOICE%"=="" (
    echo [INFO] No target selected.
    exit /b 0
)
call :resolve_target "%TARGET_CHOICE%"
if not defined TARGET_INDEX (
    echo [ERROR] Invalid target: %TARGET_CHOICE%
)
exit /b 0

:resolve_target
set "TARGET_INDEX="
set "RESOLVE_ARG=%~1"

for /L %%I in (1,1,%TARGET_COUNT%) do (
    if /I "!RESOLVE_ARG!"=="%%I" set "TARGET_INDEX=%%I"
    if /I "!RESOLVE_ARG!"=="!TARGET_%%I_ID!" set "TARGET_INDEX=%%I"
)
exit /b 0

:load_target
set "TARGET_INDEX=%~1"
call set "TARGET_ID=%%TARGET_%TARGET_INDEX%_ID%%"
call set "TARGET_TITLE=%%TARGET_%TARGET_INDEX%_TITLE%%"
call set "TARGET_DO_WIN=%%TARGET_%TARGET_INDEX%_DO_WIN%%"
call set "TARGET_DO_TCL=%%TARGET_%TARGET_INDEX%_DO_TCL%%"
call set "TARGET_SUMMARY=%%TARGET_%TARGET_INDEX%_SUMMARY%%"
exit /b 0

:usage
echo.
echo Usage:
echo   %~nx0
echo   %~nx0 list
echo   %~nx0 ^<target-name^>
echo   %~nx0 ^<target-number^>
echo   %~nx0 ^<target-name^> --no-pause
echo.
call :print_targets
set "VSIM_RC=1"
goto :done

:done_popd
popd >nul

:done
if "%PAUSE_AT_END%"=="1" pause
exit /b %VSIM_RC%
