# Phần 5: IP Core - Logic BIST (Built-In Self-Test)

## 1. Vai trò chức năng
`logic_bist` là khối hỗ trợ tự kiểm tra chức năng (Functional BIST helper) dành cho DSP. Khối này chịu trách nhiệm sinh tín hiệu kích thích đưa vào DSP và nén tín hiệu phản hồi để tạo thành một "chữ ký" (signature) kiểm tra.

## 2. Mô hình hoạt động
Sử dụng 3 thành phần chính:
- **PRPG (Pseudo-random pattern generator)**: Sử dụng LFSR (Linear-Feedback Shift Register) 16-bit để tạo dữ liệu giả lập giống như nhiễu/hồ quang.
- **Run Controller**: Máy trạng thái FSM (IDLE → RUN → COMPLETE) quản lý toàn bộ chu trình kiểm tra.
- **MISR (Response compactor)**: Đọc luồng ngắt từ DSP và nén thành một mã signature 16-bit. 

## 3. Giao tiếp trong SoC
- Khi phần mềm kích hoạt BIST, tín hiệu `bist_active_o` sẽ báo hiệu khối SoC ngắt luồng dữ liệu từ ADC và thay bằng dữ liệu từ BIST.
- Trong thời gian này, ngắt từ DSP (irq_arc) bị che (mask) khỏi hệ thống, ngăn không cho Relay vật lý bị ngắt nhầm trong lúc đang tự kiểm tra.
- Sau khi hoàn thành, firmware có thể qua giao tiếp APB đọc mã Signature để đối chiếu xem logic DSP còn hoạt động đúng hay không.
