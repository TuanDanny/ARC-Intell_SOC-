# Run Folder

Folder này gom file chạy mô phỏng, demo, log, prompt kiểm thử.

## Cấu trúc

```text
run/
  README.md
  scripts/
    run_modelsim_here.bat
    run_modelsim_gui_here.bat
    run_full_gui.bat
    run_dsp_gui.bat
    run_periph_gui.bat
    run_support_gui.bat
    debug_step.bat
    ip_dsp/
    ip_wdt/
    ip_bist/
    ip_spi/
  questa/
    *.do
  logs/
    transcript_*.txt
    waveform_before_run.wlf
  demo/
    intelli_safe_arc_test.vcd
    intelli_safe_arc_test_sim.vcd
  plan/
    full_simulation_prompt.md
```

## Cách chạy khuyến nghị

Các script trong `run/scripts/` đã được chỉnh path để chạy từ project root:

```bat
cd /d D:\APP\Quatus_Workspace\In_SOC
run\scripts\run_modelsim_here.bat full --no-pause
run\scripts\run_modelsim_here.bat dsp --no-pause
run\scripts\run_modelsim_here.bat ip_dsp --no-pause
run\scripts\run_modelsim_here.bat support --no-pause
run\scripts\run_modelsim_here.bat periph --no-pause
```

IP standalone:

```bat
cd /d D:\APP\Quatus_Workspace\In_SOC
run\scripts\ip_wdt\run_regression.bat --no-pause
run\scripts\ip_bist\run_regression.bat --no-pause
run\scripts\ip_spi\run_regression.bat --no-pause
run\scripts\ip_dsp\run_regression.bat --no-pause
```

GUI quick launch:

```bat
cd /d D:\APP\Quatus_Workspace\In_SOC
run\scripts\run_full_gui.bat
run\scripts\run_dsp_gui.bat
run\scripts\run_periph_gui.bat
run\scripts\run_support_gui.bat
```

## Evidence logs

Regression logs đã copy vào:

```text
run/logs/
```

Các target đã PASS:

| Target | Log | Expected summary |
| --- | --- | --- |
| full | `run/logs/transcript_full.txt` | `EXTRA SCENARIOS 11-26 SUMMARY: PASS=16 FAIL=0 KNOWN_ISSUE=0` |
| dsp | `run/logs/transcript_dsp.txt` | `[DSP-UPG] SUMMARY PASS=9 FAIL=0` |
| ip_dsp | `run/logs/transcript_ip_dsp.txt` | `[DSP-IP] SUMMARY PASS=4 FAIL=0` |
| support | `run/logs/transcript_support.txt` | `[SUPPORT] SUMMARY PASS=3 FAIL=0` |
| periph | `run/logs/transcript_periph.txt` | `[PERIPH] SUMMARY PASS=3 FAIL=0` |
| ip_wdt | `run/logs/transcript_ip_wdt.txt` | `[WDT-IP] SUMMARY PASS=5 FAIL=0` |
| ip_bist | `run/logs/transcript_ip_bist.txt` | `[BIST-IP] SUMMARY PASS=5 FAIL=0` |
| ip_spi | `run/logs/transcript_ip_spi.txt` | `[SPI-IP] SUMMARY PASS=5 FAIL=0` |

## Ghi chú

- `run/` là folder gom file chạy/evidence, không thay thế source tree.
- RTL, testbench, IP vẫn nằm ở `rtl/`, `sim/`, `ip/`.
- `run/scripts/run_modelsim_here.bat` đặt project root = `run/scripts/../..`.
- `run/scripts/ip_*/*run_regression.bat` trỏ về IP gốc trong `ip/` để build đúng RTL/testbench.
- `run/scripts/ip_*/*run_regression.bat` mặc định `pause` cuối cửa sổ; thêm `--no-pause` khi chạy batch/CI.
- Nên chạy từ project root như lệnh trên để log/workdir dễ kiểm soát.