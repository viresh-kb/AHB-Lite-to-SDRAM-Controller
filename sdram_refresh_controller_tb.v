`timescale 1ns / 1ps
// sdram_refresh_controller_tb.sv
// Testbench for the sdram_refresh_controller module.

module sdram_refresh_controller_tb;

    // Parameters for the testbench
    parameter HCLK_PERIOD = 10; // 10ns for 100MHz HCLK
    parameter T_REFRESH_INTERVAL_CYCLES_TB = 782; // Must match the DUT's parameter

    // Declare signals for DUT inputs
    reg HCLK;
    reg HRESETn;
    reg sdram_ready_i;

    // Declare wire for DUT outputs
    wire refresh_req_o;

    // Instantiate the Device Under Test (DUT)
    sdram_refresh_controller #(
        .T_REFRESH_INTERVAL_CYCLES(T_REFRESH_INTERVAL_CYCLES_TB)
    ) dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .sdram_ready_i(sdram_ready_i),
        .refresh_req_o(refresh_req_o)
    );

    // Clock generation
    initial begin
        HCLK = 1'b0;
        forever #(HCLK_PERIOD / 2) HCLK = ~HCLK;
    end

    // Test sequence
    initial begin
        $display("-----------------------------------------------------");
        $display("Starting SDRAM Refresh Controller Testbench");
        $display("T_REFRESH_INTERVAL_CYCLES = %0d", T_REFRESH_INTERVAL_CYCLES_TB);
        $display("-----------------------------------------------------");

        // 1. Initial Reset State
        HRESETn = 1'b0; // Assert active-low reset
        sdram_ready_i = 1'b0; // SDRAM not ready initially
        #(HCLK_PERIOD * 5); // Hold reset for a few clock cycles
        $display("[%0t] After reset, refresh_req_o = %b", $time, refresh_req_o);
        // Expected: refresh_req_o should be 0

        // 2. De-assert Reset and allow normal operation
        HRESETn = 1'b1; // De-assert reset
        sdram_ready_i = 1'b1; // Assume SDRAM is ready for now
        $display("[%0t] De-asserted HRESETn. SDRAM is ready.", $time);

        // Wait for the first refresh request
        // The timer starts from 0, so it will reach 0 immediately and request refresh
        // then reload. The first actual request will be after T_REFRESH_INTERVAL_CYCLES - 1
        // (if the timer is loaded with T_REFRESH_INTERVAL_CYCLES - 1)
        // Or, if loaded with T_REFRESH_INTERVAL_CYCLES, it will be after T_REFRESH_INTERVAL_CYCLES
        // Let's observe the behavior based on the DUT's logic:
        // refresh_timer <= T_REFRESH_INTERVAL_CYCLES - 1;
        // So, the first request should come after T_REFRESH_INTERVAL_CYCLES cycles.

        @(posedge HCLK); // Wait one clock cycle after reset de-assertion
        $display("[%0t] Initial state after reset de-assertion. refresh_req_o = %b", $time, refresh_req_o);

        // Wait for the timer to expire and refresh_req_o to go high
        repeat (T_REFRESH_INTERVAL_CYCLES_TB + 5) @(posedge HCLK); // Add some buffer cycles
        $display("[%0t] After %0d cycles, refresh_req_o = %b", $time, T_REFRESH_INTERVAL_CYCLES_TB, refresh_req_o);
        // Expected: refresh_req_o should be 1'b1 for one cycle

        @(posedge HCLK);
        $display("[%0t] Next cycle, refresh_req_o = %b", $time, refresh_req_o);
        // Expected: refresh_req_o should be 1'b0 after one cycle

        // 3. Test scenario: SDRAM not ready when refresh is due
        $display("-----------------------------------------------------");
        $display("[%0t] Testing scenario: SDRAM not ready", $time);
        sdram_ready_i = 1'b0; // Make SDRAM not ready
        $display("[%0t] sdram_ready_i set to 0.", $time);

        // Wait for the timer to expire again
        repeat (T_REFRESH_INTERVAL_CYCLES_TB + 5) @(posedge HCLK);
        $display("[%0t] Timer expired, sdram_ready_i is 0. refresh_req_o = %b", $time, refresh_req_o);
        // Expected: refresh_req_o should still be 0

        // Now, make SDRAM ready and see if refresh_req_o asserts
        sdram_ready_i = 1'b1;
        $display("[%0t] sdram_ready_i set to 1. Waiting for refresh_req_o.", $time);
        @(posedge HCLK);
        $display("[%0t] After sdram_ready_i goes high, refresh_req_o = %b", $time, refresh_req_o);
        // Expected: refresh_req_o should be 1'b1 for one cycle

        @(posedge HCLK);
        $display("[%0t] Next cycle, refresh_req_o = %b", $time, refresh_req_o);
        // Expected: refresh_req_o should be 1'b0

        // 4. Observe a few more refresh cycles for continuous operation
        $display("-----------------------------------------------------");
        $display("[%0t] Observing continuous refresh cycles...", $time);
        sdram_ready_i = 1'b1; // Keep SDRAM ready

        for (integer i = 0; i < 3; i=i+1) begin
            repeat (T_REFRESH_INTERVAL_CYCLES_TB) @(posedge HCLK);
            $display("[%0t] Refresh cycle %0d: refresh_req_o = %b", $time, i+1, refresh_req_o);
            // Expected: refresh_req_o should be 1'b1
            @(posedge HCLK);
            $display("[%0t] Refresh cycle %0d (next): refresh_req_o = %b", $time, i+1, refresh_req_o);
            // Expected: refresh_req_o should be 1'b0
        end

        $display("-----------------------------------------------------");
        $display("[%0t] Testbench finished.", $time);
        $finish; // End simulation
    end

    // Monitor signals (optional, but good for debugging)
    initial begin
        $monitor("Time: %0t | HCLK: %b | HRESETn: %b | sdram_ready_i: %b | refresh_req_o: %b | refresh_timer (DUT): %0d",
                 $time, HCLK, HRESETn, sdram_ready_i, refresh_req_o, dut.refresh_timer);
    end

endmodule