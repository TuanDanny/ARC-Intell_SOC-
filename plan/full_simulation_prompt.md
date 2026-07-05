Bạn là verification engineer cho project FPGA/SystemVerilog `In_SOC`.

Mục tiêu:
- Chạy đầy đủ các regression/testbench hiện có.
- Không sửa RTL nếu chưa cần.
- Thu transcript/log cho từng target.
- Lập bảng PASS/FAIL/Known issue.
- Đối chiếu kết quả mô phỏng với tài liệu hiện tại.
- Không phóng đại claim vượt RTL.

Bối cảnh project:
- Project root: thư mục chứa `In_SOC.qpf`, `run_modelsim_here.bat`, `rtl/`, `sim/`, `ip/`, `simulation/questa/`.
- Thiết kế là mini SoC FPGA phát hiện arc/glowing-contact.
- Top-level: `rtl/top_soc.sv`.
- Clock hệ thống: 50 MHz.
- Bus: APB.
- Module chính:
  - `cpu_8bit`
  - `apb_node`
  - `apb_spi_adc_bridge`
  - `dsp_arc_detect`
  - `safety_watchdog`
  - `logic_bist`
  - `apb_gpio`
  - `apb_uart_wrap`
  - `apb_adv_timer`
- IP chính: `dsp_arc_detect`.
- IP phụ: `apb_spi_adc_bridge`, `safety_watchdog`, `logic_bist`.
- `top_soc` là reference integration/demo system, không phải reusable IP boundary.

Tài liệu cần bám:
- `README.md`
- `walkthrough.md`
- `ip_reuse_readiness.md`
- `docs/ip/ip_scope_and_rtl_alignment.md`
- `docs/ip/dsp_arc_detect.md`
- `docs/ip/safety_watchdog.md`
- `docs/ip/logic_bist.md`
- `docs/ip/apb_spi_adc_bridge.md`
- `plan/dsp_plan.md`
- `plan/watchdog_plan.md`
- `plan/bist_plan.md`

Quy tắc claim:
- Chỉ nói “implemented” nếu thấy trong RTL hoặc testbench hiện tại.
- `dsp_arc_detect`: configurable APB-based arc/thermal detection IP candidate, có telemetry/profile/adaptive threshold/spike window/thermal/quiet-zone theo tài liệu hiện tại.
- Không nói DSP đã có vendor-grade IP package hoàn chỉnh, timing closure, coverage closure, hoặc guaranteed latency < 10 us.
- `safety_watchdog`: basic APB watchdog với magic feed, lock, timeout, reset pulse. Không nói independent/windowed/retained cause/pretimeout nếu RTL chưa có.
- `logic_bist`: functional BIST helper với LFSR/MISR/APB/DSP injection. Không nói full scan LBIST hoặc on-chip golden compare/pass-fail thật nếu RTL chưa có.
- `apb_spi_adc_bridge`: SPI-to-stream bridge có APB telemetry/sample shadow. Không nói có FIFO/CDC/backpressure true nếu RTL chưa có.
- Không nói project là complete commercial IP catalog.

Kiểm tra trước khi chạy:
1. Xác nhận đang đứng ở project root.
2. Kiểm tra `vsim` có trong PATH:
   ```bat
   where vsim
   ```
3. Nếu `vsim` không có, báo user mở Questa/ModelSim command shell hoặc add `bin` vào PATH.
4. Kiểm tra rủi ro portability:
   - `rtl/top_soc.sv` có thể còn include tuyệt đối:
     - `D:/APP/Quatus_Workspace/In_SOC/rtl/include/apb_bus.sv`
     - `D:/APP/Quatus_Workspace/In_SOC/rtl/include/config.sv`
   - Nếu compile lỗi do include path, đề xuất sửa sang include tương đối:
     ```systemverilog
     `include "apb_bus.sv"
     `include "config.sv"
     ```
     và bảo đảm `.do`/`qsf` có include/search path đúng.
5. Dọn môi trường mô phỏng cũ để tránh stale compiled objects/log bị ghi đè:
   - Nếu chạy CLI thủ công, xóa thư mục `work/` cũ trước khi compile lại.
   - Xóa hoặc archive `transcript`, `vsim.wlf`, `dump.vcd` cũ tại project root trước khi chạy target mới.
   - Nếu dùng launcher chính, chỉ dọn khi chắc chắn launcher không cần cache/library cũ.

