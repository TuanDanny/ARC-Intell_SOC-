@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  In_SOC Questa/ModelSim GUI launcher
rem
rem  Intended workflow:
rem  - Double-click this file from Windows Explorer
rem  - Pick a target in the terminal menu
rem  - The launcher opens one GUI session with the chosen target
rem
rem  Notes:
rem  - Use this .bat from Windows, not from the Questa transcript
rem  - Wave groups / VCD export are configured by gui_hooks.do
rem  - Edit only :register_targets to add/remove built-in targets
rem ============================================================

goto :main

:register_targets
set "TARGET_COUNT=0"
call :add_target "full"    "Full SoC GUI regression (tb_professional)"                 "simulation\questa\In_SOC_run_msim_rtl_verilog_codex.do"
call :add_target "dsp"     "DSP-focused GUI regression (tb_dsp_upgrades)"              "simulation\questa\run_dsp_upgrades_codex.do"
call :add_target "support" "Support blocks GUI smoke regression (tb_support_blocks)"   "simulation\questa\run_support_blocks.do"
call :add_target "periph"  "APB peripherals GUI smoke regression (tb_apb_peripherals)" "simulation\questa\run_apb_peripherals.do"
exit /b 0

:add_target
set /a TARGET_COUNT+=1
set "TARGET_%TARGET_COUNT%_ID=%~1"
set "TARGET_%TARGET_COUNT%_TITLE=%~2"
set "TARGET_%TARGET_COUNT%_DO_WIN=%~3"
set "TARGET_%TARGET_COUNT%_DO_TCL=%~3"
set "TARGET_%TARGET_COUNT%_DO_TCL=!TARGET_%TARGET_COUNT%_DO_TCL:\=/!"
exit /b 0

:print_targets
echo.
echo Available GUI targets:
for /L %%I in (1,1,%TARGET_COUNT%) do (
    call echo   %%I. %%TARGET_%%I_ID%% - %%TARGET_%%I_TITLE%%
)
echo   C. custom - choose any .do file
echo.
echo Examples:
echo   %~nx0
echo   %~nx0 full
echo   %~nx0 2
echo   %~nx0 dsp --manual
echo   %~nx0 full_manual
echo   %~nx0 custom simulation\questa\run_apb_peripherals.do
echo.
exit /b 0

:usage
echo.
echo Usage:
echo   %~nx0
echo   %~nx0 list
echo   %~nx0 ^<target-name^>
echo   %~nx0 ^<target-number^>
echo   %~nx0 ^<target-name^> --manual
echo   %~nx0 full_manual
echo   %~nx0 custom ^<path-to-do-file^>
echo   %~nx0 ^<path-to-do-file.do^> --manual
echo.
call :print_targets
exit /b 1

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
exit /b 0

:set_custom_target
set "CUSTOM_RAW=%~1"
if not defined CUSTOM_RAW exit /b 1

set "CUSTOM_CANDIDATE=%CUSTOM_RAW%"
if not exist "%CUSTOM_CANDIDATE%" if exist "%ROOT%%CUSTOM_RAW%" (
    set "CUSTOM_CANDIDATE=%ROOT%%CUSTOM_RAW%"
)
if not exist "%CUSTOM_CANDIDATE%" (
    echo [ERROR] Could not find custom .do file: %CUSTOM_RAW%
    exit /b 1
)

for %%F in ("%CUSTOM_CANDIDATE%") do (
    set "TARGET_ID=custom"
    set "TARGET_TITLE=Custom GUI launch (%%~nxF)"
    set "TARGET_DO_WIN=%%~fF"
    set "TARGET_DO_TCL=%%~fF"
)
set "TARGET_DO_TCL=%TARGET_DO_TCL:\=/%"
exit /b 0

:prompt_target
call :print_targets
set "TARGET_CHOICE="
set /p TARGET_CHOICE=Select GUI target number, name, or C for custom: 
if not defined TARGET_CHOICE exit /b 1

if /I "%TARGET_CHOICE%"=="c" goto :prompt_custom
if /I "%TARGET_CHOICE%"=="custom" goto :prompt_custom

call :resolve_target "%TARGET_CHOICE%"
if not defined TARGET_INDEX (
    echo [ERROR] Invalid target: %TARGET_CHOICE%
    exit /b 1
)
exit /b 0

:prompt_custom
set "CUSTOM_INPUT="
echo.
set /p CUSTOM_INPUT=Enter .do file path (relative to project root or absolute): 
if not defined CUSTOM_INPUT exit /b 1
call :set_custom_target "%CUSTOM_INPUT%"
exit /b %ERRORLEVEL%

:write_launch_do
set "ROOT_TCL=%ROOT:\=/%"
set "LAUNCH_DO=%ROOT%simulation\questa\_last_gui_launch.do"

(
    echo transcript on
    echo set codex_gui_target {%TARGET_ID%}
    echo set codex_gui_manual %GUI_MANUAL%
    echo cd {%ROOT_TCL%}
    echo do simulation/questa/gui_hooks.do
    echo do %TARGET_DO_TCL%
) > "%LAUNCH_DO%"

