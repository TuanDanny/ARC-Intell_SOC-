# Thiết kế: Cảm biến nhiệt độ vật lý & vị trí triển khai IP core trong full-stack an toàn điện

**Ngày:** 2026-08-02
**Phạm vi:** Thiết kế hệ thống / kiến trúc triển khai cho In_SOC (INTELLI-SAFE-SoC) khi tapout thành chip/module thật, tích hợp vào Aptomat thông minh (Smart Breaker). Đây là spec **thiết kế**, chưa có RTL — mọi thay đổi RTL nêu ở đây là việc cần làm ở bước kế tiếp (writing-plans / implementation), không nằm trong phạm vi tài liệu này.

**Bối cảnh xuất phát:** Toàn bộ RTL hiện tại (`dsp_arc_detect.sv`) chỉ có **một kênh cảm biến duy nhất** — dòng điện lấy qua ADC ngoài (`adc_data_i`, 16-bit). Cả hai loại sự cố "hồ quang điện" (arc fault) và "tiếp điểm quá nhiệt" (glowing contact) hiện được suy luận bằng hai thuật toán khác nhau trên **cùng một** tín hiệu dòng điện đó — không có cảm biến nhiệt độ vật lý (NTC/RTD/IR) nào trong thiết kế đã kiểm chứng. Tài liệu này thiết kế việc bổ sung một kênh cảm biến nhiệt độ vật lý thật, và làm rõ IP core nằm ở đâu trong một hệ thống an toàn điện đô thị đầy đủ.

---

## 1. Vị trí của IP core trong full-stack an toàn điện

Hệ thống an toàn điện cho đô thị thông minh được chia thành 4 tầng độc lập. In_SOC **chỉ** đảm nhiệm Tầng 1 — đây là ranh giới phạm vi có chủ đích, không phải thiếu sót:

| Tầng | Vai trò | Ai đảm nhiệm |
|---|---|---|
| **1. Sensor & bảo vệ tự trị** | Nằm trong từng CB riêng lẻ, phát hiện + cắt relay **cục bộ, độc lập, không phụ thuộc mạng** — phải hoạt động đúng ngay cả khi mất kết nối/mất điện toàn nhà | **In_SOC (phạm vi tài liệu này)** |
| 2. Tổng hợp/truyền thông cấp tủ điện | Gom trạng thái + telemetry (cause code, thời điểm trip) từ nhiều CB trong 1 tủ điện, đẩy lên qua bus (RS-485/Modbus hoặc BLE mesh cho retrofit) | Module gateway riêng — **chưa có trong RTL**, thuộc "Lộ trình phát triển" (kết nối hạ tầng đô thị) |
| 3. Quản lý toà nhà (BMS) | Phân tích xu hướng nhiều mạch cùng lúc (ví dụ nhiều CB có mật độ spike tăng dần dù chưa trip) | Phần mềm BMS, ngoài phạm vi chip |
| 4. Hạ tầng đô thị thông minh | Dữ liệu rủi ro cháy nổ tổng hợp cấp khu vực, phục vụ cảnh báo PCCC/quy hoạch bảo trì lưới điện | Nền tảng thành phố, ngoài phạm vi dự án |

**Nguyên tắc thiết kế cốt lõi:** một thiết bị bảo vệ điện phải tự cắt điện được dù không có mạng/cloud/BMS. Việc chưa kết nối lên Tầng 2-4 là ranh giới phạm vi rõ ràng, không phải giới hạn kỹ thuật.

---

## 2. Vị trí lắp đặt vật lý & phương án tích hợp cảm biến nhiệt

### 2.1. Vị trí lắp: tích hợp trong thân Aptomat/CB

Module (chip + cảm biến) nằm **bên trong vỏ CB**, đo dòng điện và nhiệt độ **ngay tại điểm tiếp điểm** — đúng vị trí phát sinh hồ quang/quá nhiệt thật, cho độ nhạy cao nhất. Đánh đổi: cần phối hợp với nhà sản xuất CB để tích hợp cơ khí (không phải sản phẩm add-on lắp rời).

