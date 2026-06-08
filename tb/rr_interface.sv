//============================================================
// rr_interface.sv
//============================================================
interface rr_if (input logic clk);

  logic                    rstn;
  logic                    en;
  logic                    load_weights;
  logic [`N-1:0][`W-1:0]  weights;
  logic [`N-1:0]           req;
  logic [`N-1:0]           gnt;

  // Driver clocking block — drive on posedge
  clocking driver_cb @(posedge clk);
    default input #1 output #1;
    output rstn;
    output en;
    output load_weights;
    output weights;
    output req;
  endclocking

  // Monitor samples on POSEDGE with #1step skew —
  // samples AFTER the clock edge so DUT registered outputs are stable
  clocking monitor_cb @(posedge clk);
    default input #1step;
    input rstn;
    input en;
    input load_weights;
    input weights;
    input req;
    input gnt;
  endclocking

  modport driver_mp  (clocking driver_cb,  input clk);
  modport monitor_mp (clocking monitor_cb, input clk);

endinterface
