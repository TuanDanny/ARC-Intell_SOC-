DSP DEVELOPMENT PLAN
Project: In_SOC
Date: 2026-04-02\

STATUS NOTE - 2026-04-26

This file is a historical development plan. It should not be read as the
current RTL status. Several items listed below, such as richer DSP telemetry,
adaptive threshold support, stream-restart awareness, thermal path, quiet-zone
path, and profile support, have since been implemented in rtl/periph/dsp_arc_detect.sv.

For the current IP scope and RTL-aligned claims, use:
  docs/ip/ip_scope_and_rtl_alignment.md
  docs/ip/dsp_arc_detect.md

đánh giá những gì DSP đang làm tốt
những điểm chưa đạt so với bài báo
các file cần sửa

1. KET LUAN NHANH

- DSP hien tai KHONG te. Nguoc lai, no da co "xuong song" dung huong:
  vi phan (high-pass kieu don gian) + threshold + leaky integrator
  + saturation + APB config + IRQ.
- Tuy nhien, neu doi chieu voi bai bao thi DSP hien tai moi dat muc:
  prototype / demo functional.
- Neu muc tieu la "dat muc bai bao da mo ta", thi ban NEN nghien cuu lai
  khoi DSP, vi day la trai tim hoc thuat cua toan du an.
- Neu muc tieu la "hon bai bao mot chut", thi nen phat trien theo huong:
  adaptive threshold + low-latency fast path + FIFO/CDC + debug/telemetry
  + bo test dua tren trace thuc te.

2. NHUNG GI DSP HIEN TAI LAM TOT

- Da co bo loc vi phan bang hieu 2 mau lien tiep:
  s_curr - s_prev
- Da co triet tuyet doi cua bien do thay doi:
  diff_abs
- Da co nguong phat hien:
  reg_diff_threshold
- Da co bo tich phan ro ri:
  integrator tang theo attack_rate, giam theo decay_rate
- Da co saturation tranh tran so:
  khong cho integrator vuot reg_int_limit
- Da co canh bao som:
  reg_status = WARN khi vuot nua nguong
- Da co bao dong nguy hiem:
  irq_arc_o = 1 khi tich luy dat nguong
- Da co APB register map de CPU co the cau hinh
- Da co BIST mux de bom mau kiem tra vao DSP

3. NHUNG DIEM CHUA DAT SO VOI BAI BAO

[1] Chua co adaptive threshold that su
- Bai bao mo ta "so sanh voi nguong an toan thich nghi".
- RTL hien tai chi co mot thanh ghi threshold co dinh do CPU ghi vao.
- Nghia la nguong hien tai la static threshold, chua theo muc nen / noise floor.

[2] Chua co FIFO / CDC dung nghia nhu bai bao
- Bai bao mo ta SPI -> FIFO -> DSP, dung de bao dam toan ven du lieu va
  giai quyet chenh lech xung nhip.
- RTL hien tai dung spi_adc_stream_rx phat sample_data_o/sample_valid_o
  truc tiep sang DSP trong cung domain clk_i.
- Nghia la hien tai chua co lop dem va chua co CDC thuc su.

[3] Chua thuyet phuc ve latency < 10 us
- Bai bao huong toi phan hoi duoi 10 us.
- Voi tham so hien tai:
  SYS_CLK = 50 MHz
  SCLK_DIV = 2
  SAMPLE_WIDTH = 16
  PRE_CS = 1
  POST_CS = 1
- Uoc tinh 1 sample mat khoang 66 chu ky sys_clk = 1.32 us.
- Default DSP:
  attack = 10
  int_limit = 1000
  => can xap xi 100 spike hop le de trip.
- Uoc tinh trip time ly tuong ~= 132 us, chua tinh CPU/relay.
- Ket luan:
  mo phong PASS chua dong nghia dat muc latency ma bai bao ky vong.

[4] IRQ va status chua du "safety-grade"
- irq_arc_o hien tu clear khi integrator ve 0.
- reg_status hien chi co SAFE / WARN / FIRE.
- Chua co sticky event latched, chua co event counter, chua co clear-on-write.
- Neu muon debug ngoai thuc te, thong tin nay chua du.

