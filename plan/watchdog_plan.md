WATCHDOG DEVELOPMENT PLAN
Project: In_SOC
Date: 2026-04-02

STATUS NOTE - 2026-04-26

This file is a historical development plan for a stronger Watchdog v2. It
should not be read as completed RTL. The current RTL is still a basic
APB-configurable watchdog with magic feed, lock, timeout, and reset-request
generation. Independent clocking, windowed feed behavior, retained fault cause,
safe lockout, BIST rerun, and manual acknowledge remain future work unless
implemented later.

For the current IP scope and RTL-aligned claims, use:
  docs/ip/ip_scope_and_rtl_alignment.md
  docs/ip/safety_watchdog.md

1. KET LUAN NHANH

- Watchdog hien tai moi dat muc watchdog co ban:
  enable + timeout + magic feed pattern + lock + reset pulse.
- So voi bai bao, cac phan con thieu lon nhat la:
  independent watchdog clock, windowed watchdog, sticky fault cause,
  safe lockout sau WDT reset, va luong BIST + manual acknowledge.
- Muc tieu hop ly cho phien ban tiep theo la:
  Watchdog v2 = independent + windowed + hard reset + sticky cause
  + relay safe lockout + BIST re-check + manual ack.
- Phan vuot bai bao nen co them:
  pretimeout interrupt de CPU/UART kip ghi log truoc khi hard reset.

2. GAP ANALYSIS SO VOI BAI BAO

[1] Independent watchdog clock
- Bai bao noi gi:
  Watchdog phai chay bang nguon xung rieng, van hoat dong duoc khi
  main system clock bi treo.
- RTL hien co:
  safety_watchdog.sv dang dung clk_i cua he thong.
- Thieu gi:
  chua co cong wdt_clk_i, chua co clock domain rieng, chua co dong bo
  APB config sang watchdog domain.
- File can sua:
  rtl/periph/safety_watchdog.sv
  rtl/top_soc.sv
- Do kho:
  KHO

[2] Windowed watchdog
- Bai bao noi gi:
  Feed som cung phai bi coi la loi, feed muon cung la loi.
- RTL hien co:
  chi kiem tra dung magic pattern de nap lai counter.
- Thieu gi:
  chua co open window / closed window, chua co early_feed / late_feed.
- File can sua:
  rtl/periph/safety_watchdog.sv
- Do kho:
  TRUNG BINH

[3] Fault cause retention
- Bai bao noi gi:
  Khi watchdog kich hoat, phai luu nguyen nhan loi de phuc vu recovery.
- RTL hien co:
  khong co CAUSE register sticky; reset xong la mat thong tin.
- Thieu gi:
  can co status/cause va co che giu du lieu qua WDT reset.
- File can sua:
  rtl/periph/safety_watchdog.sv
  rtl/top_soc.sv
  co the tach them module moi: rtl/safety_manager.sv
- Do kho:
  KHO

[4] Hard reset path va pulse width
- Bai bao noi gi:
  Watchdog phai reset CPU/bus/DSP mot cach chac chan.
- RTL hien co:
  watchdog da co reset pulse, top-level da giu them mot khoang ngan.
- Thieu gi:
  can tach ro reset tree va phan retention, tranh reset sach ca phan
  luu fault cause.
- File can sua:
  rtl/periph/safety_watchdog.sv
  rtl/top_soc.sv
- Do kho:
  TRUNG BINH

[5] Safe relay lockout sau WDT reset
- Bai bao noi gi:
  Sau khi watchdog reset, relay phai o trang thai an toan va khong tu
  dong dong lai.
- RTL hien co:
  relay hien chi bi ep an toan trong luc reset.
- Thieu gi:
  chua co safe_lockout sticky sau reset.
- File can sua:
  rtl/top_soc.sv
  co the tach them module moi: rtl/safety_manager.sv
- Do kho:
  KHO

[6] BIST rerun + manual acknowledge
- Bai bao noi gi:
  Sau WDT reset phai chay lai BIST va doi nguoi van hanh xac nhan.
