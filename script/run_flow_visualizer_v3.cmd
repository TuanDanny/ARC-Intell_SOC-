@echo off
setlocal
set SCRIPT_DIR=%~dp0
set DEFAULT_INPUT=%SCRIPT_DIR%..\sim\intelli_safe_arc_test.vcd
set OUTPUT=%SCRIPT_DIR%output\flow_visualizer_v3.html
set INPUT=%~1

if "%INPUT%"=="" (
    set /p INPUT=Nhap duong dan VCD - Enter de dung mac dinh: 
)
if "%INPUT%"=="" set INPUT=%DEFAULT_INPUT%

if not exist "%INPUT%" goto :missing_input

echo.
echo Dang dung VCD:
echo %INPUT%
echo HTML se duoc ghi de vao:
echo %OUTPUT%

set /p START=Nhap start ps (mac dinh 0): 
if "%START%"=="" set START=0
set /p END=Nhap end ps (mac dinh 4000000): 
if "%END%"=="" set END=4000000

node "%SCRIPT_DIR%flow_visualizer_v3.js" --input "%INPUT%" --output "%OUTPUT%" --start %START% --end %END%
if errorlevel 1 goto :fail

echo.
echo Da tao xong V3 tai:
echo %OUTPUT%
echo Ban hay refresh lai file HTML nay bang Ctrl+F5 neu dang mo san.
goto :done

:missing_input
echo.
echo Khong tim thay file VCD:
echo %INPUT%
goto :done

:fail
echo.
echo Co loi khi tao Flow Visualizer V3.

:done
endlocal
