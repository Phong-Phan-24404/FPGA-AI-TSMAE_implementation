module decoder_LSTM_cell #(
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24,
   parameter INPUT_SIZE = 10,
    parameter HIDDEN_SIZE = 10
    
)(
    input  logic clk,
    input  logic reset,
    
    input  logic signed [DATA_WIDTH-1:0] x_t [INPUT_SIZE],
    input  logic signed [DATA_WIDTH-1:0] h_prev [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] c_prev [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] h_t [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] c_t [HIDDEN_SIZE],
    input  logic start,
    output logic done
   // output logic busy
);
    // Internal signals
    logic signed [DATA_WIDTH-1:0] W_ih_flat [4*HIDDEN_SIZE*INPUT_SIZE];
    logic signed [DATA_WIDTH-1:0] W_hh_flat [4*HIDDEN_SIZE*HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b_ih_flat [4*HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b_hh_flat [4*HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] W_ih [4][HIDDEN_SIZE][INPUT_SIZE];
    logic signed [DATA_WIDTH-1:0] W_hh [4][HIDDEN_SIZE][HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b_ih [4][HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b_hh [4][HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] gates [4][HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] i [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] f [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] g [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] o [HIDDEN_SIZE];
    logic compute_gates_start, compute_gates_done, compute_gates_busy;
    logic gate_computation_start, gate_computation_done, gate_computation_busy;
    
    // State machine states
    localparam IDLE = 0, COMPUTE_GATES = 1, GATE_COMPUTATION = 2, FINISH = 3;
    logic [1:0] state;

    // Load weights and biases from memory files
    initial begin
        $readmemh("W_ih_dec.mem", W_ih_flat);
        $readmemh("W_hh_dec.mem", W_hh_flat);
        $readmemh("b_ih_dec.mem", b_ih_flat);
        $readmemh("b_hh_dec.mem", b_hh_flat);
    end

    // Reshape flat arrays into multidimensional arrays
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                for (int k = 0; k < INPUT_SIZE; k++) begin
                    W_ih[i][j][k] = W_ih_flat[i*HIDDEN_SIZE*INPUT_SIZE + j*INPUT_SIZE + k];
                end
                b_ih[i][j] = b_ih_flat[i*HIDDEN_SIZE + j];
                b_hh[i][j] = b_hh_flat[i*HIDDEN_SIZE + j];
                for (int k = 0; k < HIDDEN_SIZE; k++) begin
                    W_hh[i][j][k] = W_hh_flat[i*HIDDEN_SIZE*HIDDEN_SIZE + j*HIDDEN_SIZE + k];
                end
            end
        end
    end

    // Instantiate compute_gates module
    compute_gates #(
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .INPUT_SIZE(INPUT_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) compute_gates_inst (
        .clk(clk),
        .reset(reset),
        .start(compute_gates_start),
        .W_ih(W_ih),
        .x_t(x_t),
        .W_hh(W_hh),
        .h_prev(h_prev),
        .b_ih(b_ih),
        .b_hh(b_hh),
        .gates(gates),
        .done(compute_gates_done),
        .busy(compute_gates_busy)
    );

    // Instantiate gate_computation module
    gate_computation #(
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) gate_computation_inst (
        .clk(clk),
        .reset(reset),
        .start(gate_computation_start),
        .gates(gates),
        .c_prev(c_prev),
        .i(i),
        .f(f),
        .g(g),
        .o(o),
        .c_t(c_t),
        .h_t(h_t),
        .done(gate_computation_done),
        .busy(gate_computation_busy)
    );

    // State machine
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
         //   busy <= 0;
            compute_gates_start <= 0;
            gate_computation_start <= 0;
            for (int k = 0; k < HIDDEN_SIZE; k++) begin
                h_t[k] <= 0;
                c_t[k] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= COMPUTE_GATES;
                      //  busy <= 1;
                        done <= 0;
                        compute_gates_start <= 1;
                    end
                end
                COMPUTE_GATES: begin
                    compute_gates_start <= 0;
                    if (compute_gates_done) begin
                        gate_computation_start <= 1;
                        state <= GATE_COMPUTATION;
                    end
                end
                GATE_COMPUTATION: begin
                    gate_computation_start <= 0;
                    if (gate_computation_done) begin
                        state <= FINISH;
                    end
                end
                FINISH: begin
                    done <= 1;
                 //   busy <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

module gate_computation #(
    parameter HIDDEN_SIZE = 10,
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic signed [DATA_WIDTH-1:0] gates [4][HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] c_prev [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] i [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] f [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] g [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] o [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] c_t [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] h_t [HIDDEN_SIZE],
    output logic done,
    output logic busy
);
    // State machine states
    localparam IDLE = 0, SIGMOID_TANH = 1, CALC_CT = 2, TANH_CT = 3, MUL_HT = 4, FINISH = 5;
    logic [2:0] state;
    
    // Internal signals
    logic [31:0] j; // Index for loop
    logic signed [DATA_WIDTH-1:0] sigmoid_i_in [HIDDEN_SIZE], sigmoid_f_in [HIDDEN_SIZE], sigmoid_o_in [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] sigmoid_i_out [HIDDEN_SIZE], sigmoid_f_out [HIDDEN_SIZE], sigmoid_o_out [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] tanh_g_in [HIDDEN_SIZE], tanh_ct_in [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] tanh_g_out [HIDDEN_SIZE], tanh_ct_out [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] mul_o_tanhct_a [HIDDEN_SIZE], mul_o_tanhct_b [HIDDEN_SIZE], mul_o_tanhct_out [HIDDEN_SIZE];
    logic sigmoid_i_start [HIDDEN_SIZE], sigmoid_i_done [HIDDEN_SIZE], sigmoid_i_ready [HIDDEN_SIZE];
    logic sigmoid_f_start [HIDDEN_SIZE], sigmoid_f_done [HIDDEN_SIZE], sigmoid_f_ready [HIDDEN_SIZE];
    logic sigmoid_o_start [HIDDEN_SIZE], sigmoid_o_done [HIDDEN_SIZE], sigmoid_o_ready [HIDDEN_SIZE];
    logic tanh_g_start [HIDDEN_SIZE], tanh_g_done [HIDDEN_SIZE], tanh_g_ready [HIDDEN_SIZE];
    logic tanh_ct_start [HIDDEN_SIZE], tanh_ct_done [HIDDEN_SIZE], tanh_ct_ready [HIDDEN_SIZE];
    logic calc_ct_start, calc_ct_done, calc_ct_busy;
    logic mul_o_tanhct_start [HIDDEN_SIZE], mul_o_tanhct_done [HIDDEN_SIZE], mul_o_tanhct_busy [HIDDEN_SIZE];
    
    // Instantiate sigmoid modules for i, f, o gates
    genvar k;
    generate
        for (k = 0; k < HIDDEN_SIZE; k++) begin : gen_sigmoid_tanh_mul
            sigmoid #(
                .DATA_WIDTH(DATA_WIDTH)
            ) sigmoid_i_inst (
                .clk(clk),
                .rst(reset),
                .start(sigmoid_i_start[k]),
                .done(sigmoid_i_done[k]),
                .ready(sigmoid_i_ready[k]),
                .x(sigmoid_i_in[k]),
                .y(sigmoid_i_out[k])
            );
            
            sigmoid #(
                .DATA_WIDTH(DATA_WIDTH)
            ) sigmoid_f_inst (
                .clk(clk),
                .rst(reset),
                .start(sigmoid_f_start[k]),
                .done(sigmoid_f_done[k]),
                .ready(sigmoid_f_ready[k]),
                .x(sigmoid_f_in[k]),
                .y(sigmoid_f_out[k])
            );
            
            sigmoid #(
                .DATA_WIDTH(DATA_WIDTH)
            ) sigmoid_o_inst (
                .clk(clk),
                .rst(reset),
                .start(sigmoid_o_start[k]),
                .done(sigmoid_o_done[k]),
                .ready(sigmoid_o_ready[k]),
                .x(sigmoid_o_in[k]),
                .y(sigmoid_o_out[k])
            );
            
            tanh #(
                .DATA_WIDTH(DATA_WIDTH)
            ) tanh_g_inst (
                .clk(clk),
                .rst(reset),
                .start(tanh_g_start[k]),
                .done(tanh_g_done[k]),
                .ready(tanh_g_ready[k]),
                .x(tanh_g_in[k]),
                .y(tanh_g_out[k])
            );
            
            tanh #(
                .DATA_WIDTH(DATA_WIDTH)
            ) tanh_ct_inst (
                .clk(clk),
                .rst(reset),
                .start(tanh_ct_start[k]),
                .done(tanh_ct_done[k]),
                .ready(tanh_ct_ready[k]),
                .x(tanh_ct_in[k]),
                .y(tanh_ct_out[k])
            );
            
            multiplier #(
                .DATA_WIDTH(DATA_WIDTH),
                .FRACTION_BITS(FRACTION_BITS)
            ) mul_o_tanhct_inst (
                .clk(clk),
                .reset(reset),
                .start(mul_o_tanhct_start[k]),
                .a(mul_o_tanhct_a[k]),
                .b(mul_o_tanhct_b[k]),
                .result(mul_o_tanhct_out[k]),
                .done(mul_o_tanhct_done[k]),
                .busy(mul_o_tanhct_busy[k])
            );
        end
    endgenerate

    // Instantiate calculate_ct module
    calculate_ct #(
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) calc_ct_inst (
        .clk(clk),
        .reset(reset),
        .start(calc_ct_start),
        .f(f),
        .c_prev(c_prev),
        .i(i),
        .g(g),
        .c_t(c_t),
        .done(calc_ct_done),
        .busy(calc_ct_busy)
    );

    // State machine
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
            j <= 0;
            calc_ct_start <= 0;
            for (int k = 0; k < HIDDEN_SIZE; k++) begin
                i[k] <= 0;
                f[k] <= 0;
                g[k] <= 0;
                o[k] <= 0;
                c_t[k] <= 0;
                h_t[k] <= 0;
                sigmoid_i_start[k] <= 0;
                sigmoid_f_start[k] <= 0;
                sigmoid_o_start[k] <= 0;
                tanh_g_start[k] <= 0;
                tanh_ct_start[k] <= 0;
                mul_o_tanhct_start[k] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= SIGMOID_TANH;
                        busy <= 1;
                        done <= 0;
                        j <= 0;
                        // Start sigmoid and tanh computations for all indices
                        for (int k = 0; k < HIDDEN_SIZE; k++) begin
                            sigmoid_i_in[k] <= gates[0][k];
                            sigmoid_f_in[k] <= gates[1][k];
                            tanh_g_in[k] <= gates[2][k];
                            sigmoid_o_in[k] <= gates[3][k];
                            sigmoid_i_start[k] <= 1;
                            sigmoid_f_start[k] <= 1;
                            tanh_g_start[k] <= 1;
                            sigmoid_o_start[k] <= 1;
                        end
                    end
                end
                SIGMOID_TANH: begin
                    // Check if all sigmoid and tanh computations are done
                    logic all_done = 1;
                    for (int k = 0; k < HIDDEN_SIZE; k++) begin
                        sigmoid_i_start[k] <= 0;
                        sigmoid_f_start[k] <= 0;
                        tanh_g_start[k] <= 0;
                        sigmoid_o_start[k] <= 0;
                        if (!sigmoid_i_done[k] || !sigmoid_f_done[k] || !tanh_g_done[k] || !sigmoid_o_done[k]) begin
                            all_done = 0;
                        end
                    end
                    if (all_done) begin
                        for (int k = 0; k < HIDDEN_SIZE; k++) begin
                            i[k] <= sigmoid_i_out[k];
                            f[k] <= sigmoid_f_out[k];
                            g[k] <= tanh_g_out[k];
                            o[k] <= sigmoid_o_out[k];
                        end
                        calc_ct_start <= 1;
                        state <= CALC_CT;
                    end
                end
                CALC_CT: begin
                    calc_ct_start <= 0;
                    if (calc_ct_done) begin
                        for (int k = 0; k < HIDDEN_SIZE; k++) begin
                            tanh_ct_in[k] <= c_t[k];
                            tanh_ct_start[k] <= 1;
                        end
                        state <= TANH_CT;
                    end
                end
                TANH_CT: begin
                    // Check if tanh(c_t) computations are done
                    logic all_tanh_done = 1;
                    for (int k = 0; k < HIDDEN_SIZE; k++) begin
                        tanh_ct_start[k] <= 0;
                        if (!tanh_ct_done[k]) begin
                            all_tanh_done = 0;
                        end
                    end
                    if (all_tanh_done) begin
                        for (int k = 0; k < HIDDEN_SIZE; k++) begin
                            mul_o_tanhct_a[k] <= o[k];
                            mul_o_tanhct_b[k] <= tanh_ct_out[k];
                            mul_o_tanhct_start[k] <= 1;
                        end
                        state <= MUL_HT;
                    end
                end
                MUL_HT: begin
                    // Check if multiplications for h_t are done
                    logic all_ht_done = 1;
                    for (int k = 0; k < HIDDEN_SIZE; k++) begin
                        mul_o_tanhct_start[k] <= 0;
                        if (!mul_o_tanhct_done[k]) begin
                            all_ht_done = 0;
                        end
                    end
                    if (all_ht_done) begin
                        for (int k = 0; k < HIDDEN_SIZE; k++) begin
                            h_t[k] <= mul_o_tanhct_out[k];
                        end
                        state <= FINISH;
                    end
                end
                FINISH: begin
                    done <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

