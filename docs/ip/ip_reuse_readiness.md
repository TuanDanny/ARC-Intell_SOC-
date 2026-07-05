# IP Reuse Readiness - In_SOC

Status note - 2026-04-26:

The formal scope decision is now recorded in `docs/ip/ip_scope_and_rtl_alignment.md`.
This file remains a practical readiness note, but the scope document is the
source of truth for whether a block is a primary IP candidate, secondary IP
candidate, or reference/demo integration.

## 1. Diem da duoc cai thien

- Loi duong dan tuyet doi trong source/project chinh da duoc giam ro:
  - `rtl/top_soc.sv` da dung include tuong doi
  - `In_SOC.qsf` da dung `SEARCH_PATH` tuong doi
  - script mo phong trong `simulation/questa` da tu tim project root tu `pwd`
- Full regression hien tai van pass sau khi don portability:
  - `tb_professional`: scenario `1..10`, extra scenario `11..26`
  - `tb_dsp_upgrades`: DSP-focused scenario set `16..23` and `25`
- `dsp_arc_detect` da co package doc lap dau tien:
  - `ip/dsp_arc_detect/rtl/`
  - `ip/dsp_arc_detect/tb/`
  - `ip/dsp_arc_detect/docs/`
  - `ip/dsp_arc_detect/scripts/`
  - `ip/dsp_arc_detect/examples/`
- Standalone DSP IP regression co expected summary:
  - `[DSP-IP] SUMMARY PASS=4 FAIL=0`

## 2. Vi sao van bi danh gia "chua du reusable IP"

Nhan xet nay la hop ly, nhung nguyen nhan khong chi nam o duong dan tuyet doi.

Project hien tai manh theo huong **mini-system demo**:
- co `top_soc`
- co testbench he thong
- co mo phong tong

Nhung chua manh theo huong **IP catalog / reusable IP**:
- da co tai lieu rieng cho cac IP candidate chinh trong `docs/ip/`
- da co register map va interface notes cho cac block chinh
- `dsp_arc_detect` da co standalone IP package dau tien
- van chua co APB wrapper doc lap ngoai project-specific interface cho tat ca IP khac
- `dsp_arc_detect` da co assertion monitor co ban, nhung van chua co coverage/formal package kieu IP-grade
- van chua co latency/timing/resource report duoc dong goi rieng cho tung IP

## 3. Nhung file nao nen xem la "source can nop"

Nen giu:
- `rtl/`
- `sim/` (testbench hand-written)
- `simulation/questa/*.do`
- `In_SOC.qsf`
- `In_SOC.sdc`
- cac file tai lieu do an / spec

Khong nen xem la source core khi danh gia portability:
- `output_files/`
- `db/`
- `incremental_db/`
- `rtl_work*/`
- `sim/work/`
- `sim/*.mpf`
- `sim/*.cr.mti`
- `transcript`
- `script/output/`

Do la ly do repo nen co `.gitignore` ro rang.

## 4. Muc toi thieu de tra loi hoi dong gon va chac

Neu bi hoi "block nao la reusable IP?" thi co the tra loi:

- `dsp_arc_detect` la IP chinh dang duoc nang cap de tai su dung
- `safety_watchdog` la IP an toan co register map rieng
- `logic_bist` la IP tu kiem tra logic
- `apb_spi_adc_bridge` la bridge giao tiep, co the tach thanh peripheral IP

Neu bi hoi "tai lieu block nao tach rieng?" thi hien tai nen bo sung:

1. `docs/ip/dsp_arc_detect.md`
2. `docs/ip/safety_watchdog.md`
3. `docs/ip/logic_bist.md`
4. `docs/ip/apb_spi_adc_bridge.md`
5. `docs/ip/ip_scope_and_rtl_alignment.md`

Moi file nen co:
- muc dich IP
- port list
- register map
- reset behavior
- latency / handshake assumptions
- test cases chinh

## 5. Lo trinh de dua project tu mini-system sang reusable IP

### Phase A - Repo portable
- giu tat ca duong dan source o dang tuong doi
- bo file generated khoi repo bang `.gitignore`
- tach ro file "source" va file "tool artifact"

### Phase B - IP docs
- viet tai lieu rieng cho tung IP block
- chot register map on dinh
- viet interface assumptions ro rang

### Phase C - IP verification
- `dsp_arc_detect` da co bench rieng va regression pass/fail ro
- cac IP khac can them bench rieng
- can bo sung bang test plan / pass criteria day du hon
- can mo rong scenario regression cho tung tinh nang chinh

### Phase D - Packaging
- `dsp_arc_detect` da gom `rtl + docs + testbench + register map + assumptions`
- cac IP khac can duoc dong goi theo cung layout
- dat ten / version cho tung IP
- neu can, tao "ip catalog" nho trong project

## 6. Cach noi voi giao vien / interviewer

Mot cau tra loi ngan, chac:

> Ban dau do an duoc xay dung theo huong mini-system de chung minh toan bo luong hoat dong cua SoC. Hien tai em da don source theo huong portable hon, loai bo phu thuoc duong dan may ca nhan trong source chinh, va dang chuyen dan cac khoi quan trong nhu DSP, Watchdog, BIST thanh cac IP co register map, testbench va tai lieu tach rieng. Nghia la project da di tu "demo system" sang "reusable IP", nhung phan tai lieu IP catalog van la hang muc can bo sung de hoan chinh.

## 7. Ket luan thuc te

Neu hoi dong che "duong dan tuyet doi", thi ban co the noi:
- dung, do la diem yeu cua repo khi nop
- nhung da duoc sua trong source/project chinh
- phan con lai chu yeu la file generated cua tool va can duoc ignore, khong phai logic thiet ke cot loi

Neu hoi dong che "chua du reusable IP", thi ban co the noi:
- nhan xet do dung mot phan
- hien tai project da co IP candidate ro rang va `dsp_arc_detect` da co package doc lap dau tien
- buoc tiep theo la dong goi cac IP con lai, mo rong verification IP-grade, va luu timing/resource evidence
