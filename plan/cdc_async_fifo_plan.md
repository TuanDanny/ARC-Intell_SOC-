# CDC / Async FIFO Upgrade Plan for SPI ADC to DSP Path

## 1. Executive conclusion

Current RTL has **not yet solved the real Clock Domain Crossing (CDC) problem** described in the defense text.

The current design is functional as a system-clocked SPI master path, but it is **not** an independent `SCLK` domain to `clk_i` domain architecture. Therefore, current project must not claim that an asynchronous FIFO already protects SPI samples from metastability.

Correct current statement:

> In the present RTL, the SPI frontend is clocked by the system clock `clk_i`; `adc_sclk_o` is generated internally by dividing `clk_i`. The SPI bridge forwards `sample_data_o/sample_valid_o` directly into the DSP path. There is no real async FIFO CDC layer yet.

Target upgraded statement after implementation:

> ADC samples are captured in the SPI clock domain and written into an async FIFO. The DSP reads samples in the 50 MHz system clock domain. Gray-coded read/write pointers cross clock domains through 2-flop synchronizers. Full and empty are generated locally in their own clock domains. No multi-bit sample bus crosses domains directly.

---

## 2. Evidence from current RTL

### 2.1 `rtl/top_soc.sv`

Current top-level path:

```systemverilog
apb_spi_adc_bridge u_spi_bridge (
    .clk_i          (clk_i),
    .rst_ni         (rst_no),
    ...
    .sample_data_o  (spi_data_val),
    .sample_valid_o (spi_data_rdy),
    ...
);

assign dsp_data_in  = bist_active_mode ? bist_data  : spi_data_val;
assign dsp_valid_in = bist_active_mode ? bist_valid : spi_data_rdy;

dsp_arc_detect u_dsp (
    .clk_i       (clk_i),
    .adc_data_i  (dsp_data_in),
    .adc_valid_i (dsp_valid_in),
    ...
);
```

Finding:

- SPI bridge output is directly multiplexed into DSP input.
- No FIFO instance exists between SPI and DSP.
- No separate SPI write clock exists at `top_soc` boundary.

### 2.2 `rtl/periph/spi_master/apb_spi_adc_bridge.sv`

Current bridge instantiates SPI frontend with same `clk_i`:

```systemverilog
spi_adc_stream_rx u_spi_adc_rx (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    ...
    .sample_ready_i (1'b1),
    .sample_data_o  (frontend_sample_data),
    .sample_valid_o (frontend_sample_valid),
    ...
);

assign sample_data_o  = frontend_sample_data;
assign sample_valid_o = frontend_sample_valid;
```

Important existing comment in file:

```text
Because the downstream DSP path has no ready/backpressure handshake today,
frontend overrun remains a bridge/software telemetry event rather than a detector-side fault source.
```

Finding:

- `sample_ready_i` is tied to `1'b1`.
- There is no downstream backpressure contract.
- Live sample stream is forwarded directly.

### 2.3 `rtl/periph/spi_adc_stream_rx.sv`

Current frontend uses one clock:

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
    ...
    adc_sclk_o <= next_sclk;
    ...
    captured_word = capture_sample_bit(sample_shift_q, adc_miso_i, bit_pos_q);
    ...