module mat_vec_mul #(

    parameter HIDDEN_SIZE = 10,
    parameter INPUT_SIZE = 10,
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic signed [DATA_WIDTH-1:0] mat [HIDDEN_SIZE][INPUT_SIZE],
    input  logic signed [DATA_WIDTH-1:0] vec [INPUT_SIZE],
    output logic signed [DATA_WIDTH-1:0] result [HIDDEN_SIZE],
    output logic done,
    output logic busy
);
    // State machine states
    localparam IDLE = 0, MUL = 1, ACCUM = 2, SHIFT = 3, FINISH = 4;
    logic [2:0] state;
    
    // Internal signals
    logic signed [DATA_WIDTH-1:0] mul_a, mul_b, mul_result;
    logic mul_start, mul_done, mul_busy;
    logic signed [63:0] sum [HIDDEN_SIZE];
    logic [31:0] i, j; // Counters for rows and columns
    
    // Instantiate multiplier
    multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) mul_inst (
        .clk(clk),
        .reset(reset),
        .start(mul_start),
        .a(mul_a),
        .b(mul_b),
        .result(mul_result),
        .done(mul_done),
        .busy(mul_busy)
    );

 always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;
        done <= 0;
        busy <= 0;
        i <= 0;
        j <= 0;
        for (int k = 0; k < HIDDEN_SIZE; k++) begin
            sum[k] <= 0;
            result[k] <= 0;
        end
    end else begin
        case (state)
            IDLE: begin
                if (start) begin
                    state <= MUL;
                    busy <= 1;
                    done <= 0;
                    i <= 0;
                    j <= 0;
                    for (int k = 0; k < HIDDEN_SIZE; k++) begin
                        sum[k] <= 0;
                    end
                   
                end
            end

            MUL: begin
                if (!mul_busy && !mul_done) begin
                    mul_a <= mat[i][j];
                    mul_b <= vec[j];
                    mul_start <= 1;
                end else if (mul_done) begin
                    mul_start <= 0;
                    sum[i] <= sum[i] + mul_result;
                    j <= j + 1;
                    if (j == INPUT_SIZE - 1) begin
                        j <= 0;
                        i <= i + 1;
                        state <= ACCUM;
                    end
                end
            end

            ACCUM: begin
                if (i < HIDDEN_SIZE) begin
                    state <= MUL;
                end else begin
                    i <= 0;
                    state <= SHIFT;
                end
            end

            SHIFT: begin
                for (int k = 0; k < HIDDEN_SIZE; k++) begin
                    result[k] <= sum[k][31:0];
                end
                state <= FINISH;
            end
            

            FINISH: begin
                done <= 1;
                busy <= 0;
                state <= IDLE;
                $display("[FINISH] All results finalized.");
            end
        endcase
    end
