@echo off
setlocal
set SCRIPT_DIR=%~dp0
set INPUT=%SCRIPT_DIR%..\sim\intelli_safe_arc_test.vcd
set OUTPUT=%SCRIPT_DIR%output\flow_visualizer_v2.html

set /p START=Nhap start ps (mac dinh 0): 
if "%START%"=="" set START=0
set /p END=Nhap end ps (mac dinh 4000000): 
if "%END%"=="" set END=4000000

node "%SCRIPT_DIR%flow_visualizer_v2.js" --input "%INPUT%" --output "%OUTPUT%" --start %START% --end %END%
if errorlevel 1 goto :fail

echo.
echo Da tao xong V2 tai:
echo %OUTPUT%
echo Ban hay mo file HTML nay bang trinh duyet.
goto :done

:fail
echo.
echo Co loi khi tao Flow Visualizer V2.

:done
endlocal