**Ràng buộc kỹ thuật chi phối:** tiếp điểm và busbar mang điện áp lưới (220–380V), nên bất kỳ cảm biến nào đặt gần đó phải hoặc (a) đảm bảo khoảng cách rò/khe hở cách điện theo IEC 60947-2 (chuẩn CB), hoặc (b) hoàn toàn không tiếp xúc điện. Đây là bài toán mà cơ cấu nhả nhiệt bimetal trong CB cơ truyền thống đã giải quyết từ lâu — có tiền lệ kỹ thuật rõ ràng để tham chiếu, không phải vấn đề mới trong ngành.

### 2.2. Ba phương án cảm biến nhiệt độ đã cân nhắc

| Phương án | Cách hoạt động | Ưu điểm | Rủi ro / đánh đổi |
|---|---|---|---|
| **A. NTC thermistor gắn cách ly nhiệt trên khung/busbar gần tiếp điểm** — ⭐ **được chọn** | Bọc epoxy/miếng dẫn nhiệt cách điện, đặt gần điểm tiếp xúc; đọc qua kênh ADC thứ 2 dùng chung hạ tầng `apb_spi_adc_bridge` đã có | Rẻ (~0,1–0,5 USD), nhỏ gọn, tái dùng gần như toàn bộ hạ tầng SPI Bridge đã build & verify; tốc độ lấy mẫu đủ nhanh vì quá nhiệt tiếp điểm là hiện tượng suy biến chậm (giây/phút), không cần <10µs như hồ quang | Cần thiết kế đường dẫn nhiệt cách điện chuẩn — nhưng đây là việc nhà sản xuất CB đã quen làm với bimetal |
| B. Cảm biến IR/thermopile không tiếp xúc, nhìn qua khe hở vào vùng tiếp điểm | Đo nhiệt bức xạ, không chạm điện | Cách ly tuyệt đối, đo đúng nhiệt độ bề mặt tiếp điểm thật | Đắt hơn (~2–5 USD), cồng kềnh cho MCB nhỏ; buồng dập hồ quang bị ám khói/carbon sau mỗi lần cắt tải sẽ làm bẩn cửa sổ cảm biến theo thời gian — rủi ro suy giảm độ chính xác trong vòng đời sản phẩm |
| C. Khai thác cơ cấu bimetal có sẵn (thêm cảm biến vị trí Hall/quang học đo độ uốn bimetal) | Số hoá tín hiệu cơ khí đã có sẵn, không thêm cảm biến nhiệt mới | Tận dụng cơ cấu đã được chứng nhận an toàn sẵn, chi phí thấp nhất | Cách tích hợp mới, cần phối hợp sâu với thiết kế cơ khí CB — rủi ro triển khai cao hơn cho dự án ở giai đoạn ý tưởng |

**Lý do chọn phương án A:**
1. **Tái sử dụng hạ tầng đã kiểm chứng** — chỉ mở rộng `apb_spi_adc_bridge` từ 1 kênh lên 2 kênh, không thiết kế lại DSP hay bus, đúng tinh thần "reusable IP" của dự án.
2. **Đúng bản chất vật lý của hiện tượng** — glowing-contact là quá trình suy biến chậm (oxi hoá/lỏng tiếp điểm qua thời gian), nên cảm biến tốc độ thấp, chi phí thấp là đủ; không cần độ chính xác/tốc độ của phương án B.

---

## 3. Luồng dữ liệu & sơ đồ khối mở rộng

**Nguyên tắc:** chỉ mở rộng tầng cảm biến & quyết định (Stage A/B trong DSP), giữ nguyên hoàn toàn phần đã kiểm chứng phía sau (CPU nhận ngắt, cắt relay, watchdog) — không cần làm lại bộ 50/50 kịch bản đã pass.