Regression bắt buộc bằng launcher chính:
Chạy từng lệnh từ project root:

1. Full SoC regression:
   ```bat
   run_modelsim_here.bat full --no-pause
   ```
   Bench/DO:
   - `sim/tb_professional.sv`
   - `simulation/questa/In_SOC_run_msim_rtl_verilog_codex.do`
   Expected token:
   - `EXTRA SCENARIOS 11-26 SUMMARY`
   Expected nội dung:
   - compile Errors: 0
   - Không có cảnh báo `Inferring latch` (chốt dữ liệu không mong muốn) hoặc `Combinational loop` (vòng lặp tổ hợp quẩn).
   - Không có cảnh báo `Metastability` hoặc vi phạm setup/hold nếu chạy gate-level/timing simulation.
   - Không có dòng nào chứa `Assertion error` hoặc `Assertion failure` trong transcript.
   - simulation reaches `$finish`
   - `EXTRA SCENARIOS 11-26 SUMMARY: PASS=16 FAIL=0 KNOWN_ISSUE=0`
   Coverage chức năng:
   - scenario 1..10 directed system tests
   - extra scenario 11..26
   - arc/inrush/intermittent/solid/stuck ADC/glowing contact/watchdog/power glitch/UART/BIST/interrupt collision/DSP upgrades/SPI checks/CPU paged MMIO/profile.

2. DSP-focused regression:
   ```bat
   run_modelsim_here.bat dsp --no-pause
   ```
   Bench/DO:
   - `sim/tb_dsp_upgrades.sv`
   - `simulation/questa/run_dsp_upgrades_codex.do`
   Expected token:
   - `[DSP-UPG] SUMMARY`
   Expected nội dung:
   - compile Errors: 0
   - Không có cảnh báo `Inferring latch` (chốt dữ liệu không mong muốn) hoặc `Combinational loop` (vòng lặp tổ hợp quẩn).
   - Không có cảnh báo `Metastability` hoặc vi phạm setup/hold nếu chạy gate-level/timing simulation.
   - Không có dòng nào chứa `Assertion error` hoặc `Assertion failure` trong transcript.
   - `[DSP-UPG] SUMMARY PASS=9 FAIL=0`
   Scenarios:
   - SC16 weighted attack
   - SC17 spike window
   - SC18 adaptive noise floor
   - SC19 stream awareness
   - SC20 thermal path
   - SC21 default glowing-contact tuning
   - SC22 zero-cross / quiet-zone
   - SC23 trip telemetry
   - SC25 boot profile / profile load

3. Standalone DSP IP regression:
   ```bat
   run_modelsim_here.bat ip_dsp --no-pause
   ```
   Bench/DO:
   - `ip/dsp_arc_detect/tb/tb_dsp_arc_detect_ip.sv`
   - `ip/dsp_arc_detect/tb/dsp_arc_detect_ip_assertions.sv`
   - `ip/dsp_arc_detect/scripts/run_questa.do`
   Expected token:
   - `[DSP-IP] SUMMARY`
   Expected nội dung:
   - compile Errors: 0
   - Không có cảnh báo `Inferring latch` (chốt dữ liệu không mong muốn) hoặc `Combinational loop` (vòng lặp tổ hợp quẩn).
   - Không có cảnh báo `Metastability` hoặc vi phạm setup/hold nếu chạy gate-level/timing simulation.
   - Không có dòng nào chứa `Assertion error` hoặc `Assertion failure` trong transcript.
   - `[DSP-IP] SUMMARY PASS=4 FAIL=0`
   Scenarios:
   - SC01 reset register map
   - SC02 APB writes, clamps, profile sanitize
   - SC03 stream restart state
   - SC04 standard fire and clear commands
   Assertion checks:
   - no X/Z on control input
   - no X/Z on ADC data while valid
   - APB address/write data stable across setup/access
   - `pready_o` behavior
   - `pslverr_o == 0`
   - no X/Z on `prdata_o`

