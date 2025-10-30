`timescale 1ns/1ps
`default_nettype none

// Testbench for tt_um_VHDL_PWM_DEMUX (10-bit PWM with compact config demux)
// Drives the TinyTapeout-style IOs, tests atomic commit,
// same-cycle write+commit, shifted and wrap-around PWM windows.
//
// Save as: test/tb.v

module tb;

  // TinyTapeout harness pins
  reg  [7:0] ui_in;
  wire [7:0] uo_out;
  reg  [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg        ena;
  reg        clk;
  reg        rst_n;

  // DUT (VHDL entity exposed as a Verilog module by mixed-language simulators)
  tt_um_VHDL_PWM_DEMUX dut (
    .ui_in  (ui_in),
    .uo_out (uo_out),
    .uio_in (uio_in),
    .uio_out(uio_out),
    .uio_oe (uio_oe),
    .ena    (ena),
    .clk    (clk),
    .rst_n  (rst_n)
  );

  // Clock: 10 MHz (100 ns period)
  initial clk = 1'b0;
  always #50 clk = ~clk;

  // Convenience alias
  wire pwm = uo_out[0];

  // -----------------------------
  // Stimulus helpers
  // -----------------------------

  // Pack 10-bit data onto uio_in[5:4] (MSBs) and ui_in[7:0] (LSBs)
  task set_data10(input [9:0] d);
    begin
      uio_in[5:4] = d[9:8];
      ui_in       = d[7:0];
    end
  endtask

  // Select which shadow to write: 00=set, 01=clear, 10=reload
  task set_sel(input [1:0] s);
    begin
      uio_in[1:0] = s;
    end
  endtask

  // 1-cycle strobes
  task pulse_wr;
    begin
      uio_in[2] = 1'b1;
      @(posedge clk);
      uio_in[2] = 1'b0;
    end
  endtask

  task pulse_commit;
    begin
      uio_in[3] = 1'b1;
      @(posedge clk);
      uio_in[3] = 1'b0;
    end
  endtask

  // Write one field to SHADOW (no commit)
  task write_shadow(input [9:0] data, input [1:0] sel);
    begin
      set_data10(data);
      set_sel(sel);
      pulse_wr();
    end
  endtask

  // Write and commit in the SAME CYCLE
  task write_and_commit_same_cycle(input [9:0] data, input [1:0] sel);
    begin
      set_data10(data);
      set_sel(sel);
      uio_in[2] = 1'b1; // wr
      uio_in[3] = 1'b1; // commit
      @(posedge clk);
      uio_in[2] = 1'b0;
      uio_in[3] = 1'b0;
    end
  endtask

  // Compute expected number of high ticks in one full period
  function integer expected_high(input integer setv, input integer clrv, input integer reload);
    begin
      if (setv <= clrv)
        expected_high = clrv - setv;
      else
        expected_high = (reload + 1 - setv) + clrv; // wrap-around window
    end
  endfunction

  // Measure PWM high ticks over exactly (reload+1) cycles and compare
  task check_pwm_window(input integer setv, input integer clrv, input integer reload, input [127:0] tag);
    integer i, highs, period;
    integer exp;
    begin
      period = reload + 1;
      exp    = expected_high(setv, clrv, reload);

      // Let new actives take effect
      @(posedge clk);

      highs = 0;
      for (i = 0; i < period; i = i + 1) begin
        @(posedge clk);
        if (pwm) highs = highs + 1;
      end

      if (highs !== exp) begin
        $display("[%0t] %s: FAIL  highs=%0d exp=%0d  (set=%0d clr=%0d reload=%0d)",
                 $time, tag, highs, exp, setv, clrv, reload);
        $finish;
      end else begin
        $display("[%0t] %s: PASS  highs=%0d == exp=%0d  (set=%0d clr=%0d reload=%0d)",
                 $time, tag, highs, exp, setv, clrv, reload);
      end
    end
  endtask

  // -----------------------------
  // Test sequence
  // -----------------------------
  initial begin
    // Wave dump (ignored by some sims, harmless)
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);

    // Defaults
    ui_in  = 8'h00;
    uio_in = 8'h00;
    ena    = 1'b0;
    rst_n  = 1'b0;

    // Bring up
    repeat (5) @(posedge clk);
    ena   = 1'b1;
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // -----------------------------
    // T1: 50% duty, reload=1023, set=0, clr=512
    // -----------------------------
    write_shadow(10'd1023, 2'b10); // RELOAD
    write_shadow(10'd0,    2'b00); // SET
    write_shadow(10'd512,  2'b01); // CLEAR
    pulse_commit();
    check_pwm_window(0, 512, 1023, "T1 50% duty");

    // -----------------------------
    // T2: shifted window (width=600), set=300, clr=900
    // -----------------------------
    write_shadow(10'd300,  2'b00); // SET
    write_shadow(10'd900,  2'b01); // CLEAR
    pulse_commit();
    check_pwm_window(300, 900, 1023, "T2 shifted window");

    // -----------------------------
    // T3: wrap-around window, set=900, clr=100 (width=224)
    // -----------------------------
    write_shadow(10'd900,  2'b00); // SET
    write_shadow(10'd100,  2'b01); // CLEAR
    pulse_commit();
    check_pwm_window(900, 100, 1023, "T3 wrap-around");

    // -----------------------------
    // T4: same-cycle write+commit on last field
    // set=10, clr=20, reload=255 (commit same cycle as reload write)
    // -----------------------------
    write_shadow(10'd10,   2'b00); // SET
    write_shadow(10'd20,   2'b01); // CLEAR
    write_and_commit_same_cycle(10'd255, 2'b10); // RELOAD + COMMIT
    check_pwm_window(10, 20, 255, "T4 same-cycle wr+commit");

    // -----------------------------
    // T5: reserved sel="11" during wr (should be ignored)
    // -----------------------------
    set_data10(10'd123);
    set_sel(2'b11);
    pulse_wr(); // ignored by design; sim-time warning may appear from VHDL

    $display("[%0t] All tests done.", $time);
    $finish;
  end

endmodule

`default_nettype wire
