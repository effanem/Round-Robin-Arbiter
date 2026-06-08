//============================================================
// rr_pkg.sv
// Single package containing all TB classes
//============================================================
package rr_pkg;

  //----------------------------------------------------------
  // Transaction
  //----------------------------------------------------------
  class rr_transaction;

    rand logic [`N-1:0]          req;
    rand logic                   en;
    rand logic                   load_weights;
    rand logic [`N-1:0][`W-1:0]  weights;
    logic      [`N-1:0]          gnt;

    constraint en_dist_c     { en dist {1'b1 := 60, 1'b0 := 40}; }
    constraint load_weight_c { load_weights dist {1'b1 := 15, 1'b0 := 85}; }
    constraint req_nonzero_c { req != '0; }

    function void print(string tag = "TXN");
      $display("[%s] req=%0b en=%0b load=%0b | gnt=%0b",
               tag, req, en, load_weights, gnt);
    endfunction

  endclass

  //----------------------------------------------------------
  // Generator
  //----------------------------------------------------------
  class rr_generator;

    mailbox      gen2drv;
    int unsigned num_transactions = 100;
    event        done;
    event        reset_done;

    function new(mailbox mbx);
      gen2drv = mbx;
    endfunction

    task run();
      rr_transaction txn;

      // Wait for driver to finish reset before sending transactions
      @(reset_done);

      for (int k = 0; k < num_transactions; k++) begin
        txn = new();

        if (`TYPE != 2) begin
          txn.load_weights = 1'b0;
          txn.weights      = '0;
          if (!txn.randomize()) begin
            $error("[GENERATOR] Randomization failed at iteration %0d", k);
            break;
          end
        end else begin
          // For TYPE==2 first txn: force weight load so DUT & scoreboard
          // both start from a known non-zero weight state
          if (k == 0) begin
            if (!txn.randomize()) begin
              $error("[GENERATOR] Randomization failed at iteration %0d", k);
              break;
            end
            txn.load_weights = 1'b1;
            txn.en           = 1'b0;
          end else begin
            if (!txn.randomize()) begin
              $error("[GENERATOR] Randomization failed at iteration %0d", k);
              break;
            end
          end
        end

        $display("[GENERATOR] Sending txn %0d : req=%0b en=%0b load=%0b",
                 k, txn.req, txn.en, txn.load_weights);
        gen2drv.put(txn);
      end

      -> done;
      $display("[GENERATOR] Done generating %0d transactions", num_transactions);
    endtask

  endclass

  //----------------------------------------------------------
  // Driver
  //----------------------------------------------------------
  class rr_driver;

    virtual rr_if    vif;
    mailbox          gen2drv;
    event            reset_done;   // shared with generator

    function new(virtual rr_if vif, mailbox mbx);
      this.vif     = vif;
      this.gen2drv = mbx;
    endfunction

    task reset();
      $display("[DRIVER] Applying reset");
      vif.driver_cb.rstn         <= 1'b0;
      vif.driver_cb.en           <= 1'b0;
      vif.driver_cb.req          <= '0;
      vif.driver_cb.load_weights <= 1'b0;
      vif.driver_cb.weights      <= '0;
      @(posedge vif.clk);
      vif.driver_cb.rstn <= 1'b1;
      @(posedge vif.clk);
      $display("[DRIVER] Reset done");
      -> reset_done;   // signal generator it can start sending
    endtask

    task drive_txn(rr_transaction txn);
      @(vif.driver_cb);
      vif.driver_cb.en           <= txn.en;
      vif.driver_cb.req          <= txn.req;
      vif.driver_cb.load_weights <= txn.load_weights;
      vif.driver_cb.weights      <= txn.weights;
    endtask

    task run();
      rr_transaction txn;
      reset();
      forever begin
        gen2drv.get(txn);
        $display("[DRIVER] Driving: req=%0b en=%0b load=%0b",
                 txn.req, txn.en, txn.load_weights);
        drive_txn(txn);
      end
    endtask

  endclass

  //----------------------------------------------------------
  // Monitor
  //----------------------------------------------------------
  class rr_monitor;

    virtual rr_if  vif;
    mailbox        mon2scb;

    function new(virtual rr_if vif, mailbox mbx);
      this.vif     = vif;
      this.mon2scb = mbx;
    endfunction

    task run();
      rr_transaction txn;
      forever begin
        // Wait for posedge — sample inputs driven this cycle
        @(vif.monitor_cb);
        if (vif.monitor_cb.en) begin
          txn              = new();
          txn.req          = vif.monitor_cb.req;
          txn.en           = vif.monitor_cb.en;
          txn.load_weights = vif.monitor_cb.load_weights;
          txn.weights      = vif.monitor_cb.weights;
          // Wait one more posedge — DUT registers inputs and gnt is now valid
          @(vif.monitor_cb);
          txn.gnt = vif.monitor_cb.gnt;
          $display("[MONITOR] Captured: req=%0b gnt=%0b", txn.req, txn.gnt);
          mon2scb.put(txn);
        end
      end
    endtask

  endclass

  //----------------------------------------------------------
  // Scoreboard
  //----------------------------------------------------------
  class rr_scoreboard;

    localparam M = $clog2(`N);

    mailbox                mon2scb;
    logic [M-1:0]          ptr_ref;
    logic [`N-1:0][`W-1:0] weights_ref;
    int                    pass_count;
    int                    fail_count;

    function new(mailbox mbx);
      mon2scb     = mbx;
      ptr_ref     = '0;
      weights_ref = '0;
      pass_count  = 0;
      fail_count  = 0;
    endfunction

    function logic [`N-1:0] compute_expected(rr_transaction txn);
      logic [`N-1:0]         exp_gnt;
      logic [M-1:0]          ptr_tmp;
      logic [`N-1:0]         req_w;
      logic [`N-1:0][`W-1:0] masked;
      logic [`W-1:0]         max_val;

      exp_gnt = '0;
      ptr_tmp = ptr_ref;

      if (`TYPE == 0) begin
        if (txn.req[ptr_ref]) begin
          exp_gnt[ptr_ref] = 1'b1;
        end else begin
          for (int i = int'(ptr_ref)-1; i >= 0; i--)
            if (txn.req[i]) ptr_tmp = i;
          for (int i = `N-1; i > int'(ptr_ref); i--)
            if (txn.req[i]) ptr_tmp = i;
          exp_gnt[ptr_tmp] = txn.req[ptr_tmp];
        end
        ptr_ref = (ptr_ref == `N-1) ? '0 : ptr_ref + 1;
      end

      else if (`TYPE == 1) begin
        if (txn.req[ptr_ref]) begin
          exp_gnt[ptr_ref] = 1'b1;
          ptr_tmp           = ptr_ref;
        end else begin
          for (int i = int'(ptr_ref)-1; i >= 0; i--)
            if (txn.req[i]) ptr_tmp = i;
          for (int i = `N-1; i > int'(ptr_ref); i--)
            if (txn.req[i]) ptr_tmp = i;
          exp_gnt[ptr_tmp] = txn.req[ptr_tmp];
        end
        ptr_ref = (ptr_tmp == `N-1) ? '0 : ptr_tmp + 1;
      end

      else begin
        if (txn.load_weights)
          weights_ref = txn.weights;

        for (int i = 0; i < `N; i++)
          masked[i] = txn.req[i] ? weights_ref[i] : '0;

        max_val = 0;
        for (int i = 0; i < `N; i++)
          if (masked[i] > max_val) max_val = masked[i];

        req_w = '0;
        for (int i = 0; i < `N; i++)
          if ((masked[i] == max_val) && txn.req[i])
            req_w[i] = 1'b1;

        if (req_w[ptr_ref]) begin
          exp_gnt[ptr_ref] = 1'b1;
          ptr_tmp           = ptr_ref;
        end else begin
          for (int i = int'(ptr_ref)-1; i >= 0; i--)
            if (req_w[i]) ptr_tmp = i;
          for (int i = `N-1; i > int'(ptr_ref); i--)
            if (req_w[i]) ptr_tmp = i;
          exp_gnt[ptr_tmp] = 1'b1;
        end

        if (|exp_gnt && !txn.load_weights && weights_ref[ptr_tmp] > 0)
          weights_ref[ptr_tmp] = weights_ref[ptr_tmp] - 1;

        ptr_ref = (ptr_tmp == `N-1) ? '0 : ptr_tmp + 1;
      end

      return exp_gnt;
    endfunction

    task run();
      rr_transaction txn;
      logic [`N-1:0] exp_gnt;
      forever begin
        mon2scb.get(txn);
        exp_gnt = compute_expected(txn);
        if (txn.gnt === exp_gnt) begin
          $display("[SCOREBOARD] PASS | req=%0b | gnt=%0b | exp=%0b",
                   txn.req, txn.gnt, exp_gnt);
          pass_count++;
        end else begin
          $error("[SCOREBOARD] FAIL | req=%0b | gnt=%0b | exp=%0b",
                 txn.req, txn.gnt, exp_gnt);
          fail_count++;
        end
      end
    endtask

    function void report();
      $display("\n============================================================");
      $display("  SCOREBOARD SUMMARY  (TYPE=%0d)", `TYPE);
      $display("  PASS = %0d", pass_count);
      $display("  FAIL = %0d", fail_count);
      if (fail_count == 0)
        $display("  RESULT : ** ALL TESTS PASSED **");
      else
        $display("  RESULT : !! %0d TESTS FAILED !!", fail_count);
      $display("============================================================\n");
    endfunction

  endclass

  //----------------------------------------------------------
  // Environment
  //----------------------------------------------------------
  class rr_environment;

    rr_generator  gen;
    rr_driver     drv;
    rr_monitor    mon;
    rr_scoreboard scb;

    mailbox gen2drv;
    mailbox mon2scb;
    event   gen_done;
    event   reset_done;   // shared between driver and generator

    virtual rr_if vif;

    function new(virtual rr_if vif);
      this.vif = vif;
      gen2drv  = new(1);
      mon2scb  = new();
      gen = new(gen2drv);
      drv = new(vif, gen2drv);
      mon = new(vif, mon2scb);
      scb = new(mon2scb);
      // Wire up shared events
      gen.done       = gen_done;
      gen.reset_done = reset_done;
      drv.reset_done = reset_done;
    endfunction

    function void set_num_transactions(int n);
      gen.num_transactions = n;
    endfunction

    task run();
      fork
        gen.run();
        drv.run();
        mon.run();
        scb.run();
      join_none
      @(gen_done);
      #500;   // 500ns drain — let last transactions finish
      scb.report();
    endtask

  endclass

  //----------------------------------------------------------
  // Test
  //----------------------------------------------------------
  class rr_test;

    rr_environment env;

    function new(virtual rr_if vif);
      env = new(vif);
    endfunction

    task run();
      $display("\n[TEST] Starting RR Arbiter Test (TYPE=%0d, N=%0d, W=%0d)\n",
               `TYPE, `N, `W);
      env.set_num_transactions(100);
      env.run();
      $display("[TEST] Completed.");
    endtask

  endclass

endpackage
