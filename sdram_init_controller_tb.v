`timescale 1ns / 1ps

module sdram_init_controller_tb;

    // DUT Specific Parameter (Override for quick test, or keep default)
    // Shorter delay for faster simulation
    localparam INIT_POWER_UP_DELAY_CYCLES_TB = 10; 

    // Clock period definition
    localparam HCLK_PERIOD = 10; // 10ns for 100MHz clock

    // Testbench signals (wires and regs)
    reg HCLK;
    reg HRESETn;
    reg sdram_ready_i;
    reg sdram_init_ack_i;
    wire init_start_o;

    // Instantiate the Unit Under Test (DUT)
    sdram_init_controller #(
        .INIT_POWER_UP_DELAY_CYCLES(INIT_POWER_UP_DELAY_CYCLES_TB)
    ) dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .sdram_ready_i(sdram_ready_i),
        .sdram_init_ack_i(sdram_init_ack_i),
        .init_start_o(init_start_o)
    );

    // Clock Generation
    always #((HCLK_PERIOD / 2)) HCLK = ~HCLK;

    // Test sequence
    initial begin
        // Initialize inputs
        HCLK = 0;
        HRESETn = 0; // Assert reset
        sdram_ready_i = 0; // SDRAM FSM initially not ready
        sdram_init_ack_i = 0; // No acknowledgment yet

        $display("--------------------------------------------------");
        $display("Starting SDRAM Init Controller Testbench");
        $display("Initial Power-Up Delay: %0d cycles", INIT_POWER_UP_DELAY_CYCLES_TB);
        $display("HCLK Period: %0d ns", HCLK_PERIOD);
        $display("--------------------------------------------------");

        @(posedge HCLK);
        #1; // Small delay after clock edge to ensure stable values for reset
        HRESETn = 1; // De-assert reset, start normal operation

        $display("\nTime %0t: HRESETn de-asserted. Timer starts counting.", $time);

        // --- Scenario 1: Normal Initialization ---

        // Wait for the power-up delay to complete
        // The DUT internal timer will count down
        repeat (INIT_POWER_UP_DELAY_CYCLES_TB + 2) @(posedge HCLK); // +2 for stability and to see init_start_o rise

        $display("\nTime %0t: Power-up delay expected to be over.", $time);
        // At this point, init_timer should be 0.
        // init_start_o will assert high if sdram_ready_i is high.

        // Make sdram_ready_i high to allow init_start_o to assert
        @(posedge HCLK); // Wait one cycle after timer hits zero before asserting ready
        sdram_ready_i = 1;
        $display("Time %0t: sdram_ready_i asserted high.", $time);

        @(posedge HCLK); // Wait for init_start_o to assert
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        if (init_start_o == 1) begin
            $display("Time %0t: PASS: init_start_o asserted after delay and sdram_ready_i.", $time);
        end else begin
            $display("Time %0t: FAIL: init_start_o did not assert as expected.", $time);
            $finish; // End simulation on failure
        end

        // Simulate SDRAM FSM acknowledging the init start
        @(posedge HCLK);
        sdram_init_ack_i = 1;
        $display("Time %0t: sdram_init_ack_i asserted high.", $time);

        @(posedge HCLK); // Wait for init_start_o to de-assert and init_done to set
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        if (init_start_o == 0) begin
            $display("Time %0t: PASS: init_start_o de-asserted after acknowledgment.", $time);
        end else begin
            $display("Time %0t: FAIL: init_start_o did not de-assert after acknowledgment.", $time);
            $finish;
        end

        // Check if init_done is set (cannot directly access, but implies correct behavior)
        // We can infer init_done from init_start_o remaining low afterwards
        $display("Time %0t: Initialization sequence completed. init_start_o should remain low now.", $time);
        @(posedge HCLK);
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        @(posedge HCLK);
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        sdram_ready_i = 0; // Reset ready signal

        // --- Scenario 2: Test re-initialization (should not happen without reset) ---
        $display("\nTime %0t: Attempting to re-initiate without reset. Should not happen.", $time);
        sdram_ready_i = 1;
        @(posedge HCLK);
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        @(posedge HCLK);
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        sdram_ready_i = 0;
        if (init_start_o == 0) begin
            $display("Time %0t: PASS: init_start_o remained low, preventing re-initialization.", $time);
        end else begin
            $display("Time %0t: FAIL: init_start_o asserted unexpectedly for re-initialization.", $time);
            $finish;
        end

        // --- Scenario 3: Reset and delayed sdram_ready_i ---
        $display("\nTime %0t: Asserting reset again.", $time);
        HRESETn = 0;
        @(posedge HCLK);
        #1;
        HRESETn = 1;
        sdram_init_ack_i = 0; // Clear ack for new sequence
        $display("Time %0t: HRESETn de-asserted. Timer starts counting again.", $time);

        // Wait for part of the delay
        repeat (INIT_POWER_UP_DELAY_CYCLES_TB / 2) @(posedge HCLK);
        sdram_ready_i = 0; // Keep sdram_ready_i low for now

        $display("Time %0t: Passed half the delay. sdram_ready_i is currently low.", $time);

        // Wait for the rest of the delay
        repeat (INIT_POWER_UP_DELAY_CYCLES_TB / 2 + 2) @(posedge HCLK);

        $display("Time %0t: Power-up delay over. init_start_o should still be low because sdram_ready_i is low.", $time);
        @(posedge HCLK);
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        if (init_start_o == 0) begin
            $display("Time %0t: PASS: init_start_o correctly held low as sdram_ready_i is low.", $time);
        end else begin
            $display("Time %0t: FAIL: init_start_o asserted prematurely.", $time);
            $finish;
        end

        // Now assert sdram_ready_i
        @(posedge HCLK);
        sdram_ready_i = 1;
        $display("Time %0t: sdram_ready_i asserted high (delayed).", $time);

        @(posedge HCLK);
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        if (init_start_o == 1) begin
            $display("Time %0t: PASS: init_start_o asserted after delayed sdram_ready_i.", $time);
        end else begin
            $display("Time %0t: FAIL: init_start_o did not assert after delayed sdram_ready_i.", $time);
            $finish;
        end

        // Acknowledge the init start
        @(posedge HCLK);
        sdram_init_ack_i = 1;
        $display("Time %0t: sdram_init_ack_i asserted high.", $time);

        @(posedge HCLK);
        $display("Time %0t: init_start_o = %b", $time, init_start_o);
        if (init_start_o == 0) begin
            $display("Time %0t: PASS: init_start_o de-asserted after delayed acknowledgment.", $time);
        end else begin
            $display("Time %0t: FAIL: init_start_o did not de-assert after delayed acknowledgment.", $time);
            $finish;
        end

        $display("\n--------------------------------------------------");
        $display("All test scenarios completed.");
        $display("--------------------------------------------------");
        $finish; // End simulation
    end

    // Optional: Monitor signals for waveform viewing
    initial begin
        $dumpfile("sdram_init_controller.vcd");
        $dumpvars(0, sdram_init_controller_tb);
    end

endmodule