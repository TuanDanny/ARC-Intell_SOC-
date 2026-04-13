@echo off
setlocal
set SCRIPT_DIR=%~dp0
set INPUT=%SCRIPT_DIR%..\sim\intelli_safe_arc_test.vcd
set OUTPUT=%SCRIPT_DIR%output\flow_visualizer_v1.html

echo.
echo In_SOC Flow Visualizer V1
echo -------------------------
set /p START_PS=Nhap Start time (ps, mac dinh 0): 
if "%START_PS%"=="" set START_PS=0
set /p END_PS=Nhap End time (ps, mac dinh 4000000): 
if "%END_PS%"=="" set END_PS=4000000

echo.
node "%SCRIPT_DIR%flow_visualizer_v1.js" --input "%INPUT%" --output "%OUTPUT%" --start %START_PS% --end %END_PS%
if errorlevel 1 goto :fail

echo.
echo HTML da duoc tao tai:
echo %OUTPUT%
echo.
echo Ban co the mo file HTML nay bang trinh duyet de xem overview va timing.
goto :eof

:fail
echo.
echo Co loi khi tao visualizer.
exit /b 1
