`timescale 1ns / 1ps

module TSMAE_tb;

    // Parameters
    localparam int DATA_WIDTH = 32;
    localparam int FRACT_WIDTH = 24;
    localparam int HIDDEN_SIZE = 10;
    localparam int INPUT_SIZE = 1;
    localparam int SEQ_LEN = 10;
    localparam int MEMORY_SIZE = 10;
    localparam int TIMEOUT_CYCLES = 15000000;
    localparam real SCALE = 2.0**FRACT_WIDTH;

    // Signals
    logic clk;
    logic rst;
    logic start;
    logic done;
    logic signed [DATA_WIDTH-1:0] x [SEQ_LEN][INPUT_SIZE];
    logic signed [DATA_WIDTH-1:0] x_recon [SEQ_LEN][INPUT_SIZE];
    logic signed [DATA_WIDTH-1:0] q [MEMORY_SIZE];
    logic signed [DATA_WIDTH-1:0] z [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] z_hat [HIDDEN_SIZE];

    // Instantiate TSMAE
    TSMAE #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACT_WIDTH(FRACT_WIDTH),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .INPUT_SIZE(INPUT_SIZE),
        .SEQ_LEN(SEQ_LEN),
        .MEMORY_SIZE(MEMORY_SIZE),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x(x),
        .x_recon(x_recon),
        .q(q),
        .z(z),
        .z_hat(z_hat),
        .done(done)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test procedure
    initial begin
        rst = 1;
        start = 0;
        for (int t = 0; t < SEQ_LEN; t++) begin
            x[t][0] = 0;
        end
        #20;
        rst = 0;
        $display("RST = %b at time %0t", rst, $time);

x[0][0] = 32'h00c7b4fb; // 0.78010529
x[1][0] = 32'h0050a84e; // 0.31506816
x[2][0] = 32'h00ef2b37; // 0.93425316
x[3][0] = 32'h01000000; // 1.00000000
x[4][0] = 32'h00000000; // 0.00000000
x[5][0] = 32'h003971d7; // 0.22439331
x[6][0] = 32'h00b80c32; // 0.71893609
x[7][0] = 32'h0090bb61; // 0.56535918
x[8][0] = 32'h00ab3e00; // 0.66891479
x[9][0] = 32'h0061352c; // 0.37971756


        // Print input x
        $display("\n==================== INPUT ====================");
        for (int t = 0; t < SEQ_LEN; t++) begin
            $display("x[%0d][0] = %0.6f", t, $itor(x[t][0]) / SCALE);
        end

        // Start TSMAE
        #10; start = 1;
        #10; start = 0;

        // Wait for completion
        repeat (TIMEOUT_CYCLES) @(posedge clk) begin
            if (done) break;
        end
        if (!done) begin
            $display("ERROR: Timeout after %0d cycles", TIMEOUT_CYCLES);
            $finish;
        end

        // Print outputs and debug information
if (done) begin
    $display("\n================== OUTPUT ====================");
    $display("x_recon[%0d][0] = %0.6f", 0, $itor(x_recon[0][0]) / SCALE);
    for (int t = 1; t < SEQ_LEN; t++) begin
        real val = $itor(x_recon[t][0]) / (1 << FRACT_WIDTH);
        real scaled_val = val ;
        $display("x_recon[%0d][0] = %0.6f", t, scaled_val);
    end
end


        $display("\nTest completed.");
        $finish;
    end

endmodule