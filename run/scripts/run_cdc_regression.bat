@echo off
setlocal
cd /d %~dp0\..\..
vsim -c -do simulation/questa/run_cdc_fifo.do
if errorlevel 1 exit /b 1
vsim -c -do simulation/questa/run_spi_cdc_bridge.do
if errorlevel 1 exit /b 1
echo CDC regression completed.
endlocal