[5] APB visibility con ngheo
- Hien APB moi doc duoc:
  STATUS, DIFF_THRESH, INT_LIMIT, DECAY_RATE, ATTACK_RATE
- Chua doc duoc:
  integrator hien tai, diff_abs hien tai, peak_diff, sample_counter,
  irq_latched, false_positive_counter, event_timestamp mini.

[6] Kien truc toan khoi DSP chua tach thanh cac stage ro rang
- Moi thu dang nam trong 1 module dsp_arc_detect.sv.
- Dieu nay tot cho demo nho, nhung kho mo rong khi ban muon:
  doi bo loc, them adaptive logic, them classifier, them debug.

[7] CPU chua khai thac duoc kha nang cau hinh DSP
- CPU ROM hien tai khong cau hinh threshold / attack / decay cua DSP.
- He thong dang dung default parameters la chinh.
- Nghia la control plane co, nhung firmware flow gan nhu chua dung.

[8] Verification chua chung minh "dat bai bao"
- Testbench hien chu yeu dung cac mau tong hop:
  500/0, 600, 650, stuck-high...
- Day la rat tot de proof-of-concept, nhung chua du de danh gia:
  false positive / false negative / do ben nguong / latency that.

4. CAC FILE QUAN TRONG CAN DOC VA SUA

- rtl/periph/dsp_arc_detect.sv
- rtl/periph/spi_adc_stream_rx.sv
- rtl/top_soc.sv
- rtl/core/cpu_8bit.sv
- rtl/periph/logic_bist.sv
- sim/tb.sv
- sim/tb_professional.sv

5. DANH GIA TUNG FILE

[A] rtl/periph/dsp_arc_detect.sv
- Day la loi thuat toan DSP hien tai.
- Diem tot:
  code ro, de doc, co saturate, co APB.
- Diem can nang cap:
  chua adaptive threshold,
  chua co sticky interrupt/event,
  chua co debug register,
  chua co classifier giau thong tin hon 1-bit IRQ,
  parameterization chua that su generic.

[B] rtl/periph/spi_adc_stream_rx.sv
- Day la frontend giao tiep ADC.
- Diem tot:
  FSM sach, phat sample_valid ro rang, co overrun flag.
- Diem can nang cap:
  chua co FIFO,
  chua co CDC thuc su,
  overrun_o hien khong duoc top-level dung,
  sample_ready_i dang bi hardwire = 1.

[C] rtl/top_soc.sv
- Day la noi DSP gap SPI, CPU, BIST.
- Diem tot:
  da co mux BIST,
  da co route IRQ ve CPU.
- Diem can nang cap:
  chua co telemetry/debug cua DSP,
  chua co route sample overrun thanh status safety,
  chua co policy neu ADC stream loi.

[D] rtl/core/cpu_8bit.sv
- Day la control plane cho DSP.
- Diem can nang cap:
  chua co code config DSP,
  chua co logic tuning threshold,
  chua co logic doc status chi tiet / logging.

[E] sim/tb.sv va sim/tb_professional.sv
- Day la proof bench rat gia tri cho do an.
- Diem can nang cap:
  can them dataset-based replay,
  can them latency measurement that hon,
  can them APB config sweep,
  can them false-positive campaigns.

6. NHUNG NANG CAP BAT BUOC NEU MUON DAT MUC BAI BAO

[1] Tach DSP thanh cac khoi ro rang
- dsp_preprocess:
  nhan sample, tinh diff, abs, peak
- dsp_threshold:
  threshold static hoac adaptive
- dsp_integrator:
  attack / decay / saturation
- dsp_classifier:
  warn / fire / sticky event / irq policy
- dsp_regs:
  APB register map

[2] Them adaptive threshold
- Muc tieu:
  threshold khong dung yen, ma theo muc nen cua he thong.
- Cach co ban, de lam va de hoc:
  noise_floor <= noise_floor + alpha*(diff_abs - noise_floor)
  threshold_dynamic = base_threshold + k * noise_floor
