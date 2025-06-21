`timescale 1ns / 1ps
module decoder_LSTM_cell_tb;

    parameter int DATA_WIDTH  = 32;
    parameter int FRACT_WIDTH = 24;
    parameter int INPUT_SIZE  = 10;
    parameter int HIDDEN_SIZE = 10;

    logic clk, rst, start, done;
    logic signed [DATA_WIDTH-1:0] x_t [INPUT_SIZE];
    logic signed [DATA_WIDTH-1:0] h_prev [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] c_prev [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] h_out [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] c_out [HIDDEN_SIZE];

    decoder_LSTM_cell dut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .x_t(x_t), .h_prev(h_prev), .c_prev(c_prev),
        .h_out(h_out), .c_out(c_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1; start = 0;
        #20 rst = 0;

        // Input vector x_t (fixed-point Q8.24)
        x_t[0] = 32'hfff5f212;
        x_t[1] = 32'hfffd2cd5;
        x_t[2] = 32'h00028982;
        x_t[3] = 32'hfffc4bc9;
        x_t[4] = 32'hfffd138b;
        x_t[5] = 32'hffffc63b;
        x_t[6] = 32'hffff58a3;
        x_t[7] = 32'h00020cfe;
        x_t[8] = 32'hfff91673;
        x_t[9] = 32'hfffefc7e;
        


        // h_prev = 0
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            h_prev[i] = 32'h00000000;
            c_prev[i] = 32'h00000000;
        end

        // Start pulse
        #10 start = 1;
        #10 start = 0;

        // Wait for done
        wait(done);

$display("h_out (float):");
for (int i = 0; i < HIDDEN_SIZE; i++) begin
    real h_val = $itor($signed(h_out[i])) / 16777216.0;
    $display("%0d: %f", i, h_val);
end


        $finish;
    end
endmodule
