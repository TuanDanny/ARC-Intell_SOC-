# --- THÊM ĐOẠN NÀY VÀO CUỐI FILE ---

# Tự động tính toán sai số clock
derive_clock_uncertainty

# Thiết lập độ trễ đầu vào (Input Delay) cho tất cả các chân (trừ chân clk_i)
# Giả sử tín hiệu bên ngoài đến chậm tối đa 5ns
set_input_delay -clock clk_50 -max 5 [remove_from_collection [all_inputs] [get_ports clk_i]]
set_input_delay -clock clk_50 -min 0 [remove_from_collection [all_inputs] [get_ports clk_i]]

# Thiết lập độ trễ đầu ra (Output Delay)
# Giả sử tín hiệu ra cần ổn định trong vòng 5ns
set_output_delay -clock clk_50 -max 5 [all_outputs]
set_output_delay -clock clk_50 -min 0 [all_outputs]