end
```

Finding:

- `adc_sclk_o` is generated from `clk_i`.
- MISO sampling is controlled by `clk_i`-clocked FSM.
- This is a system-clocked SPI master, not an external independent `SCLK` capture domain.

### 2.4 `rtl/lib/generic_fifo.sv`

Current generic FIFO has one clock:

```systemverilog
module generic_fifo (
   input logic clk,
   input logic rst_n,
   ...
);
```

Finding:

- This FIFO is synchronous.
- It cannot solve CDC between two unrelated clocks.
- It can be used for buffering inside one domain only.

### 2.5 Documentation already admits limitation

Existing docs/plan contain matching limitation:

- `docs/ip/apb_spi_adc_bridge.md`: says no integrated FIFO buffering and no downstream ready/backpressure.
- `plan/dsp_plan.md`: says current RTL has no true FIFO/CDC and should add FIFO/CDC later.
- `plan/full_simulation_prompt.md`: warns not to claim FIFO/CDC/backpressure if RTL does not have it.

---

## 3. Root problem to solve

Defense text describes this physical problem:

```text
SPI receives data in SCLK domain.
DSP and CPU run in 50 MHz system clock domain.
Direct connection from SPI domain to DSP domain can cause metastability.
Async FIFO is used as CDC bridge.
```

To make RTL match that statement, design must have all of these:

1. A real SPI capture/write clock domain.
2. A real DSP/read clock domain.
3. An async FIFO with independent `wr_clk_i` and `rd_clk_i`.
4. Pointer crossing through synchronizers, not sample bus crossing directly.
5. Top-level integration showing FIFO between SPI and DSP.
6. Testbench proving data ordering and no false reads across unrelated clocks.

---

## 4. Architecture choices

### Option A: Keep current SPI master derived from system clock

Use when project wants minimum RTL change.

Architecture:

```text
clk_i 50 MHz
  ├─ SPI master FSM generates adc_sclk_o
  ├─ SPI sample_valid/sample_data
  ├─ optional synchronous FIFO
  └─ DSP consumes sample_valid
```

Result:

- No CDC exists between SPI frontend and DSP because all logic is in `clk_i` domain.
- Metastability claim must be removed.
- Add sync FIFO only for buffering/backpressure.

Defense wording for Option A:

> In this implementation, `adc_sclk_o` is generated by a system-clocked SPI master, so the SPI frontend and DSP are in the same clock domain. Therefore, a true CDC boundary does not exist in this version. We use controlled `sample_valid` timing and can add a synchronous FIFO for buffering, but not as a metastability CDC barrier.

### Option B: Implement real CDC async FIFO path

Use when project wants to support defense text exactly.

Architecture:

```text
External/independent SPI clock domain          System 50 MHz domain
------------------------------------          --------------------
adc_sclk_i / spi_wr_clk_i                     clk_i
spi_slave_or_capture_rx                       dsp_arc_detect
sample_word + sample_done                     fifo_rd_data + fifo_rd_valid
        │                                             ▲
        ▼                                             │
