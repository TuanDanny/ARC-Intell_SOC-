/*
 * File: typedef.svh
 * Description: Định nghĩa các kiểu dữ liệu dùng cho ngoại vi APB.
 */

`ifndef _APB_TYPEDEF_SVH_
`define _APB_TYPEDEF_SVH_

    // Định nghĩa các kiểu dữ liệu cơ bản để code gọn hơn
    typedef logic [31:0]    addr_t;  // Kiểu địa chỉ 32-bit
    typedef logic [31:0]    data_t;  // Kiểu dữ liệu 32-bit
    typedef logic [3:0]     strb_t;  // Kiểu Strobe (Byte enable) 4-bit
    
    // Nếu sau này bạn dùng UART thật của PULP, họ có thể cần thêm các struct.
    // Hiện tại với Dummy UART hoặc code rút gọn, chỉ cần file này tồn tại là đủ.

`endif