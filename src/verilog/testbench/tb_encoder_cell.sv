`timescale 1ns / 1ps

module lstm_cell_tb;

    // Parameters matching module and Python code
    parameter int DATA_WIDTH  = 32;
    parameter int FRACT_WIDTH = 24;
    parameter int HIDDEN_SIZE = 10;
    parameter int TIMEOUT_CYCLES = 1000000;
    parameter real SCALE      = 1 << FRACT_WIDTH; // For fixed-point conversion

    // Signals
    logic clk;
    logic rst;
    logic start;
    logic signed [DATA_WIDTH-1:0] x_t;
    logic signed [DATA_WIDTH-1:0] h_prev [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] c_prev [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] h_out [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] c_out [HIDDEN_SIZE];
    logic done;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // Instantiate DUT
    LSTM_cell #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACT_WIDTH(FRACT_WIDTH),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .x_t(x_t),
        .h_prev(h_prev),
        .c_prev(c_prev),
        .h_out(h_out),
        .c_out(c_out),
        .start(start),
        .done(done)
    );

    // Test stimulus
    initial begin
        // Initialize signals
        rst = 1;
        start = 0;
        x_t = 0;
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            h_prev[i] = 0;
            c_prev[i] = 0;
        end

        // Reset pulse
        #20 rst = 0;
        #10;

// x_t = 0.2819640636
x_t = 32'sd4728976;

// h_prev[] (Q8.24)
h_prev[0] =  32'sd1653732;   // 0.0985327139
h_prev[1] = -32'sd428580;    // -0.025554616
h_prev[2] =  32'sd990660;    // 0.0590863079
h_prev[3] =  32'sd768146;    // 0.0457760394
h_prev[4] =  32'sd796628;    // 0.0474620163
h_prev[5] = -32'sd415225;    // -0.0247544628
h_prev[6] = -32'sd1438485;   // -0.0857528001
h_prev[7] =  32'sd460001;    // 0.0274231341
h_prev[8] = -32'sd923258;    // -0.0550349578
h_prev[9] =  32'sd232240;    // 0.0138418945

// c_prev[] (Q8.24)
c_prev[0] =  32'sd3780317;   // 0.2253876477
c_prev[1] = -32'sd965012;    // -0.0575771667
c_prev[2] =  32'sd2660597;   // 0.1584128141
c_prev[3] =  32'sd1355008;   // 0.0807871073
c_prev[4] =  32'sd1456175;   // 0.0867768303
c_prev[5] = -32'sd747569;    // -0.0445386134
c_prev[6] = -32'sd3086574;   // -0.1839655191
c_prev[7] =  32'sd911863;    // 0.054315839
c_prev[8] = -32'sd1579194;   // -0.094157435
c_prev[9] =  32'sd464143;    // 0.0276818946


        // Display inputs
        $display("\nInput Values:");
        $display("x_t = %0.4f", $itor(x_t) / SCALE);
        $write("h_prev = [");
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            $write("%0.4f", $itor(h_prev[i]) / SCALE);
            if (i < HIDDEN_SIZE-1) $write(", ");
        end
        $display("]");
        $write("c_prev = [");
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            $write("%0.4f", $itor(c_prev[i]) / SCALE);
            if (i < HIDDEN_SIZE-1) $write(", ");
        end
        $display("]");

        // Start computation
        #10 start = 1;
        #10 start = 0;

        // Wait for done or timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk) begin
            if (done) break;
        end

        // Check if computation completed
        if (done) begin
            $display("\nOutput Values:");
            $write("h_out = [");
            for (int i = 0; i < HIDDEN_SIZE; i++) begin
                $write("%0.4f", $itor(h_out[i]) / SCALE);
                if (i < HIDDEN_SIZE-1) $write(", ");
            end
            $display("]");
            $write("c_out = [");
            for (int i = 0; i < HIDDEN_SIZE; i++) begin
                $write("%0.4f", $itor(c_out[i]) / SCALE);
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