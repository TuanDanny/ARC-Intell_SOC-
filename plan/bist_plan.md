BIST DEVELOPMENT PLAN
Project: In_SOC
Date: 2026-04-02

STATUS NOTE - 2026-04-26

This file is a historical development plan for a stronger BIST v1.5. It
should not be read as completed RTL. The current RTL is a functional BIST
helper with LFSR stimulus, MISR signature capture, APB control/status, and DSP
path injection. On-chip golden signature compare and explicit pass/fail status
remain future work unless implemented later.

For the current IP scope and RTL-aligned claims, use:
  docs/ip/ip_scope_and_rtl_alignment.md
  docs/ip/logic_bist.md

1. KET LUAN NHANH

- BIST hien tai KHONG te, va cung khong phai "vo dung".
- No da co nhung thanh phan loi dung huong:
  LFSR pattern generator + MISR signature + mux bom mau vao DSP
  + co the phan biet mach tot va mach loi trong testbench.
- Tuy nhien, neu doi chieu voi bai bao thi BIST hien tai van moi o muc:
  Functional BIST demo, chua phai Logic BIST hoan chinh nhu hinh mo ta.
- Vi ban khong muon nghien cuu sau vao BIST, minh de xuat muc tieu hop ly la:
  BIST v1.5 / "du dung":
  co golden signature on-chip, co pass/fail that, co status ro rang,
  co restart dung, co testbench du tin cay.
- KET LUAN VE UU TIEN:
  BIST CAN sua mot vai diem, nhung KHONG nen uu tien hon WATCHDOG va DSP.
  Lam gon, chac, dung y bai bao la du.

2. NHUNG GI BIST HIEN TAI LAM TOT

- Da co PRPG dua tren LFSR:
  tao pattern gia de kich thich DSP.
- Da co MISR:
  nen dap ung DSP thanh signature 16-bit.
- Da co APB register map:
  CTRL / CONFIG / SEED / SIGNATURE / STATUS.
- Da co mux o top-level:
  BIST co the tach ADC that, dua pattern vao DSP.
- Da co co che che irq CPU khi BIST dang chay:
  tranh bao dong gia len CPU trong luc test.
- Testbench da chung minh mot dieu quan trong:
  fault signature co the khac golden signature.

3. NHUNG DIEM CHUA HAY / CHUA DAT SO VOI BAI BAO

[1] Chua co golden signature on-chip
- Bai bao mo ta:
  signature phai duoc so sanh voi gia tri mau luu san trong ROM.
- RTL hien tai:
  chi xuat r_signature ra APB.
- Golden signature hien dang nam trong testbench, khong nam trong chip.
- Nghia la pass/fail that su van dang do testbench quyet dinh.

[2] "Mismatch" hien tai chua phai mismatch that
- Comment STATUS noi co bit Mismatch.
- RTL hien tai lai gan loi theo dieu kien:
  r_signature == 16'h0000
- Dieu nay KHONG giong y nghia "signature khac golden".
- Day la diem can sua som nhat.

[3] Restart flow chua dep
- Neu dang o COMPLETE ma ghi START moi,
  FSM chi quay ve IDLE roi dung lai.
- Nghia la START trong COMPLETE khong thuc su restart ngay test moi.
- De dung va de dung cho nguoi moi, START nen co hanh vi ro rang:
  reset noi bo + vao RUN.

[4] BIST chi quan sat 1-bit dsp_irq_i
- Bai bao nghieng ve logic BIST / signature analysis tren "processing core".
- RTL hien tai chi nen 1 bit irq_arc_o cua DSP.
- Cach nay van co gia tri, nhung fault coverage se han che.
- Nhieu loi noi tang trong DSP co the khong phan anh len irq.

[5] Chua co PASS / FAIL bit dung nghia
- Hien STATUS moi co:
  Busy, Done, s_bist_error.
- Chua co:
  pass, fail, signature_valid, compare_valid.
- Khi doc APB, nguoi dung van phai tu dien giai.

[6] Chua co integration that su voi CPU / boot flow
- CPU ROM hien tai khong goi BIST.
- He thong chua tu chay BIST sau reset hoac sau WDT reset.
- Dieu nay lech voi tinh than bai bao.