- RTL hien co:
  BIST va watchdog dang tach roi; CPU ROM chua co luong recovery.
- Thieu gi:
  thieu lien ket WDT -> BIST -> manual_ack -> relay enable.
- File can sua:
  rtl/top_soc.sv
  rtl/periph/logic_bist.sv
  rtl/core/cpu_8bit.sv
- Do kho:
  RAT KHO

[7] CPU/software servicing protocol
- Bai bao noi gi:
  CPU phai cau hinh va feed watchdog dung cach, dong thoi xu ly recovery.
- RTL hien co:
  ROM hien tai chua cau hinh hay feed watchdog.
- Thieu gi:
  thieu boot flow, thieu luong doc fault cause, thieu recovery path.
- File can sua:
  rtl/core/cpu_8bit.sv
- Do kho:
  KHO

[8] Verification
- Bai bao noi gi:
  Kich ban mo phong phai chung minh watchdog hoat dong dung trong cac
  tinh huong loi thuc te.
- RTL hien co:
  testbench chu yeu force noi tang r_enable / r_counter.
- Thieu gi:
  chua test APB path, chua test early/late feed, chua test clock hang,
  chua test safe lockout, chua test BIST/manual_ack.
- File can sua:
  sim/tb_professional.sv
  sim/tb.sv
- Do kho:
  TRUNG BINH

3. KIEN TRUC DE XUAT CHO WATCHDOG V2

- Module trung tam van la safety_watchdog.sv nhung can nang cap:
  + input: wdt_clk_i
  + output: wdt_reset_o, pretimeout_irq_o, fault_latched_o
  + register map: CTRL, TIMEOUT, WINDOW_MIN, WINDOW_MAX, FEED,
    STATUS, CAUSE, PRETIMEOUT
- Nen them mot lop policy o top-level hoac module rieng safety_manager:
  + giu fault cause qua WDT reset
  + giu safe_lockout
  + chan relay cho den khi BIST pass + manual ack
- CPU chi nen dong vai tro dieu phoi va hien thi trang thai;
  safety policy quan trong khong nen phu thuoc hoan toan vao CPU.

4. NHUNG VIEC CAN LAM CU THE

[A] Nang cap IP watchdog
- Them wdt_clk_i.
- Them state machine cho windowed operation.
- Them cause code:
  0 = none
  1 = timeout
  2 = early_feed
  3 = late_feed
  4 = illegal_config
- Them STATUS:
  enable, locked, window_open, pretimeout, expired, fault_latched.
- Them PRETIMEOUT threshold va pretimeout_irq_o.
- Dam bao lock cover tat ca thanh ghi quan trong.

[B] Xu ly retention va safe lockout
- Tao sticky register last_fault_cause.
- Tao sticky bit wdt_fault_latched.
- Tao sticky bit safe_lockout.
- Chi clear bang external reset hoac manual clear co kiem soat.
- Relay enable chi hop le khi:
  bist_pass = 1 AND manual_ack = 1 AND wdt_fault_latched = 0.

[C] Tich hop voi BIST
- Sau WDT reset, mac dinh relay giu OFF.
- CPU hoac safety manager trigger BIST.
- Neu BIST fail: tiep tuc lockout.
- Neu BIST pass: cho manual_ack.
- Chi sau manual_ack moi duoc re-arm relay.

[D] Nang cap CPU ROM
- Boot binh thuong:
  config watchdog, bat watchdog, feed theo chu ky hop le.
- Boot sau WDT reset:
  doc CAUSE, thong bao loi, trigger BIST, doi manual_ack.
- Khong cho CPU tu dong dong relay lai ngay sau reset.

[E] Nang cap verification
- Bo thoi quen force noi tang watchdog lam duong chinh.
- Tat ca bai test quan trong phai di qua APB path that.
- Them monitor cho:
  STATUS, CAUSE, relay output, BIST result, manual ack gating.

5. KE HOACH THUC HIEN THEO GIAI DOAN