- Loi ich:
  giam false positive khi moi truong on ao thay doi.

[3] Them sticky event latch
- Khi fire xay ra:
  fire_latched = 1
- Chi xoa bang APB clear hoac reset co chu dich.
- Loi ich:
  giup CPU/UART/GPIO khong bo lo su kien ngan.

[4] Them register telemetry
- STATUS:
  safe, warn, fire, fire_latched, sample_overrun
- CURRENT_DIFF
- CURRENT_INTEGRATOR
- PEAK_DIFF
- PEAK_INTEGRATOR
- EVENT_COUNT
- CLEAR register
- Loi ich:
  giup tuning va debug de hon rat nhieu.

[5] Them fast path cho latency
- Hien tai chi co 1 duong "tich luy cham roi moi trip".
- Nen them 2 lop quyet dinh:
  Fast emergency path:
    neu diff_abs vuot nguong rat cao N lan lien tiep ngan -> trip ngay
  Slow confidence path:
    leaky integrator de xu ly ho quang chap chon
- Day la nang cap rat dang gia neu ban muon den gan muc < 10 us.

[6] Them FIFO / CDC hoac it nhat de san interface cho no
- Ban dau, neu chua muon lam async FIFO that:
  hay chen 1 sample FIFO dong bo nho ngay sau SPI.
- Sau do nang cap thanh async FIFO neu ADC va DSP khac domain.
- Day la buoc can thiet de kien truc gan bai bao hon.

7. NHUNG NANG CAP "HON BAI BAO MOT CHUT" NEU THUC SU CAN

[1] Multi-feature classifier
- Ngoai diff_abs + integrator, bo sung:
  short-term energy,
  zero-cross density,
  burst density,
  peak hold.
- Khong can lam AI/ML som.
- Chi can fusion 2-3 feature la da hon bai bao nhung van hop ly.

[2] Auto profile switching
- Ho tro profile:
  normal load
  motor heavy
  EV charger
  contact-aging
- CPU chon profile theo ngu canh.

[3] Event trace mini
- Luu 4-8 event cuoi:
  peak_diff, peak_integrator, state, sample_count.
- Rat hieu qua khi demo va debug ngoai lab.

[4] BIST cho noi tang DSP sau hon
- BIST hien chu yeu nhin IRQ dau ra.
- Neu muon tot hon:
  them mode quan sat them classifier / integrator path.

8. NHUNG NANG CAP KHONG NEN LAM QUA SOM

- Khong nen nhay thang vao FFT.
- Khong nen them deep learning tren RTL ngay.
- Khong nen mo rong qua nhieu kenh ADC truoc khi 1 kenh da duoc chung minh.
- Khong nen toi uu cong suat/area qua som khi chua chot dung thuat toan.

9. KE HOACH THUC HIEN THEO GIAI DOAN

PHASE 0 - BASELINE & DO DAC
- Muc tieu:
  hieu chinh xac DSP hien tai dat gi va khong dat gi.
- Cong viec:
  do latency,
  do so sample de trip,
  ghi lai false positive / false negative tren test hien tai,
  luu waveform chuan.
- Dau ra:
  1 baseline report ngan.

PHASE 1 - CLEAN ARCHITECTURE
- Muc tieu:
  refactor DSP thanh cac stage ro rang, de de nghien cuu.
- Cong viec:
  tach preprocess / threshold / integrator / classifier / regs.
- Dau ra:
  DSP de doc, de test, de mo rong.

PHASE 2 - OBSERVABILITY
- Muc tieu:
  nhin duoc noi tang DSP qua APB ma khong can moi lan deu mo waveform.
- Cong viec:
  them CURRENT_DIFF, CURRENT_INTEGRATOR, PEAK_DIFF, EVENT_COUNT,
  FIRE_LATCHED, CLEAR_EVENT.
- Dau ra:
  bench va CPU co the debug DSP de dang.

PHASE 3 - ADAPTIVE THRESHOLD
- Muc tieu:
  giam false positive va gap bai bao hon.
- Cong viec:
  them noise_floor estimator,
  dynamic threshold,
  cho phep bat/tat bang APB.
