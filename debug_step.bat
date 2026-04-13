@echo off
:: Thiet lap trinh bien dich voi duong dan include
set IV=iverilog -g2012 -I rtl/include -I rtl/include/apb
set BUILD=build
if not exist %BUILD% mkdir %BUILD%

echo.
echo ========================================================
echo  BUOC 1: KIEM TRA CU PHAP BUS (INTERFACE)
echo ========================================================
:: Tao file dummy de Icarus co Top Module
echo module dummy_top; APB_BUS bus(); endmodule > %BUILD%/dummy_bus.sv

:: Phai doc file apb_bus.sv cung voi dummy
%IV% -o %BUILD%/test_bus.out rtl/include/apb_bus.sv %BUILD%/dummy_bus.sv
if %errorlevel% neq 0 (
    echo [LOI CU PHAP] File apb_bus.sv bi loi!
    goto :FAIL
)
echo [OK] Bus Interface chuan 100%%.

echo.
echo ========================================================
echo  BUOC 2: KIEM TRA CAU HINH (CONFIG)
echo ========================================================
:: FIX: Phai kem theo file apb_bus.sv o day de no hieu dummy_bus
%IV% -o %BUILD%/test_config.out rtl/include/apb_bus.sv rtl/include/config.sv %BUILD%/dummy_bus.sv
if %errorlevel% neq 0 (
    echo [LOI CU PHAP] File config.sv bi loi!
    goto :FAIL
)
echo [OK] Config chuan 100%%.

echo.
echo ========================================================
echo  BUOC 3: KIEM TRA CPU (CORE)
echo ========================================================
%IV% -o %BUILD%/test_cpu.out rtl/include/apb_bus.sv rtl/include/config.sv rtl/core/cpu_8bit.sv
if %errorlevel% neq 0 (
    echo [LOI] CPU BI LOI!
    goto :FAIL
)
echo [OK] CPU da nhan dien duoc Bus va Config!

echo.
echo ========================================================
echo  BUOC 4: KIEM TRA DSP
echo ========================================================
%IV% -o %BUILD%/test_dsp.out rtl/include/apb_bus.sv rtl/include/config.sv rtl/periph/dsp_arc_detect.sv
if %errorlevel% neq 0 (
    echo [LOI] DSP BI LOI!
    goto :FAIL
)
echo [OK] DSP ngon lanh.

echo.
echo ========================================================
echo  BUOC 5: KIEM TRA TOP SOC (FINAL)
echo ========================================================
%IV% -o %BUILD%/test_top.out ^
    rtl/include/apb_bus.sv rtl/include/config.sv ^
    rtl/lib/rstgen.sv rtl/lib/pulp_clock_gating.sv rtl/bus/apb_node.sv ^
    rtl/periph/dsp_arc_detect.sv ^
    rtl/periph/apb_gpio.sv rtl/periph/apb_uart_wrap.sv ^
    rtl/periph/safety_watchdog.sv rtl/periph/logic_bist.sv ^
    rtl/periph/timer/up_down_counter.sv rtl/periph/timer/prescaler.sv ^
    rtl/periph/timer/comparator.sv rtl/periph/timer/adv_timer_apb_if.sv ^
    rtl/periph/timer/timer_cntrl.sv rtl/periph/timer/input_stage.sv ^
    rtl/periph/timer/timer_module.sv rtl/periph/timer/apb_adv_timer.sv ^
    rtl/core/cpu_8bit.sv ^
    rtl/top_soc.sv

if %errorlevel% neq 0 (
    echo [LOI] CO LOI O FILE TOP HOAC CAC MODULE CON LAI!
    goto :FAIL
)
echo.
echo [THANH CONG] TOAN BO HE THONG DA SAN SANG MO PHONG!
pause
goto :EOF

:FAIL
echo.
echo [!!!] DEBUG DUNG LAI. HAY SUA LOI TREN.
pause