PHASE 0 - DOC, CHOT SPEC, VE SO DO
- Muc tieu:
  chot lai dung spec can dat truoc khi code.
- Cong viec:
  ve register map, state machine, reset tree, safety policy.
- Dau ra:
  1 ban spec nho cho Watchdog v2.

PHASE 1 - SUA safety_watchdog.sv
- Muc tieu:
  bien watchdog co ban thanh independent windowed watchdog.
- Cong viec:
  them clock rieng, window logic, status/cause, pretimeout.
- Dau ra:
  module watchdog moi compile sach trong ModelSim.

PHASE 2 - SUA top_soc.sv / THEM safety_manager
- Muc tieu:
  dua watchdog thanh co che fail-safe cap he thong.
- Cong viec:
  tao safe_lockout, relay gating, sticky cause, reset policy.
- Dau ra:
  relay khong the tu dong dong lai sau WDT reset.

PHASE 3 - SUA cpu_8bit.sv
- Muc tieu:
  tao luong boot va recovery dung theo safety flow.
- Cong viec:
  config/feed watchdog, doc cause, trigger BIST, cho manual ack.
- Dau ra:
  CPU co duong di ro rang cho normal mode va recovery mode.

PHASE 4 - SUA TESTBENCH
- Muc tieu:
  kiem tra lai toan bo bang path su dung that.
- Cong viec:
  viet scenario normal feed, no feed, early feed, late feed,
  locked config, main clock stop, WDT reset, BIST rerun, manual ack.
- Dau ra:
  bo regression moi phan anh dung safety behavior.

PHASE 5 - TONG HOP VA DANH GIA
- Muc tieu:
  dam bao thiet ke co the duy tri va mo rong.
- Cong viec:
  review naming, comment, register map, warning, synthesis risk.
- Dau ra:
  Watchdog v2 on dinh, de hoc, de mo rong.

6. THU TU UU TIEN THUC TE

1. Sua safety_watchdog.sv truoc.
2. Sua top_soc.sv va them safety_manager.
3. Noi WDT voi BIST va relay policy.
4. Sua CPU ROM de phu hop flow moi.
5. Mo rong testbench va regression.

7. CHECKLIST TEST CAN CO

[ ] Feed dung cua so -> khong reset.
[ ] Khong feed -> timeout reset.
[ ] Feed qua som -> early_feed reset.
[ ] Feed qua muon -> late_feed reset.
[ ] Lock xong thi khong doi duoc timeout/window.
[ ] Main clk dung nhung wdt_clk_i van chay -> watchdog van bao loi.
[ ] Sau WDT reset relay van OFF.
[ ] BIST fail -> khong cho re-arm.
[ ] BIST pass nhung chua manual_ack -> van khong cho re-arm.
[ ] BIST pass + manual_ack -> moi cho phep re-arm.
[ ] CAUSE va fault_latched ton tai dung qua chu ky reset mong muon.

8. 3 NGUYEN TAC QUAN TRONG DE NHO

- Watchdog muon bat duoc loi treo clock thi no khong duoc song chung
  bang chinh clock dang bi giam sat.
- Thanh ghi ghi nguyen nhan reset khong duoc nam trong cung reset tree
  voi reset ma no dang ghi nhan.
- Chuc nang giu relay an toan khong nen phu thuoc hoan toan vao CPU vua
  bi crash; no phai co lop bao ve phan cung o top-level.

9. FILE UU TIEN CAN DOC / SUA

- rtl/periph/safety_watchdog.sv
- rtl/top_soc.sv
- rtl/core/cpu_8bit.sv
- rtl/periph/logic_bist.sv
- sim/tb_professional.sv
- sim/tb.sv

KET QUA MONG MUON CUOI CUNG

- Watchdog dat muc bai bao mo ta:
  independent + windowed + hard reset + safe recovery.
- He thong sau WDT reset van giu relay OFF.
- Muon cap dien lai phai qua BIST va manual acknowledge.
- Verification du manh de ban co the tiep tuc nghien cuu sau nay.