if not exist "%LAUNCH_DO%" (
    echo [ERROR] Failed to create launcher do-file: %LAUNCH_DO%
    exit /b 1
)
exit /b 0

:main
set "ROOT=%~dp0..\..\"
set "MODE_ARG=%~1"
set "EXTRA_ARG=%~2"
set "THIRD_ARG=%~3"
set "GUI_MANUAL=0"
set "PAUSE_AT_END=1"
set "TARGET_INDEX="
set "TARGET_ID="
set "TARGET_TITLE="
set "TARGET_DO_WIN="
set "TARGET_DO_TCL="

call :register_targets

if /I "%MODE_ARG%"=="--no-pause" (
    set "PAUSE_AT_END=0"
    set "MODE_ARG="
)
if /I "%EXTRA_ARG%"=="--no-pause" set "PAUSE_AT_END=0"
if /I "%THIRD_ARG%"=="--no-pause" set "PAUSE_AT_END=0"

if /I "%MODE_ARG%"=="full_manual"    set "GUI_MANUAL=1" & set "MODE_ARG=full"
if /I "%MODE_ARG%"=="dsp_manual"     set "GUI_MANUAL=1" & set "MODE_ARG=dsp"
if /I "%MODE_ARG%"=="support_manual" set "GUI_MANUAL=1" & set "MODE_ARG=support"
if /I "%MODE_ARG%"=="periph_manual"  set "GUI_MANUAL=1" & set "MODE_ARG=periph"

if /I "%EXTRA_ARG%"=="manual" set "GUI_MANUAL=1"
if /I "%EXTRA_ARG%"=="--manual" set "GUI_MANUAL=1"
if /I "%THIRD_ARG%"=="manual" set "GUI_MANUAL=1"
if /I "%THIRD_ARG%"=="--manual" set "GUI_MANUAL=1"

if /I "%MODE_ARG%"=="help" goto :usage_fail
if /I "%MODE_ARG%"=="-h" goto :usage_fail
if /I "%MODE_ARG%"=="--help" goto :usage_fail
if /I "%MODE_ARG%"=="list" (
    call :print_targets
    goto :done
)

if /I "%MODE_ARG%"=="custom" (
    if defined EXTRA_ARG (
        call :set_custom_target "%EXTRA_ARG%"
        if errorlevel 1 goto :fail
    ) else (
        call :prompt_custom
        if errorlevel 1 goto :fail
    )
    goto :target_ready
)

set "MODE_EXT=%MODE_ARG:~-3%"
if /I "%MODE_EXT%"==".do" (
    call :set_custom_target "%MODE_ARG%"
    if errorlevel 1 goto :fail
    goto :target_ready
)

if defined MODE_ARG if not "%MODE_ARG%"=="" (
    call :resolve_target "%MODE_ARG%"
    if not defined TARGET_INDEX (
        echo [ERROR] Unknown target: %MODE_ARG%
        echo.
        call :print_targets
        goto :fail
    )
) else (
    call :prompt_target
    if errorlevel 1 goto :fail
)

if not defined TARGET_ID call :load_target "%TARGET_INDEX%"

:target_ready
pushd "%ROOT%" >nul || (
    echo [ERROR] Could not enter project root: %ROOT%
    goto :fail
)

where vsim >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not find vsim in PATH.
    echo         Open a Questa/ModelSim shell, or add the bin folder to PATH.
    goto :fail_popd
)

call :write_launch_do
if errorlevel 1 goto :fail_popd

echo.
echo ============================================================
echo  In_SOC Questa GUI Launcher
echo ============================================================
echo  Target      : %TARGET_ID%
echo  Description : %TARGET_TITLE%
echo  Project root: %CD%
echo  DO file     : %TARGET_DO_WIN%
echo  Launch DO   : simulation\questa\_last_gui_launch.do
if "%GUI_MANUAL%"=="1" (
    echo  Mode        : MANUAL ^(compile/load only, no auto run-all^)
) else (
    echo  Mode        : AUTO ^(compile/load ^+ run-all ^+ wave/VCD setup^)
)
echo ============================================================
echo.
echo [INFO] Opening Questa/ModelSim GUI...
echo [INFO] This launcher is meant to be used from Windows terminal/Explorer.
echo [INFO] Curated waves and VCD export will be added automatically.

start "" vsim -gui -do "do simulation/questa/_last_gui_launch.do"
set "START_RC=%ERRORLEVEL%"

if "%START_RC%"=="0" (
    echo [OK] GUI launch request sent successfully.
    echo [INFO] If the GUI was already open, close the old session first.
    goto :done_popd
)

echo [ERROR] Could not start Questa/ModelSim GUI. Exit code = %START_RC%
goto :fail_popd

:usage_fail
call :usage
goto :fail

:fail_popd
popd >nul

:fail
if "%PAUSE_AT_END%"=="1" pause
exit /b 1

:done_popd
popd >nul

:done
if "%PAUSE_AT_END%"=="1" pause
exit /b 0