async FIFO write side  ── Gray pointer sync ── async FIFO read side
wr_clk_i, wr_valid_i                            rd_clk_i, rd_ready_i
```

Result:

- Real CDC solved.
- Defense statement becomes technically true.
- Needs new RTL and tests.

Recommended choice: **Option B**, because user defense text explicitly claims CDC problem and async FIFO solution.

---

## 5. Required RTL files

### 5.1 Add `rtl/lib/async_fifo_gray.sv`

Purpose: true dual-clock FIFO.

Proposed interface:

```systemverilog
module async_fifo_gray #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  wr_clk_i,
    input  logic                  wr_rst_ni,
    input  logic                  wr_valid_i,
    output logic                  wr_ready_o,
    input  logic [DATA_WIDTH-1:0] wr_data_i,

    input  logic                  rd_clk_i,
    input  logic                  rd_rst_ni,
    output logic                  rd_valid_o,
    input  logic                  rd_ready_i,
    output logic [DATA_WIDTH-1:0] rd_data_o,

    output logic                  full_o,
    output logic                  empty_o,
    output logic                  overflow_o,
    output logic                  underflow_o
);
```

Implementation requirements:

- Memory depth: `2**ADDR_WIDTH`.
- Binary write pointer and read pointer.
- Gray-coded write pointer and read pointer.
- 2-flop synchronizer for read pointer into write clock domain.
- 2-flop synchronizer for write pointer into read clock domain.
- `full_o` generated only in write clock domain.
- `empty_o` generated only in read clock domain.
- `wr_ready_o = !full_o`.
- `rd_valid_o = !empty_o`.
- Write occurs only when `wr_valid_i && wr_ready_o`.
- Read pointer increments only when `rd_valid_o && rd_ready_i`.
- `overflow_o` pulses or sticky flag when `wr_valid_i && full_o`.
- `underflow_o` pulses or sticky flag when `rd_ready_i && empty_o`.
- No combinational path between domains.

### 5.2 Add or modify SPI capture frontend

Current `spi_adc_stream_rx.sv` is a master generated from `clk_i`. To create true CDC, add new module:

`rtl/periph/spi_adc_sclk_capture_rx.sv`

Proposed purpose:

- Capture ADC serial bits using `spi_sclk_i`/`adc_sclk_i` domain.
- Generate one-cycle `sample_valid_o` in `spi_sclk_i` domain when 16-bit sample is complete.
- Output sample word to FIFO write side.

Proposed interface:

```systemverilog
module spi_adc_sclk_capture_rx #(
    parameter int SAMPLE_WIDTH = 16,
    parameter bit CPOL = 1'b0,
    parameter bit CPHA = 1'b0,
    parameter bit MSB_FIRST = 1'b1
) (
    input  logic                    spi_clk_i,
    input  logic                    spi_rst_ni,
    input  logic                    spi_csn_i,
    input  logic                    spi_miso_i,
    output logic [SAMPLE_WIDTH-1:0] sample_data_o,
    output logic                    sample_valid_o
);
```

If project must remain SPI master, then an alternate design can expose internal sample-complete pulses into an async FIFO with `wr_clk_i=clk_i`, but that is not real CDC. Prefer external/independent `spi_clk_i` for real CDC demonstration.

### 5.3 Add bridge wrapper `rtl/periph/spi_master/spi_adc_cdc_bridge.sv`

Purpose: bind capture frontend and async FIFO.

Proposed interface:

```systemverilog
module spi_adc_cdc_bridge #(
    parameter int SAMPLE_WIDTH = 16,
    parameter int FIFO_ADDR_WIDTH = 4
) (
    input  logic                    spi_clk_i,
    input  logic                    spi_rst_ni,
    input  logic                    spi_csn_i,
    input  logic                    spi_miso_i,

    input  logic                    sys_clk_i,
    input  logic                    sys_rst_ni,
    output logic [SAMPLE_WIDTH-1:0] sys_sample_data_o,
    output logic                    sys_sample_valid_o,
    input  logic                    sys_sample_ready_i,

    output logic                    fifo_full_o,
    output logic                    fifo_empty_o,
    output logic                    fifo_overflow_o,
    output logic                    fifo_underflow_o
);
```

Mapping:

```text
spi_adc_sclk_capture_rx.sample_valid_o -> async_fifo_gray.wr_valid_i
spi_adc_sclk_capture_rx.sample_data_o  -> async_fifo_gray.wr_data_i
async_fifo_gray.rd_data_o              -> DSP sample data
async_fifo_gray.rd_valid_o             -> DSP sample valid
DSP sample consume                     -> async_fifo_gray.rd_ready_i
```

### 5.4 Modify `rtl/top_soc.sv`

If Option B is selected, add input ports:

```systemverilog
input logic adc_sclk_i,
input logic adc_csn_i,
```

Or reuse existing output pins only if system remains SPI master. For true external SCLK CDC, top-level must receive independent SPI clock.

Insert CDC bridge before BIST mux:

```systemverilog
logic [15:0] cdc_sample_data;
logic        cdc_sample_valid;
logic        cdc_sample_ready;
logic        cdc_fifo_full;
logic        cdc_fifo_empty;
logic        cdc_fifo_overflow;
logic        cdc_fifo_underflow;

assign cdc_sample_ready = cdc_sample_valid && !bist_active_mode;