end

endmodule

module compute_gates #(
    parameter HIDDEN_SIZE = 10,
    parameter INPUT_SIZE = 10,
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic signed [DATA_WIDTH-1:0] W_ih [4][HIDDEN_SIZE][INPUT_SIZE],
    input  logic signed [DATA_WIDTH-1:0] x_t [INPUT_SIZE],
    input  logic signed [DATA_WIDTH-1:0] W_hh [4][HIDDEN_SIZE][HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] h_prev [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] b_ih [4][HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] b_hh [4][HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] gates [4][HIDDEN_SIZE],
    output logic done,
    output logic busy
);
    // State machine states
    localparam IDLE = 0, MATMUL1 = 1, MATMUL2 = 2, ADD = 3, FINISH = 4;
    logic [2:0] state;
    
    // Internal signals
    logic signed [DATA_WIDTH-1:0] temp [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] matmul1_result [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] matmul2_result [HIDDEN_SIZE];
    logic matmul1_start, matmul1_done, matmul1_busy;
    logic matmul2_start, matmul2_done, matmul2_busy;
    logic [1:0] k; // Gate index (0 to 3)
    logic [31:0] i; // Index for addition loop
    
    // Instantiate two matrix-vector multipliers
    mat_vec_mul #(
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .INPUT_SIZE(INPUT_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) matmul1 (
        .clk(clk),
        .reset(reset),
        .start(matmul1_start),
        .mat(W_ih[k]),
        .vec(x_t),
        .result(matmul1_result),
        .done(matmul1_done),
        .busy(matmul1_busy)
    );
    
    mat_vec_mul #(
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .INPUT_SIZE(HIDDEN_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) matmul2 (
        .clk(clk),
        .reset(reset),
        .start(matmul2_start),
        .mat(W_hh[k]),
        .vec(h_prev),
        .result(matmul2_result),
        .done(matmul2_done),
        .busy(matmul2_busy)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
            k <= 0;
            i <= 0;
            for (int m = 0; m < 4; m++) begin
                for (int n = 0; n < HIDDEN_SIZE; n++) begin
                    gates[m][n] <= 0;
                end
            end
            for (int n = 0; n < HIDDEN_SIZE; n++) begin
                temp[n] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= MATMUL1;
                        busy <= 1;
                        done <= 0;
                        k <= 0;
                        i <= 0;
                    end
                end
        MATMUL1: begin
            if (!matmul1_busy && !matmul1_done) begin
                matmul1_start <= 1;
            end else if (matmul1_done) begin
                matmul1_start <= 0;
        
                // === DEBUG OUTPUT FOR matmul1_result ===
              //  $display("=== [MATMUL1 DONE] gate = %0d | W_ih × x_t ===", k);
             //   for (int n = 0; n < HIDDEN_SIZE; n++) begin
                //    $display("matmul1_result[%0d] = %0.6f (hex = %08h)",
                 //       n, $itor(matmul1_result[n]) / (1 << FRACTION_BITS), matmul1_result[n]);
              //  end
        
                for (int n = 0; n < HIDDEN_SIZE; n++) begin
                    gates[k][n] <= matmul1_result[n];
                end
                state <= MATMUL2;
            end
        end
        
        MATMUL2: begin
            if (!matmul2_busy && !matmul2_done) begin
                matmul2_start <= 1;
            end else if (matmul2_done) begin
                matmul2_start <= 0;
        
                // === DEBUG OUTPUT FOR matmul2_result ===
            //    $display("=== [MATMUL2 DONE] gate = %0d | W_hh × h_prev ===", k);
            //    for (int n = 0; n < HIDDEN_SIZE; n++) begin
                //    $display("matmul2_result[%0d] = %0.6f (hex = %08h)",
                //        n, $itor(matmul2_result[n]) / (1 << FRACTION_BITS), matmul2_result[n]);
             //   end
        
                for (int n = 0; n < HIDDEN_SIZE; n++) begin
                    temp[n] <= matmul2_result[n];
                end
                state <= ADD;
            end
        end
        
                        ADD: begin
                            if (i < HIDDEN_SIZE) begin
                                gates[k][i] <= gates[k][i] + temp[i] + b_ih[k][i] + b_hh[k][i];
                                i <= i + 1;
                            end else begin
                                i <= 0;
                                k <= k + 1;
                                if (k < 3) begin
                                    state <= MATMUL1;
                                end else begin
                                    state <= FINISH;
                                end
                            end
                        end
        FINISH: begin
            done <= 1;
            busy <= 0;
            state <= IDLE;
        end 

            endcase
        end
    end
endmodule

module calculate_ct #(
    parameter HIDDEN_SIZE = 10,
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic signed [DATA_WIDTH-1:0] f [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] c_prev [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] i [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] g [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] c_t [HIDDEN_SIZE],
    output logic done,
    output logic busy
);
    // State machine states
    localparam IDLE = 0, MUL1 = 1, MUL2 = 2, ADD = 3, FINISH = 4;
    logic [2:0] state;
    
    // Internal signals
    logic signed [DATA_WIDTH-1:0] mul1_a, mul1_b, mul1_result;
    logic signed [DATA_WIDTH-1:0] mul2_a, mul2_b, mul2_result;
    logic mul1_start, mul1_done, mul1_busy;
    logic mul2_start, mul2_done, mul2_busy;
    logic [31:0] j; // Index for loop
    logic signed [DATA_WIDTH-1:0] mul1_temp [HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] mul2_temp [HIDDEN_SIZE];
    
    // Instantiate two multipliers
    multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) mul1 (
        .clk(clk),
        .reset(reset),
        .start(mul1_start),
        .a(mul1_a),
        .b(mul1_b),
        .result(mul1_result),
        .done(mul1_done),
        .busy(mul1_busy)
    );
    
    multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACTION_BITS)
    ) mul2 (
        .clk(clk),
        .reset(reset),
        .start(mul2_start),
        .a(mul2_a),
        .b(mul2_b),
        .result(mul2_result),
        .done(mul2_done),
        .busy(mul2_busy)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
            j <= 0;
            for (int k = 0; k < HIDDEN_SIZE; k++) begin
                c_t[k] <= 0;
                mul1_temp[k] <= 0;
                mul2_temp[k] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= MUL1;
                        busy <= 1;
                        done <= 0;
                        j <= 0;
                    end
                end
                MUL1: begin
                    if (!mul1_busy && !mul1_done) begin
                        mul1_a <= f[j];
                        mul1_b <= c_prev[j];
                        mul1_start <= 1;
                    end else if (mul1_done) begin
                        mul1_start <= 0;
                        mul1_temp[j] <= mul1_result;
                        state <= MUL2;
                    end
                end
                MUL2: begin
                    if (!mul2_busy && !mul2_done) begin
                        mul2_a <= i[j];
                        mul2_b <= g[j];
                        mul2_start <= 1;
                    end else if (mul2_done) begin
                        mul2_start <= 0;
                        mul2_temp[j] <= mul2_result;
                        state <= ADD;
                    end
                end
                ADD: begin
                    c_t[j] <= mul1_temp[j] + mul2_temp[j];
                    j <= j + 1;
                    if (j < HIDDEN_SIZE - 1) begin
                        state <= MUL1;
                    end else begin
                        state <= FINISH;
                    end
                end
                FINISH: begin
                    done <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