[7] Chua xuat trang thai BIST ra ngoai dung nhu comment top-level
- Top-level comment ghi GPIO[3] la BIST status.
- Thuc te chua co day nao buoc BIST pass/fail vao GPIO[3].

[8] Verification chua di qua duong APB that cua he thong
- Testbench dang force truc tiep vao u_bist.paddr_i, pwrite_i...
- Nghia la no test duoc logic BIST, nhung chua test that duong CPU/APB interconnect.
- Van dung cho do an, nhung chua dep neu muon noi "he thong da verify hoan chinh".

4. CAC FILE QUAN TRONG CAN DOC / SUA

- rtl/periph/logic_bist.sv
- rtl/top_soc.sv
- rtl/core/cpu_8bit.sv
- sim/tb.sv
- sim/tb_professional.sv

5. DANH GIA CHI TIET TUNG FILE

[A] rtl/periph/logic_bist.sv
- Day la noi can sua nhieu nhat.
- Viec can lam:
  + them golden signature storage
  + them comparator pass/fail
  + sua meaning cua STATUS
  + sua restart behavior
  + giu seed/test_len robust

[B] rtl/top_soc.sv
- Day la noi BIST noi vao DSP va CPU.
- Viec can lam:
  + noi BIST status ra GPIO[3] neu muon dung nhu comment
  + giu mux DSP/BIST ro rang
  + can nhac them cờ top-level cho BIST pass/fail

[C] rtl/core/cpu_8bit.sv
- Hien tai CPU biet dia chi BIST nhung khong dung.
- Neu muon dat muc bai bao vua phai:
  CPU nen co it nhat 1 flow goi BIST sau WDT reset hoac sau boot.
- Neu ban muon scope nho:
  co the tam chua sua CPU, nhung can ghi ro day la no thong.

[D] sim/tb.sv va sim/tb_professional.sv
- Testbench hien tai da co gia tri thuc te.
- Viec can lam:
  + them test cho PASS/FAIL on-chip
  + them test cho restart
  + them test cho clear status
  + neu duoc, them 1 bai test di qua APB that cua CPU

6. BIST HIEN TAI CO LOI BUG HAY KHONG

Co 4 diem minh xem la can sua:

[1] Mismatch logic sai y nghia
- Hien tai loi duoc gan khi signature bang 0.
- Day khong phai cach so sanh voi golden signature.
- Day la loi "dinh nghia chuc nang", khong phai loi compile.

[2] START khi COMPLETE khong restart dep
- Hanh vi nay de gay nham cho nguoi dung va testbench.
- Nen sua de START trong COMPLETE co the vao RUN truc tiep,
  hoac reset noi bo roi bat dau lai ngay.

[3] Golden signature dang nam ngoai chip
- Ve mat kien truc, day la thieu sot lon nhat so voi bai bao.
- BIST hien gio chua the tu danh gia PASS/FAIL neu khong co testbench.

[4] Status con ngheo
- Busy/Done la chua du.
- Can co PASS/FAIL ro rang de software va top-level de doc.

7. NHUNG DIEM KHONG CAN DAO QUA SAU

- Khong can nhay ngay sang full scan-LBIST.
- Khong can mo rong BIST thanh DFT nghiep vu lon.
- Khong can quan sat qua nhieu node noi tang DSP o giai doan nay.
- Khong can toi uu area/power cho BIST som.
- Khong can them qua nhieu mode test neu muc tieu la "du dung".

8. MUC TIEU HOP LY CHO BIST v1.5

Day la muc tieu minh de xuat cho ban:

- BIST van giu kien truc hien tai:
  LFSR -> DSP input -> MISR -> compare
- Them 1 gia tri golden signature nam trong chip:
  co the la register APB hoac constant ROM-like.
- STATUS ro rang:
  busy, done, pass, fail.
- Cho phep software clear / reset.
- START o moi trang thai phai co hanh vi de doan.
- Top-level co the xuat BIST status co ban.
- Testbench kiem tra duoc:
  golden path, faulty path, restart path.

Neu lam du nhu tren thi BIST da du de bao cao, du de hoc, du de dung.

9. KIEN TRUC DE XUAT

[A] Register map de xuat
- 0x00 CTRL
  bit0 start
  bit1 reset_logic
  bit2 clear_status
- 0x04 CONFIG
  test_len
- 0x08 SEED
  lfsr seed
- 0x0C SIGNATURE
  observed signature