spi_adc_cdc_bridge u_spi_cdc_bridge (
    .spi_clk_i            (adc_sclk_i),
    .spi_rst_ni           (rst_no),
    .spi_csn_i            (adc_csn_i),
    .spi_miso_i           (adc_miso_i),
    .sys_clk_i            (clk_i),
    .sys_rst_ni           (rst_no),
    .sys_sample_data_o    (cdc_sample_data),
    .sys_sample_valid_o   (cdc_sample_valid),
    .sys_sample_ready_i   (cdc_sample_ready),
    .fifo_full_o          (cdc_fifo_full),
    .fifo_empty_o         (cdc_fifo_empty),
    .fifo_overflow_o      (cdc_fifo_overflow),
    .fifo_underflow_o     (cdc_fifo_underflow)
);

assign dsp_data_in  = bist_active_mode ? bist_data  : cdc_sample_data;
assign dsp_valid_in = bist_active_mode ? bist_valid : cdc_sample_valid;
```

Important integration rule:

- If DSP has no `ready_o`, use `rd_ready_i = rd_valid_o` to consume each valid sample in one system clock cycle.
- If later DSP adds stall support, connect real `dsp_ready_o`.

### 5.5 Modify `apb_spi_adc_bridge.sv` or keep separate

Two integration styles:

1. Minimal risk: keep current `apb_spi_adc_bridge.sv` for existing tests, add new `spi_adc_cdc_bridge.sv` path as optional top-level architecture.
2. Bigger change: integrate async FIFO into `apb_spi_adc_bridge.sv` and add APB status registers.

Recommended for project stability: **style 1 first**, then merge APB status later.

---

## 6. APB/status register plan

If async FIFO is integrated into APB bridge, extend status map:

Existing:

```text
0x00 CTRL
0x04 STATUS
0x08 CMD
0x0C SAMPLE
0x10 COUNT
0x14 INFO
```

Proposed `STATUS` bits:

```text
bit 0  enable
bit 1  continuous
bit 2  frontend_busy
bit 3  frame_active
bit 4  sample_valid_sticky
bit 5  sample_overwrite_sticky
bit 6  frontend_overrun_sticky
bit 7  fifo_full
bit 8  fifo_empty
bit 9  fifo_overflow_sticky
bit 10 fifo_underflow_sticky
bit 11 cdc_mode_enabled
```

Proposed new register:

```text
0x18 FIFO_STATUS
  [7:0]   fifo_wr_level estimate or write count low
  [15:8]  fifo_rd_level estimate or read count low
  [16]    full
  [17]    empty
  [18]    overflow_sticky
  [19]    underflow_sticky
