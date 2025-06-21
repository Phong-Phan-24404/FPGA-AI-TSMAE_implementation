`timescale 1ns / 1ps

module decoder_LSTM_tb;

    // Parameters
    parameter DATA_WIDTH  = 32;
    parameter FRACT_WIDTH = 24;
    parameter INPUT_SIZE  = 10;
    parameter HIDDEN_SIZE = 10;
    parameter SEQ_LEN     = 10;
    parameter CLK_PERIOD  = 10;

    typedef logic signed [DATA_WIDTH-1:0] fxp_t;

    // DUT I/O
    logic clk;
    logic rst;
    logic start;
    fxp_t x      [SEQ_LEN][INPUT_SIZE];
    fxp_t h_out  [HIDDEN_SIZE];
    fxp_t x_hat  [SEQ_LEN][INPUT_SIZE];
    logic done;

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // Instantiate DUT
    decoder_LSTM #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACT_WIDTH(FRACT_WIDTH),
        .INPUT_SIZE(INPUT_SIZE),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .SEQ_LEN(SEQ_LEN)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x(x),
        .h_out(h_out),
        .x_hat(x_hat),
        .done(done)
    );

    // Convert Q8.24 to real
    function real fxp_to_real(input fxp_t val);
        return $itor(val) / (1 << FRACT_WIDTH);
    endfunction

    // Test procedure
    initial begin
        $display("=== TEST: decoder_LSTM + projection_layer ===");

        // Init signals
        clk = 0;
        rst = 1;
        start = 0;

        // Wait for reset
        #(5 * CLK_PERIOD);
        rst = 0;

        // Assign x[t][i] = (t + i)/10 in Q8.24
        for (int t = 0; t < SEQ_LEN; t++) begin
            for (int i = 0; i < INPUT_SIZE; i++) begin
                real val = (t + i) / 10.0;
                x[t][i] = fxp_t'(val * (1 << FRACT_WIDTH));
            end
        end

        // Start module
        #(2 * CLK_PERIOD);
        start = 1;
        #(1 * CLK_PERIOD);
        start = 0;

        // Wait for done
        wait (done);
        #(1 * CLK_PERIOD);

        // Display result
        $display("\n=== Output x_hat[t][0] (SEQ_LEN = %0d) ===", SEQ_LEN);
        for (int t = 0; t < SEQ_LEN; t++) begin
            $display("x_hat[%0d][0] = %0.6f", t, fxp_to_real(x_hat[t][0]));
        end

        $display("\n=== Final h_out ===");
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            $display("h_out[%0d] = %0.6f", i, fxp_to_real(h_out[i]));
        end

        $display("\n✅ DONE TEST");
        $stop;
    end

endmodule
