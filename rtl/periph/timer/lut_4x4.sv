module lut_4x4
(
  input  logic                clk_i,
  input  logic                rstn_i,

  input  logic                cfg_en_i,
  input  logic                cfg_update_i,

  input  logic         [15:0] cfg_lut_i,

  input  logic          [3:0] signal_i,
  output logic                signal_o

);
  logic                r_active;
  logic         [15:0] r_lut;

  always_ff @(posedge clk_i or negedge rstn_i) begin : proc_r_lut
    if(~rstn_i) begin
      r_lut    <= 0;
    end else begin
      if ( (cfg_en_i && !r_active) || cfg_update_i ) //if first enable or explicit update is iven
      begin
        r_lut    <= cfg_lut_i;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rstn_i) begin : proc_r_active
    if(~rstn_i) begin
      r_active <= 0;
    end else 
    begin     
      if (cfg_en_i && !r_active)
        r_active <= 1'b1;
      else if (!cfg_en_i && r_active)
        r_active <= 1'b0;
    end
  end


  always_comb begin : proc_signal_o
    signal_o = 1'b0;
    for (int i=0;i<16;i++)
    begin
      if (i == signal_i)
        signal_o = r_lut[i];
    end
  end

endmodule // lut_4x4