- 0x10 GOLDEN
  golden signature expected
- 0x14 STATUS
  bit0 busy
  bit1 done
  bit2 pass
  bit3 fail
  bit4 signature_valid

[B] Compare policy de xuat
- Khi test hoan tat:
  observed_signature == golden_signature -> PASS
  observed_signature != golden_signature -> FAIL
- Neu golden_signature chua duoc nap:
  co the bao signature_valid = 0 hoac FAIL_SAFE.

[C] Restart policy de xuat
- Neu START duoc ghi:
  reset internal lfsr/misr/counter/status
  vao RUN ngay lap tuc.
- Dieu nay giup BIST de dung va de verify hon rat nhieu.

10. KE HOACH THUC HIEN THEO GIAI DOAN

PHASE 0 - GIU SCOPE NHO
- Muc tieu:
  xac nhan BIST chi can dat muc "du dung".
- Cong viec:
  chot khong theo scan-LBIST sau,
  chot scope o muc functional compare on-chip.
- Dau ra:
  1 spec nho cho BIST v1.5.

PHASE 1 - SUA logic_bist.sv
- Muc tieu:
  bien BIST thanh khoi co PASS/FAIL that.
- Cong viec:
  + them GOLDEN register
  + them compare logic
  + sua STATUS
  + sua START/RESTART
- Dau ra:
  BIST tu quyet dinh pass/fail, khong phu thuoc testbench.

PHASE 2 - SUA top_soc.sv
- Muc tieu:
  BIST duoc tich hop dep hon o top-level.
- Cong viec:
  + route BIST status ra GPIO[3] neu can
  + dat ten / day tin hieu ro hon
  + giu irq CPU bi mask trong luc BIST
- Dau ra:
  BIST thay duoc trong he thong, khong chi nam trong module rieng.

PHASE 3 - SUA testbench
- Muc tieu:
  verify lai dung y nghia BIST moi.
- Cong viec:
  + test golden pass
  + test faulty fail
  + test restart
  + test clear_status
  + test relay khong bi trip trong luc BIST
- Dau ra:
  bo BIST testbench gon nhung du tin cay.

PHASE 4 - TUY CHON SUA CPU
- Muc tieu:
  neu muon sat bai bao hon mot chut.
- Cong viec:
  goi BIST sau WDT reset hoac sau boot.
- Dau ra:
  BIST duoc he thong su dung that.

11. THU TU UU TIEN THUC TE

1. Sua logic_bist.sv.
2. Sua testbench.
3. Noi BIST status ra top_soc.sv.
4. Neu con thoi gian moi can sua cpu_8bit.sv.

12. CHECKLIST TEST CAN CO

[ ] Golden signature duoc nap / doc dung.
[ ] BIST golden run -> PASS.
[ ] Force loi DSP -> FAIL.
[ ] START khi COMPLETE -> restart dung.
[ ] Clear status -> xoa done/pass/fail dung.
[ ] Relay khong bi trip trong luc BIST.
[ ] GPIO[3] phan anh BIST status neu co noi.
[ ] Test length = 0 duoc xu ly ro rang.
[ ] Seed = 0 duoc thay bang seed hop le nhu mong doi.

13. 5 DIEU BAN NEN NHO VE BIST NAY

- BIST hien tai da co nen, nen khong can dap di lam lai.
- Dieu quan trong nhat la dua PASS/FAIL vao trong chip.
- Golden signature nam trong testbench thi chua dat muc bai bao.
- BIST cho do an nay nen vua du, khong can lam qua sau.
- Ve uu tien, WATCHDOG va DSP van quan trong hon BIST.

14. DE XUAT CUOI CUNG

- Co can nghien cuu BIST khong?
  CO, nhung chi o muc vua phai.
- Co can nang cap hon bai bao khong?
  Khong can nhieu. Chi can hon mot chut o cho:
  status ro rang, restart dep, va testbench chac chan hon.
- Muc tieu tot nhat cho ban:
  "Functional BIST v1.5 du dung, du bao cao, du tich hop voi he thong."

KET QUA MONG MUON CUOI CUNG

- BIST co the tu danh gia PASS/FAIL ngay trong RTL.
- Testbench khong con phai dong vai "trong tai chinh".
- BIST hop voi bai bao hon, nhung van giu scope nho va de bao tri.