```
[CT đo dòng điện]  ──16-bit──►  apb_spi_adc_bridge (kênh 0) ──┐
                                                                 ├──►  DSP Arc/Thermal Detect
[NTC đo nhiệt độ]  ──16-bit──►  apb_spi_adc_bridge (kênh 1) ──┘         (2 luồng song song)
                                                                          │
                        ┌─────────────────────────────────────────────────┤
                        ▼ Stage A (tách riêng theo kênh)                  ▼
             Kênh dòng điện: noise floor thích ứng,         Kênh nhiệt độ: lọc low-pass,
             envelope, mật độ spike (như hiện tại,          so ngưỡng tuyệt đối + tốc độ
             KHÔNG đổi)                                     tăng nhiệt (dT/dt)
                        │                                                 │
                        └─────────────────┬───────────────────────────────┘
                                           ▼ Stage B — đối chiếu chéo (MỚI)
                    ARC_DENSITY / ARC_STANDARD / QUIET_ZONE  ← vẫn chỉ từ kênh dòng điện, không đổi
                    THERMAL  ← chỉ trip khi hotspot-score (dòng điện) VÀ ngưỡng nhiệt độ thật
                               cùng lúc vượt ngưỡng — giảm báo động giả do 1 nguồn tín hiệu
                                           │
                                           ▼
                              irq_arc_o → CPU NMI (không đổi)
                                           │
                                           ▼
                        CPU cắt relay + ghi cause code (không đổi, đã verify)
```

### 3.1. Các thay đổi RTL cần thiết (việc cho bước implementation kế tiếp, không làm ở đây)

1. **`apb_spi_adc_bridge`**: mở rộng từ lấy mẫu 1 kênh sang tuần tự 2 kênh (dòng điện + nhiệt độ). SPI master đã có cơ chế lấy mẫu sẵn, chỉ cần thêm logic chọn kênh.
2. **`dsp_arc_detect`**: thêm cổng dữ liệu vào thứ 2 (`temp_data_i`), thêm Stage A riêng cho kênh nhiệt độ (low-pass, ngưỡng tuyệt đối, tốc độ tăng nhiệt), và logic đối chiếu chéo ở Stage B chỉ áp dụng cho cause `THERMAL`.
3. **`logic_bist`**: mở rộng self-test để bao phủ (coverage) cả 2 kênh, không chỉ kênh dòng điện như hiện tại — nếu không, self-test sẽ không còn kiểm chứng được đường tín hiệu nhiệt độ mới.
4. **Đăng ký APB mới** (mức khái niệm, chưa định nghĩa offset cụ thể): ngưỡng nhiệt độ tuyệt đối, ngưỡng tốc độ tăng nhiệt, cửa sổ thời gian đối chiếu chéo giữa 2 kênh.

### 3.2. Những gì KHÔNG đổi (đã kiểm chứng, giữ nguyên)

- Toàn bộ đường phản ứng an toàn: `irq_arc_o` → CPU NMI → cắt relay → ghi cause code.
- Watchdog, cơ chế ngắt ưu tiên lồng, CPU ISA.
- Cause code `ARC_DENSITY`, `ARC_STANDARD`, `QUIET_ZONE` — vẫn tính hoàn toàn từ kênh dòng điện như thiết kế đã verify.

---

## 4. Ngoài phạm vi tài liệu này

- Định nghĩa offset thanh ghi APB cụ thể cho kênh nhiệt độ và logic đối chiếu chéo.
- Lựa chọn linh kiện NTC cụ thể (giá trị điện trở, đường cong B, gói SMD) và thiết kế mạch phân áp/khuếch đại tín hiệu tương tự.
- Thiết kế cơ khí đường dẫn nhiệt cách điện bên trong CB (cần phối hợp với nhà sản xuất CB thật).
- Module gateway Tầng 2 (RS-485/Modbus hoặc BLE mesh) và mọi phần Tầng 2–4 của full-stack.
- Cập nhật testbench/regression cho kênh nhiệt độ mới và logic đối chiếu chéo.

Các mục trên là input cho bước lập kế hoạch triển khai (implementation plan) nếu dự án quyết định hiện thực hoá thiết kế này.