```

If exact FIFO level across domains is not implemented, use monotonic write/read counters synchronized separately or omit level. Do not expose unsafe multi-bit level crossing directly.

---

## 7. Verification plan

### 7.1 Unit test: async FIFO only

Add:

`sim/tb_cdc_async_fifo.sv`

Test clocks:

```systemverilog
// Example only
always #7  wr_clk = ~wr_clk; // ~71.4 MHz
always #10 rd_clk = ~rd_clk; // 50 MHz
```

Test cases:

1. Reset both domains.
2. Write 32 incremental samples, read continuously.
3. Write clock faster than read clock.
4. Read clock faster than write clock.
5. Random write/read enables.
6. Fill FIFO to full, verify `full_o` and `wr_ready_o=0`.
7. Force write when full, verify `overflow_o`.
8. Empty FIFO, verify `empty_o` and `rd_valid_o=0`.
9. Force read when empty, verify `underflow_o`.
10. Reset write domain while read domain running.
11. Reset read domain while write domain running.

Scoreboard:

```text
expected_queue.push_back(wr_data)
on read: compare rd_data_o == expected_queue.pop_front()
```

Pass criteria:

```text
PASS: no data mismatch
PASS: no X on rd_data_o when rd_valid_o=1
PASS: full/empty behavior correct
PASS: overflow/underflow flags correct
PASS: simulation ends with FAIL=0
```

### 7.2 Unit test: SPI capture to async FIFO

Add:

`sim/tb_spi_cdc_bridge.sv`

Test cases:

1. Drive independent `spi_clk` and `sys_clk`.
2. Send sample sequence over SPI: `16'h1234`, `16'hBEEF`, `16'hCAFE`, `16'h55AA`.
3. Verify system side emits same order through `sys_sample_valid_o`.
4. Stall read side for several system cycles, verify FIFO buffers.
5. Overrun FIFO intentionally, verify overflow flag.
6. Run with phase-shifted clocks.

Pass criteria:

```text
CDC bridge sample order preserved
No duplicate sample
No dropped sample unless overflow intentionally caused
Overflow flag only in overflow test
No X propagation to DSP input
```

### 7.3 Full SoC test

Modify or add:

`sim/tb_soc_cdc_path.sv`

Test cases:

1. BIST inactive, SPI CDC source feeds DSP.
2. DSP `adc_valid_i` pulses only when async FIFO has complete sample.
3. BIST active, BIST mux overrides CDC path.
4. BIST inactive again, CDC path resumes.
5. Arc sample sequence through CDC path triggers DSP IRQ.

Pass criteria:

```text
DSP receives complete 16-bit samples only
DSP does not evaluate partial SPI words
IRQ behavior same as direct path for same sample sequence
BIST mux still works
```

---

## 8. Simulation scripts

Add Questa script:

`simulation/questa/run_cdc_fifo.do`

Suggested compile order:

```tcl
vlib work
vlog -sv rtl/lib/async_fifo_gray.sv
vlog -sv sim/tb_cdc_async_fifo.sv
vsim -c tb_cdc_async_fifo -do "run -all; quit"
```

Add bridge script:

`simulation/questa/run_spi_cdc_bridge.do`

Suggested compile order:

```tcl
vlib work
vlog -sv rtl/lib/async_fifo_gray.sv
vlog -sv rtl/periph/spi_adc_sclk_capture_rx.sv
vlog -sv rtl/periph/spi_master/spi_adc_cdc_bridge.sv
vlog -sv sim/tb_spi_cdc_bridge.sv
vsim -c tb_spi_cdc_bridge -do "run -all; quit"
```

Optional batch wrapper:

`run/scripts/run_cdc_regression.bat`

Expected command:

```bat
vsim -c -do simulation/questa/run_cdc_fifo.do
vsim -c -do simulation/questa/run_spi_cdc_bridge.do
```

---

## 9. CDC sign-off checklist

Implementation must satisfy:

- [ ] No direct multi-bit sample bus from SPI clock domain to system clock domain.
- [ ] Only Gray-coded pointers cross FIFO domains.
- [ ] Pointer crossings use 2-flop synchronizers.
- [ ] Full flag generated in write clock domain.
- [ ] Empty flag generated in read clock domain.
- [ ] Async reset release is safe or synchronized per domain.
- [ ] No combinational feedback between domains.
- [ ] DSP consumes only `rd_valid_o` samples.
- [ ] FIFO overflow cannot silently corrupt already queued samples.
- [ ] Testbench uses unrelated clocks, not same-clock shortcut.
- [ ] Simulation has `FAIL=0` for async FIFO and SPI CDC bridge.
- [ ] Documentation wording updated to match actual RTL.

---

## 10. Concrete output deliverables

After implementation, project should contain:

```text
rtl/lib/async_fifo_gray.sv
rtl/periph/spi_adc_sclk_capture_rx.sv
rtl/periph/spi_master/spi_adc_cdc_bridge.sv
sim/tb_cdc_async_fifo.sv
sim/tb_spi_cdc_bridge.sv
simulation/questa/run_cdc_fifo.do
simulation/questa/run_spi_cdc_bridge.do
run/scripts/run_cdc_regression.bat
docs/cdc_async_fifo.md
```

RTL top integration choices:

```text
Option A deliverable:
- no real CDC claim
- optional synchronous FIFO/backpressure only

