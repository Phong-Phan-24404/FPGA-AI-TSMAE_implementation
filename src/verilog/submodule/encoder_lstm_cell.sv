`timescale 1ns / 1ps
module LSTM_cell #(
    parameter int DATA_WIDTH  = 32,
    parameter int FRACT_WIDTH = 24,
    parameter int HIDDEN_SIZE = 10,
    parameter int TIMEOUT_CYCLES = 10000
)(
    input  logic                clk,
    input  logic                rst,
    input  logic signed [DATA_WIDTH-1:0] x_t,
    input  logic signed [DATA_WIDTH-1:0] h_prev [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] c_prev [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] h_out [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] c_out [HIDDEN_SIZE],
    input  logic                start,
    output logic                done
);

    // Typedefs for fixed-point
    typedef logic signed [DATA_WIDTH-1:0] fxp_t;
    typedef logic signed [(DATA_WIDTH*2)-1:0] fxp_ext_t;

    // Raw gate signals
    fxp_t i_raw [HIDDEN_SIZE];
    fxp_t f_raw [HIDDEN_SIZE];
    fxp_t g_raw [HIDDEN_SIZE];
    fxp_t o_raw [HIDDEN_SIZE];
    fxp_t i_fp [HIDDEN_SIZE];
    fxp_t f_fp [HIDDEN_SIZE];
    fxp_t g_fp [HIDDEN_SIZE];
    fxp_t o_fp [HIDDEN_SIZE];
    fxp_t c_new [HIDDEN_SIZE];
    fxp_t c_new_reg [HIDDEN_SIZE]; // Registered c_new
    fxp_t t_fp [HIDDEN_SIZE];

    // Handshake signals for activation modules
    logic start_sigmoid [HIDDEN_SIZE];
    logic done_sigmoid_i [HIDDEN_SIZE];
    logic done_sigmoid_f [HIDDEN_SIZE];
    logic done_sigmoid_o [HIDDEN_SIZE];
    logic ready_sigmoid_i [HIDDEN_SIZE];
    logic ready_sigmoid_f [HIDDEN_SIZE];
    logic ready_sigmoid_o [HIDDEN_SIZE];
    logic start_tanh [HIDDEN_SIZE];
    logic done_tanh_g [HIDDEN_SIZE];
    logic done_tanh_ct [HIDDEN_SIZE];
    logic ready_tanh_g [HIDDEN_SIZE];
    logic ready_tanh_ct [HIDDEN_SIZE];

    // Memory for weights and biases
    logic signed [DATA_WIDTH-1:0] W_ih_flat [4*HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] W_hh_flat [4*HIDDEN_SIZE*HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b_ih_flat [4*HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b_hh_flat [4*HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b_flat [4*HIDDEN_SIZE];

    // Multidimensional arrays
    logic signed [DATA_WIDTH-1:0] W_ih [4][HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] W_hh [4][HIDDEN_SIZE][HIDDEN_SIZE];
    logic signed [DATA_WIDTH-1:0] b [4][HIDDEN_SIZE];

    // Initialize memory with placeholder values
    initial begin
        $readmemh("W_ih_enc.mem", W_ih_flat);
        $readmemh("W_hh_enc.mem", W_hh_flat);
        $readmemh("b_ih_enc.mem", b_ih_flat);
        $readmemh("b_hh_enc.mem", b_hh_flat);
    end

    // Map flat arrays to multidimensional arrays and combine biases
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                W_ih[i][j] = W_ih_flat[i*HIDDEN_SIZE + j];
                b[i][j] = b_ih_flat[i*HIDDEN_SIZE + j] + b_hh_flat[i*HIDDEN_SIZE + j];
                for (int k = 0; k < HIDDEN_SIZE; k++) begin
                    W_hh[i][j][k] = W_hh_flat[i*HIDDEN_SIZE*HIDDEN_SIZE + j*HIDDEN_SIZE + k];
                end
            end
        end
    end

    // Compute raw gates in parallel
    ConcatMultAdd #(DATA_WIDTH, FRACT_WIDTH, HIDDEN_SIZE) CM_i (
        .X(x_t), .h_in(h_prev), .W0(W_ih[0]), .W_h(W_hh[0]), .b(b[0]), .out(i_raw)
    );
    ConcatMultAdd #(DATA_WIDTH, FRACT_WIDTH, HIDDEN_SIZE) CM_f (
        .X(x_t), .h_in(h_prev), .W0(W_ih[1]), .W_h(W_hh[1]), .b(b[1]), .out(f_raw)
    );
    ConcatMultAdd #(DATA_WIDTH, FRACT_WIDTH, HIDDEN_SIZE) CM_g (
        .X(x_t), .h_in(h_prev), .W0(W_ih[2]), .W_h(W_hh[2]), .b(b[2]), .out(g_raw)
    );
    ConcatMultAdd #(DATA_WIDTH, FRACT_WIDTH, HIDDEN_SIZE) CM_o (
        .X(x_t), .h_in(h_prev), .W0(W_ih[3]), .W_h(W_hh[3]), .b(b[3]), .out(o_raw)
    );

    // Instantiate sigmoid and tanh modules
    generate
        for (genvar j = 0; j < HIDDEN_SIZE; j++) begin : activation_gen
            sigmoid SIG_i (
                .clk(clk), .rst(rst), .start(start_sigmoid[j]), .done(done_sigmoid_i[j]),
                .ready(ready_sigmoid_i[j]), .x(i_raw[j]), .y(i_fp[j])
            );
            sigmoid SIG_f (
                .clk(clk), .rst(rst), .start(start_sigmoid[j]), .done(done_sigmoid_f[j]),
                .ready(ready_sigmoid_f[j]), .x(f_raw[j]), .y(f_fp[j])
            );
            tanh TANH_g (
                .clk(clk), .rst(rst), .start(start_tanh[j]), .done(done_tanh_g[j]),
                .ready(ready_tanh_g[j]), .x(g_raw[j]), .y(g_fp[j])
            );
            sigmoid SIG_o (
                .clk(clk), .rst(rst), .start(start_sigmoid[j]), .done(done_sigmoid_o[j]),
                .ready(ready_sigmoid_o[j]), .x(o_raw[j]), .y(o_fp[j])
            );
            tanh TANH_ct (
                .clk(clk), .rst(rst), .start(start_tanh[j]), .done(done_tanh_ct[j]),
                .ready(ready_tanh_ct[j]), .x(c_new_reg[j]), .y(t_fp[j])
            );
        end
    endgenerate

    // Function to check if all done signals are high
    function automatic logic all_done(input logic arr [HIDDEN_SIZE]);
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            if (!arr[i]) return 0;
        end
        return 1;
    endfunction

    // Function to check if all ready signals are high
    function automatic logic all_ready(input logic arr [HIDDEN_SIZE]);
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            if (!arr[i]) return 0;
        end
        return 1;
    endfunction

    // Compute c_new combinationally
    always_comb begin
        if (state == CELL_UPDATE) begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                fxp_ext_t prod1, prod2, sum;
                prod1 = f_fp[j] * c_prev[j];
                prod2 = i_fp[j] * g_fp[j];
                sum = prod1 + prod2;
                c_new[j] = fxp_t'(sum >>> FRACT_WIDTH);
            end
        end else begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                c_new[j] = 0;
            end
        end
    end

    // State machine
    enum logic [3:0] {
        IDLE = 4'd0,
        GATES = 4'd1,
        ACTIVATE = 4'd2,
        CELL_UPDATE = 4'd3,
        CELL_UPDATE_HOLD = 4'd4,
        TANH_CT_COMPUTE = 4'd5,
        HIDDEN_UPDATE = 4'd6,
        HIDDEN_UPDATE_HOLD = 4'd7,
        DONE = 4'd8
    } state, next_state;

    // Timeout counter
    logic [15:0] timeout_cnt;
    logic timeout;
    logic done_next;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        timeout_cnt <= 0;
        timeout <= 0;
        done <= 0;
        for (int j = 0; j < HIDDEN_SIZE; j++) begin
            h_out[j] <= 0;
            c_out[j] <= 0;
            c_new_reg[j] <= 0;
        end
    end else begin
        state <= next_state;
        done <= done_next;

        if (state == CELL_UPDATE) begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                c_new_reg[j] <= c_new[j];
                c_out[j] <= c_new[j];
            end
        end

        if (state == HIDDEN_UPDATE) begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                fxp_ext_t prod;
                fxp_t h_tmp;
                prod = o_fp[j] * t_fp[j];
                h_tmp = fxp_t'(prod >>> FRACT_WIDTH);
                h_out[j] <= h_tmp;
            end
        end

        // Timeout counter update
        if (state == ACTIVATE || state == TANH_CT_COMPUTE || state == HIDDEN_UPDATE) begin
            if (timeout_cnt >= TIMEOUT_CYCLES) begin
                timeout <= 1;
                timeout_cnt <= 0;
            end else begin
                timeout_cnt <= timeout_cnt + 1;
            end
        end else begin
            timeout_cnt <= 0;
            timeout <= 0;
        end
    end
end

    // Next state and handshake logic
    always_comb begin
        next_state = state;
        done_next = 0;
        for (int j = 0; j < HIDDEN_SIZE; j++) begin
            start_sigmoid[j] = 0;
            start_tanh[j] = 0;
        end

        case (state)
            IDLE: begin
                if (start) begin
                    next_state = GATES;
                end
            end
            GATES: begin
                if (all_ready(ready_sigmoid_i) && all_ready(ready_sigmoid_f) && 
                    all_ready(ready_sigmoid_o) && all_ready(ready_tanh_g)) begin
                    for (int j = 0; j < HIDDEN_SIZE; j++) begin
                        start_sigmoid[j] = 1;
                        start_tanh[j] = 1; // For TANH_g only
                    end
                    next_state = ACTIVATE;
                end
            end
            ACTIVATE: begin
                if (timeout) begin
                    done_next = 1;
                    next_state = DONE;
                end else if (all_done(done_sigmoid_i) && all_done(done_sigmoid_f) && 
                             all_done(done_tanh_g) && all_done(done_sigmoid_o)) begin
                    next_state = CELL_UPDATE;
                end
            end
            CELL_UPDATE: begin
                next_state = CELL_UPDATE_HOLD; // Move to hold state
            end
            CELL_UPDATE_HOLD: begin
                if (all_ready(ready_tanh_ct)) begin
                    for (int j = 0; j < HIDDEN_SIZE; j++) begin
                        start_tanh[j] = 1; // For TANH_ct
                    end
                    next_state = TANH_CT_COMPUTE;
                end
            end
            TANH_CT_COMPUTE: begin
                if (timeout) begin
                    done_next = 1;
                    next_state = DONE;
                end else if (all_done(done_tanh_ct)) begin
                    next_state = HIDDEN_UPDATE;
                end
            end
            HIDDEN_UPDATE: begin
                if (timeout) begin
                    done_next = 1;
                    next_state = DONE;
                end else begin
                    next_state = HIDDEN_UPDATE_HOLD; // Move to hold state
                end
            end
            HIDDEN_UPDATE_HOLD: begin
                done_next = 1;
                next_state = DONE;
            end
            DONE: begin
                done_next = 1;
                next_state = IDLE;
            end
            default: begin
                done_next = 1;
                next_state = IDLE;
            end
        endcase
    end

endmodule

module sigmoid #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                clk,
    input  logic                rst,
    input  logic                start,
    output logic                done,
    output logic                ready,
    input  logic signed [DATA_WIDTH-1:0] x,
    output logic signed [DATA_WIDTH-1:0] y
);

    // Import C sigmoid function: int fxp_sigmoid_q8_24(int x);
    import "DPI-C" function int fxp_sigmoid_q8_24(input int x);

    typedef enum logic [1:0] {IDLE, CALC, DONE} state_t;
    state_t state;

    logic signed [DATA_WIDTH-1:0] x_reg;
    logic signed [DATA_WIDTH-1:0] y_result;
    logic compute;

    // Call DPI-C sigmoid (combinational logic)
    always_comb begin
        if (compute)
            y_result = fxp_sigmoid_q8_24(x_reg);
        else
            y_result = 0;
    end

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state  <= IDLE;
            done   <= 0;
            y      <= 0;
            x_reg  <= 0;
            compute <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg  <= x;
                        compute <= 1;
                        state <= CALC;
                    end
                end

                CALC: begin
                    compute <= 0;
                    y <= y_result;
                    state <= DONE;
                end

                DONE: begin
                    done <= 1;
                    if (!start)
                        state <= IDLE;
                end
            endcase
        end
    end

    assign ready = (state == IDLE);

endmodule

module tanh #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                clk,
    input  logic                rst,
    input  logic                start,
    output logic                done,
    output logic                ready,
    input  logic signed [DATA_WIDTH-1:0] x,
    output logic signed [DATA_WIDTH-1:0] y
);

    // Import C tanh function: int fxp_tanh_q8_24(int x);
    import "DPI-C" function int fxp_tanh_q8_24(input int x);

    typedef enum logic [1:0] {IDLE, CALC, DONE} state_t;
    state_t state;

    logic signed [DATA_WIDTH-1:0] x_reg;
    logic signed [DATA_WIDTH-1:0] y_result;
    logic compute;

    // Call DPI-C tanh (combinational logic)
    always_comb begin
        if (compute)
            y_result = fxp_tanh_q8_24(x_reg);
        else
            y_result = 0;
    end

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state  <= IDLE;
            done   <= 0;
            y      <= 0;
            x_reg  <= 0;
            compute <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg <= x;
                        compute <= 1;
                        state <= CALC;
                    end
                end

                CALC: begin
                    compute <= 0;
                    y <= y_result;
                    state <= DONE;
                end

                DONE: begin
                    done <= 1;
                    if (!start)
                        state <= IDLE;
                end
            endcase
        end
    end

    assign ready = (state == IDLE);

endmodule

module ConcatMultAdd #(
    parameter int DATA_WIDTH = 32,
    parameter int FRACT_WIDTH = 24,
    parameter int HIDDEN_SIZE = 10
)(
    input  logic signed [DATA_WIDTH-1:0] X,
    input  logic signed [DATA_WIDTH-1:0] h_in [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] W0 [HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] W_h [HIDDEN_SIZE][HIDDEN_SIZE],
    input  logic signed [DATA_WIDTH-1:0] b [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] out [HIDDEN_SIZE]
);

    typedef logic signed [DATA_WIDTH-1:0] fxp_t;
    typedef logic signed [(DATA_WIDTH*2)-1:0] fxp_ext_t;

    fxp_ext_t x_term [HIDDEN_SIZE];
    fxp_ext_t h_sum [HIDDEN_SIZE];

    always_comb begin
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            x_term[i] = (W0[i] * X) >>> FRACT_WIDTH;
        end
    end

    always_comb begin
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            h_sum[i] = '0;
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                h_sum[i] += (W_h[i][j] * h_in[j]) >>> FRACT_WIDTH;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            out[i] = fxp_t'(x_term[i] + h_sum[i] + b[i]);
        end
    end

endmodule