- Dau ra:
  DSP co 2 mode:
  static mode va adaptive mode.

PHASE 4 - FAST PATH LATENCY
- Muc tieu:
  dua he thong den gan hoac dat muc latency trong bai bao.
- Cong viec:
  them duong so sanh khan cap,
  them consecutive-spike counter,
  tune lai attack/limit.
- Dau ra:
  phan hoi nhanh hon rat nhieu voi solid arc.

PHASE 5 - SPI FRONTEND + FIFO / CDC
- Muc tieu:
  lam frontend dung "phong cach bai bao".
- Cong viec:
  chen sample FIFO,
  xu ly overrun thanh status that,
  chuan bi async boundary neu can.
- Dau ra:
  duong ADC -> DSP ben vung hon, mo rong de hon.

PHASE 6 - CPU / CONTROL INTEGRATION
- Muc tieu:
  cho CPU thuc su cau hinh va doc ket qua DSP.
- Cong viec:
  them chuong trinh config threshold/profile,
  doc sticky events,
  gui bao cao ra UART neu can.
- Dau ra:
  DSP khong con la "khoi tu chay", ma thanh subsystem hoan chinh.

PHASE 7 - VERIFICATION NANG CAO
- Muc tieu:
  chung minh DSP dat muc "tin duoc", khong chi "chay duoc".
- Cong viec:
  them sweep tham so,
  them random regression,
  them replay trace ADC,
  them do latency tu dong,
  them false-positive campaign.
- Dau ra:
  1 bo ket qua mo phong co gia tri hoc thuat.

10. TEST PLAN NEN CO

[A] Directed tests co ban
- normal noise
- motor inrush
- single transient spark
- intermittent arc
- solid arc
- ADC stuck-high
- contact overheat

[B] Directed tests moi nen bo sung
- adaptive threshold ON/OFF
- fire_latched clear-on-write
- peak register update
- event counter tang dung
- sample overrun report
- fast path trigger
- fast path khong trip oan voi inrush

[C] Random tests
- random noise stream
- random burst stream
- random quiet-to-burst transitions
- random threshold sweep

[D] Measurement tests
- do latency theo us
- dem so sample de fire
- thong ke false trip
- thong ke miss trip

11. THU TU UU TIEN THUC TE

1. Refactor dsp_arc_detect.sv cho de doc va de mo rong.
2. Them telemetry + sticky event.
3. Them adaptive threshold.
4. Them fast path latency.
5. Nang cap spi_adc_stream_rx.sv theo huong FIFO / CDC.
6. Moi sua CPU va testbench de khai thac tinh nang moi.

12. 5 DIEU BAN NEN NHO KHI NGHIEN CUU DSP NAY

- PASS testbench khong dong nghia dat latency nhu bai bao.
- Mot threshold co dinh rat de demo, nhung thuong khong du ben ngoai thuc te.
- Neu khong co telemetry, ban se rat kho tuning DSP.
- Neu khong tach stage, moi nang cap ve sau se rat met.
- DSP la khoi co gia tri hoc thuat cao nhat cua du an nay, nen rat dang dau tu.

13. DINH HUONG DE XUAT CUOI CUNG

- Neu ban muon dat muc bai bao:
  nen lam toi thieu den Phase 5.
- Neu ban muon "hon bai bao mot chut" nhung van thuc te:
  nen lam den Phase 7, nhung chi can 1-2 nang cap vuot troi:
  adaptive threshold + fast path + trace-based verification.
- Neu ban moi bat dau:
  hay lam lan luot:
  refactor -> telemetry -> adaptive threshold.
- Day la lo trinh vua hoc duoc ly thuyet DSP so,
  vua hoc duoc thiet ke RTL,
  vua tao ra ket qua co gia tri bao cao.

KET QUA MONG MUON CUOI CUNG

- DSP khong chi "phat hien duoc ho quang",
  ma con co the giai thich vi sao no phat hien.
- He thong co thong so de tuning, co event de debug, co bang chung de bao ve.
- Ban co mot nen tang de tiep tuc nghien cuu theo huong hoc thuat hoac san pham.