Option B deliverable:
- top-level CDC bridge integrated before DSP
- true async FIFO CDC claim allowed
```

Expected verification output:

```text
[CDC-FIFO] PASS: reset behavior
[CDC-FIFO] PASS: write faster than read
[CDC-FIFO] PASS: read faster than write
[CDC-FIFO] PASS: random phase/order preserved
[CDC-FIFO] PASS: full/overflow behavior
[CDC-FIFO] PASS: empty/underflow behavior
[CDC-FIFO] SUMMARY: PASS=6 FAIL=0

[SPI-CDC] PASS: samples preserved 1234 BEEF CAFE 55AA
[SPI-CDC] PASS: FIFO stall buffering
[SPI-CDC] PASS: overflow flag
[SPI-CDC] PASS: no X on DSP-facing stream
[SPI-CDC] SUMMARY: PASS=4 FAIL=0
```

---

## 11. Correct defense wording

### Before CDC implementation

Use this wording:

> Ở phiên bản RTL hiện tại, SPI ADC là master do hệ thống sinh `adc_sclk_o` từ `clk_i`, nên SPI frontend và DSP vẫn nằm trong cùng miền clock hệ thống. Vì vậy em chưa tuyên bố đã có async FIFO CDC thật. Điểm còn thiếu là tách miền SPI clock độc lập và đưa dữ liệu qua async FIFO Gray-pointer.

Avoid this wording:

> Em đã dùng `generic_fifo.sv` làm async FIFO để chống metastability giữa SPI SCLK và DSP 50 MHz.

Reason:

- `generic_fifo.sv` is synchronous one-clock FIFO.
- It does not protect CDC.

### After CDC implementation

Use this wording:

> Dữ liệu ADC được chốt trong miền SPI clock và chỉ đi sang miền system clock qua async FIFO. FIFO dùng write/read pointer mã Gray, mỗi pointer được đồng bộ qua 2 flip-flop trước khi tính full/empty. DSP chỉ nhận `sample_valid` ở miền 50 MHz sau khi FIFO xác nhận có đủ một mẫu 16-bit hoàn chỉnh. Vì vậy không có bus dữ liệu SPI nối thẳng sang DSP, giảm nguy cơ metastability ở biên clock.

---

## 12. Recommended execution order

1. Add `async_fifo_gray.sv`.
2. Add `tb_cdc_async_fifo.sv` and pass FIFO tests.
3. Add `spi_adc_sclk_capture_rx.sv`.
4. Add `spi_adc_cdc_bridge.sv`.
5. Add `tb_spi_cdc_bridge.sv` and pass bridge tests.
6. Integrate into `top_soc.sv` behind a parameter or separate top variant.
7. Add APB status bits for FIFO flags.
8. Update docs to remove old limitation.
9. Run full regression.
10. Archive transcript showing `PASS=... FAIL=0`.

---

## 13. Risk notes

- Async FIFO must not use `generic_fifo.sv`; that module is single-clock.
- Exact FIFO occupancy across domains is non-trivial; avoid unsafe multi-bit level crossing.
- External `adc_sclk_i` top-level port changes board/interface assumptions.
- Existing tests may assume `adc_sclk_o` master behavior; keep old bridge until new CDC path is validated.
- If staying with SPI master generated from `clk_i`, claim should be about synchronous design discipline, not CDC metastability protection.

---

## 14. Final decision

Current system: **CDC tử huyệt chưa được khắc phục bằng FIFO bất đồng bộ**.

Recommended fix: implement **Option B real async FIFO CDC path** if defense narrative must say SPI SCLK and DSP 50 MHz are separate domains.

Minimum safe communication now: state clearly that current SPI path is same-domain and CDC upgrade is planned.