4. Support blocks smoke regression:
   ```bat
   run_modelsim_here.bat support --no-pause
   ```
   Bench/DO:
   - `sim/tb_support_blocks.sv`
   - `simulation/questa/run_support_blocks.do`
   Expected token:
   - `[SUPPORT] SUMMARY`
   Expected nội dung:
   - compile Errors: 0
   - Không có cảnh báo `Inferring latch` (chốt dữ liệu không mong muốn) hoặc `Combinational loop` (vòng lặp tổ hợp quẩn).
   - Không có cảnh báo `Metastability` hoặc vi phạm setup/hold nếu chạy gate-level/timing simulation.
   - Không có dòng nào chứa `Assertion error` hoặc `Assertion failure` trong transcript.
   - `FAIL=0`
   Scenarios:
   - rstgen smoke
   - clock gating smoke
   - generic FIFO smoke

5. APB peripherals smoke regression:
   ```bat
   run_modelsim_here.bat periph --no-pause
   ```
   Bench/DO:
   - `sim/tb_apb_peripherals.sv`
   - `simulation/questa/run_apb_peripherals.do`
   Expected token:
   - `[PERIPH] SUMMARY`
   Expected nội dung:
   - compile Errors: 0
   - Không có cảnh báo `Inferring latch` (chốt dữ liệu không mong muốn) hoặc `Combinational loop` (vòng lặp tổ hợp quẩn).
   - Không có cảnh báo `Metastability` hoặc vi phạm setup/hold nếu chạy gate-level/timing simulation.
   - Không có dòng nào chứa `Assertion error` hoặc `Assertion failure` trong transcript.
   - `FAIL=0`
   Scenarios:
   - GPIO smoke
   - UART smoke
   - Timer smoke

Standalone IP regressions cần chạy thêm nếu có `.do` trong từng IP package:
6. WDT IP standalone:
   - Bench: `ip/safety_watchdog/tb/tb_safety_watchdog_ip.sv`
   - Expected summary: `[WDT-IP] SUMMARY PASS=5 FAIL=0`
   - Scenarios:
     - SC01 reset defaults
     - SC02 enable/feed/counter decrements
     - SC03 lock mechanism
     - SC04 timeout → `wdt_reset_o`
     - SC05 disabled WDT holds counter
   - Nếu chưa có launcher target, tìm script trong `ip/safety_watchdog/scripts/` hoặc tạo command `vsim -c -do ...` theo filelist hiện có.
   - Nếu chưa có script, thử chạy mô phỏng thủ công ở chế độ CLI:
     ```bat
     vlib work
     vlog -sv -cover bces -work work ip/safety_watchdog/rtl/*.sv ip/safety_watchdog/tb/*.sv
     vsim -coverage -voptargs="+acc" -c -do "log -r /*; run -all; coverage save coverage_ip_wdt.ucdb; quit" tb_safety_watchdog_ip
     ```
   - Nếu chưa có script, báo “bench tồn tại nhưng chưa được nối vào launcher chính”.

7. BIST IP standalone:
   - Bench: `ip/logic_bist/tb/tb_logic_bist_ip.sv`
   - Expected summary: `[BIST-IP] SUMMARY PASS=5 FAIL=0`
   - Scenarios:
     - SC01 reset defaults
     - SC02 run BIST cycle
     - SC03 zero signature error flag
     - SC04 reset command
     - SC05 seed protection
   - Nếu chưa có launcher target, tìm script trong `ip/logic_bist/scripts/` hoặc tạo command `vsim -c -do ...` theo filelist hiện có.
   - Nếu chưa có script, thử chạy mô phỏng thủ công ở chế độ CLI:
     ```bat
     vlib work
     vlog -sv -cover bces -work work ip/logic_bist/rtl/*.sv ip/logic_bist/tb/*.sv
     vsim -coverage -voptargs="+acc" -c -do "log -r /*; run -all; coverage save coverage_ip_bist.ucdb; quit" tb_logic_bist_ip
     ```
   - Nếu chưa có script, báo “bench tồn tại nhưng chưa được nối vào launcher chính”.

