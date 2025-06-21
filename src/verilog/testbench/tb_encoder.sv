`timescale 1ns / 1ps
module encoder_LSTM_tb;

    // Parameters
    parameter int DATA_WIDTH  = 32;
    parameter int FRACT_WIDTH = 24;
    parameter int HIDDEN_SIZE = 10;
    parameter int SEQ_LEN     = 5;
    parameter int NUM_FEATURES = 1;
    parameter int TIMEOUT_CYCLES = 1000000;
    parameter real SCALE      = 1 << FRACT_WIDTH; // For fixed-point conversion

    // Signals
    logic clk;
    logic rst;
    logic start;
    logic signed [DATA_WIDTH-1:0] x [SEQ_LEN][NUM_FEATURES];
    logic signed [DATA_WIDTH-1:0] h_out [HIDDEN_SIZE];
    logic done;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // Instantiate DUT
    encoder_LSTM #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACT_WIDTH(FRACT_WIDTH),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .SEQ_LEN(SEQ_LEN),
        .NUM_FEATURES(NUM_FEATURES),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x(x),
        .h_out(h_out),
        .done(done)
    );

    // Test stimulus
    initial begin
        // Initialize signals
        rst = 1;
        start = 0;
        for (int t = 0; t < SEQ_LEN; t++) begin
            for (int f = 0; f < NUM_FEATURES; f++) begin
                x[t][f] = 0;
            end
        end

        // Reset pulse
        #20 rst = 0;
        #10;

        // Example input sequence (Q8.24)
        // Example: x[t][0] = 0.2819640636 for all t
        for (int t = 0; t < SEQ_LEN; t++) begin
            x[t][0] = 32'sd4728976; // 0.2819640636
        end

        // Display inputs
        $display("\nInput Sequence:");
        for (int t = 0; t < SEQ_LEN; t++) begin
            $write("x[%0d] = [", t);
            for (int f = 0; f < NUM_FEATURES; f++) begin
                $write("%0.10f", $itor(x[t][f]) / SCALE);
                if (f < NUM_FEATURES-1) $write(", ");
            end
            $display("]");
        end

        // Start computation
        #10 start = 1;
        #10 start = 0;

        // Wait for done or timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk) begin
            if (done) break;
        end

        // Wait one additional clock cycle to ensure h_out is updated
        @(posedge clk);

        // Check if computation completed
        if (done) begin
            $display("\nOutput Values:");
            $write("h_out = [");
            for (int i = 0; i < HIDDEN_SIZE; i++) begin
                $write("%0.10f", $itor(h_out[i]) / SCALE);
                if (i < HIDDEN_SIZE-1) $write(", ");
            end
            $display("]");
        end else begin
            $display("\nError: Computation timed out!");
        end

        // Finish simulation
        #20 $finish;
    end

endmodule