module  prescaler (
  input  logic                clk_i,
  input  logic                rstn_i,

  input  logic                ctrl_active_i,
  input  logic                ctrl_update_i,
  input  logic                ctrl_rst_i,

  input  logic          [7:0] cfg_presc_i,

  input  logic                event_i,
  output logic                event_o

);

  logic   [7:0] r_presc;
  logic   [7:0] r_counter;

  always_ff @(posedge clk_i or negedge rstn_i) begin : proc_r_presc
    if(~rstn_i) begin
      r_presc <= 0;
    end else begin
      if ( ctrl_update_i ) //if first enable or explicit update is iven
      begin
        r_presc <= cfg_presc_i;
      end
    end
  end


  always_ff @(posedge clk_i or negedge rstn_i) begin : proc_r_counter
    if(~rstn_i) begin
      r_counter <= 0;
      event_o <= 0;
    end else begin
      if (ctrl_rst_i)
      begin
        r_counter <= 0;
        event_o   <= 0;
      end
      else if (ctrl_active_i)
      begin
        if (event_i)
        begin
          if(r_presc == 0)
          begin
            event_o <= 1'b1;
          end
          else
          begin
            if (r_counter == r_presc)
            begin
              event_o   <= 1'b1;
              r_counter <= 0;
            end
            else
            begin
              event_o   <= 1'b0;
              r_counter <= 8'(r_counter + 1);
            end
          end
        end
        else
        begin
          event_o <= 1'b0;
        end
      end
      else
      begin
        r_counter <= 0;
        event_o   <= 0;
      end
    end
  end
endmodule // prescaler
