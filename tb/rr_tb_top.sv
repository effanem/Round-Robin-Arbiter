//============================================================
// rr_tb_top.sv
//============================================================
`timescale 1ns/1ps
import rr_pkg::*;

module rr_tb_top;

  parameter CLK_PERIOD = 20;

  logic clk;
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  rr_if rr_bus (.clk(clk));

  round_robin #(.N(`N), .W(`W), .TYPE(`TYPE)) dut (
    .i_clk     (clk),
    .i_rstn    (rr_bus.rstn),
    .i_en      (rr_bus.en),
    .i_req     (rr_bus.req),
    .i_load    (rr_bus.load_weights),
    .i_weights (rr_bus.weights),
    .o_gnt     (rr_bus.gnt)
  );

  initial begin
    rr_test test;
    test = new(rr_bus);
    test.run();
    $finish;
  end

  initial begin
    #(CLK_PERIOD * 100000);
    $fatal(0, "[TB_TOP] Simulation timeout!");
  end

endmodule