8. SPI ADC Bridge IP standalone:
   - Bench: `ip/apb_spi_adc_bridge/tb/tb_apb_spi_adc_bridge_ip.sv`
   - Expected summary: `[SPI-IP] SUMMARY PASS=5 FAIL=0`
   - Scenarios:
     - SC01 reset defaults
     - SC02 capture sample from fake ADC
     - SC03 disable and re-enable
     - SC04 SPI signal integrity
     - SC05 stream restart detection
   - Nếu chưa có launcher target, tìm script trong `ip/apb_spi_adc_bridge/scripts/` hoặc tạo command `vsim -c -do ...` theo filelist hiện có.
   - Nếu chưa có script, thử chạy mô phỏng thủ công ở chế độ CLI:
     ```bat
     vlib work
     vlog -sv -cover bces -work work ip/apb_spi_adc_bridge/rtl/*.sv ip/apb_spi_adc_bridge/tb/*.sv
     vsim -coverage -voptargs="+acc" -c -do "log -r /*; run -all; coverage save coverage_ip_spi.ucdb; quit" tb_apb_spi_adc_bridge_ip
     ```
   - Nếu chưa có script, báo “bench tồn tại nhưng chưa được nối vào launcher chính”.

Cách thu log:
- Sau mỗi run, copy `transcript` sang thư mục log riêng, ví dụ:
  ```bat
  mkdir sim_logs
  copy transcript sim_logs\transcript_full.txt
  copy transcript sim_logs\transcript_dsp.txt
  copy transcript sim_logs\transcript_ip_dsp.txt
  copy transcript sim_logs\transcript_support.txt
  copy transcript sim_logs\transcript_periph.txt
  ```
- Nếu chạy IP standalone ngoài launcher, đặt tên tương ứng:
  - `transcript_ip_wdt.txt`
  - `transcript_ip_bist.txt`
  - `transcript_ip_spi.txt`
- Lưu báo cáo độ bao phủ nếu Questa có cấu hình code coverage / functional coverage:
  ```bat
  copy coverage_report.html sim_logs\coverage_full.html
  copy coverage.ucdb sim_logs\coverage_full.ucdb
  ```
- Nếu mỗi target sinh coverage riêng, đặt tên tương ứng:
  - `coverage_full.ucdb` / `coverage_full.html`
  - `coverage_dsp.ucdb` / `coverage_dsp.html`
  - `coverage_ip_dsp.ucdb` / `coverage_ip_dsp.html`
  - `coverage_support.ucdb` / `coverage_support.html`
  - `coverage_periph.ucdb` / `coverage_periph.html`
  - `coverage_ip_wdt.ucdb` / `coverage_ip_wdt.html`
  - `coverage_ip_bist.ucdb` / `coverage_ip_bist.html`
  - `coverage_ip_spi.ucdb` / `coverage_ip_spi.html`
- Thu thập file dạng sóng nếu có sinh ra sau mô phỏng:
  ```bat
  copy vsim.wlf sim_logs\waveform_full.wlf
  copy dump.vcd sim_logs\waveform_full.vcd
  ```
- Nếu mỗi target sinh waveform riêng, đặt tên tương ứng để tránh ghi đè:
  - `waveform_full.wlf` / `waveform_full.vcd`
  - `waveform_dsp.wlf` / `waveform_dsp.vcd`
  - `waveform_ip_dsp.wlf` / `waveform_ip_dsp.vcd`
  - `waveform_support.wlf` / `waveform_support.vcd`
  - `waveform_periph.wlf` / `waveform_periph.vcd`
  - `waveform_ip_wdt.wlf` / `waveform_ip_wdt.vcd`
  - `waveform_ip_bist.wlf` / `waveform_ip_bist.vcd`
  - `waveform_ip_spi.wlf` / `waveform_ip_spi.vcd`

Bảng báo cáo cần xuất:

