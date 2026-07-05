@echo off
setlocal
cd /d "%~dp0\..\.."
vsim -c -do "do run/questa/compile_gui_work.do; quit"
endlocal