| Target | Command | Bench | Expected summary | Result | Latch/Coverage Check | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| full | `run_modelsim_here.bat full --no-pause` | `sim/tb_professional.sv` | `EXTRA SCENARIOS 11-26 SUMMARY: PASS=16 FAIL=0 KNOWN_ISSUE=0` | PASS/FAIL | Latch: Yes/No; Coverage: Saved/NA | ... |
| dsp | `run_modelsim_here.bat dsp --no-pause` | `sim/tb_dsp_upgrades.sv` | `[DSP-UPG] SUMMARY PASS=9 FAIL=0` | PASS/FAIL | Latch: Yes/No; Coverage: Saved/NA | ... |
| ip_dsp | `run_modelsim_here.bat ip_dsp --no-pause` | `ip/dsp_arc_detect/tb/tb_dsp_arc_detect_ip.sv` | `[DSP-IP] SUMMARY PASS=4 FAIL=0` | PASS/FAIL | Latch: Yes/No; Coverage: Saved/NA | ... |
| support | `run_modelsim_here.bat support --no-pause` | `sim/tb_support_blocks.sv` | `[SUPPORT] SUMMARY ... FAIL=0` | PASS/FAIL | Latch: Yes/No; Coverage: Saved/NA | ... |
| periph | `run_modelsim_here.bat periph --no-pause` | `sim/tb_apb_peripherals.sv` | `[PERIPH] SUMMARY ... FAIL=0` | PASS/FAIL | Latch: Yes/No; Coverage: Saved/NA | ... |
| ip_wdt | custom/script | `ip/safety_watchdog/tb/tb_safety_watchdog_ip.sv` | `[WDT-IP] SUMMARY PASS=5 FAIL=0` | PASS/FAIL/NOT_RUN | Latch: Yes/No; Coverage: Saved/NA | launcher/script status |
| ip_bist | custom/script | `ip/logic_bist/tb/tb_logic_bist_ip.sv` | `[BIST-IP] SUMMARY PASS=5 FAIL=0` | PASS/FAIL/NOT_RUN | Latch: Yes/No; Coverage: Saved/NA | launcher/script status |
| ip_spi | custom/script | `ip/apb_spi_adc_bridge/tb/tb_apb_spi_adc_bridge_ip.sv` | `[SPI-IP] SUMMARY PASS=5 FAIL=0` | PASS/FAIL/NOT_RUN | Latch: Yes/No; Coverage: Saved/NA | launcher/script status |

Nếu lỗi xảy ra:
1. Dừng và phân loại lỗi:
   - compile error
   - missing include/file
   - missing library
   - `vsim` not found
   - assertion failure
   - `Assertion error` / `Assertion failure` trong transcript
   - runtime timeout
   - expected summary token missing
   - latch inference warning
   - combinational loop warning
   - timing/setup/hold warning nếu chạy gate-level/timing simulation
2. Trích 20-40 dòng lỗi quan trọng từ transcript.
3. Nếu lỗi xảy ra trong kịch bản có yếu tố ngẫu nhiên, BẮT BUỘC trích xuất SV Seed, thường in ở đầu transcript: `SV Seed for random number generator: <number>`.
4. Chỉ đề xuất sửa tối thiểu.
5. Không sửa RTL tự động nếu chưa được phép.

Kết luận cần viết:
- Tổng số target PASS/FAIL/NOT_RUN.
- Danh sách scenario đã chứng minh.
- Danh sách gap còn lại:
  - WDT chưa independent/windowed/cause retention.
  - BIST chưa on-chip golden compare/pass-fail thật.
  - SPI chưa FIFO/CDC/backpressure.
  - DSP chưa có latency/timing/resource/coverage closure package.
  - `top_soc.sv` có thể còn absolute include cần sửa để portable.
  - Chưa thực hiện logic synthesis và Static Timing Analysis (STA) trên Quartus/Vivado để xác nhận Fmax >= 50 MHz.
  - Chưa thực hiện gate-level simulation / post-synthesis simulation.
- Đề xuất bước tiếp:
  1. Sửa include portability nếu còn lỗi.
  2. Thêm target launcher cho `ip_wdt`, `ip_bist`, `ip_spi`.
  3. Lưu `sim_logs/` làm bằng chứng regression.
  4. Bổ sung latency measurement test cho DSP.
  5. Bổ sung documentation evidence table vào README/report.
  6. Đẩy project vào Quartus/Vivado, chạy synthesis để kiểm tra timing và resource utilization (LUTs, FFs, DSP blocks).
  7. Chạy STA để xác nhận Fmax >= 50 MHz và không có setup/hold violation.
  8. Nếu có netlist sau tổng hợp, chạy gate-level/post-synthesis simulation cho target quan trọng.
  9. Chuyển đổi toàn bộ quy trình regression và thu thập log này thành CI/CD config, ví dụ `.github/workflows/regression.yml` hoặc `.gitlab-ci.yml`, để chạy tự động mỗi khi có commit mới.
