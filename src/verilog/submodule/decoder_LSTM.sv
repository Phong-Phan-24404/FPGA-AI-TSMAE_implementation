`timescale 1ns / 1ps
module decoder_LSTM #(
    parameter int DATA_WIDTH  = 32,
    parameter int FRACT_WIDTH = 24,
    parameter int HIDDEN_SIZE = 10,
    parameter int INPUT_SIZE  = 1,  // Output dimension for x_recon
    parameter int SEQ_LEN     = 10,
    parameter int TIMEOUT_CYCLES = 1000000,
    parameter logic signed [DATA_WIDTH-1:0] b_out = 32'hffefc4f9  // Scalar bias
)(
    input  logic                clk,
    input  logic                rst,
    input  logic                start,
    input  logic signed [DATA_WIDTH-1:0] z_hat_seq [SEQ_LEN][HIDDEN_SIZE], // Input sequence
    output logic signed [DATA_WIDTH-1:0] h_out [HIDDEN_SIZE],           // Final hidden state
    output logic signed [DATA_WIDTH-1:0] x_recon [SEQ_LEN][INPUT_SIZE], // Reconstructed output
    output logic                done
);

    // Typedefs for fixed-point
    typedef logic signed [DATA_WIDTH-1:0] fxp_t;

    // Internal signals
    fxp_t h_t [HIDDEN_SIZE];      // Current hidden state
    fxp_t c_t [HIDDEN_SIZE];      // Current cell state
    fxp_t h_next [HIDDEN_SIZE];   // Next hidden state from decoder_LSTM_cell
    fxp_t c_next [HIDDEN_SIZE];   // Next cell state from decoder_LSTM_cell
    fxp_t z_t [HIDDEN_SIZE];      // Current input at time t (from z_hat_seq)
    logic lstm_start;             // Start signal for decoder_LSTM_cell
    logic lstm_done;              // Done signal from decoder_LSTM_cell
    logic [31:0] time_step;       // Current time step (0 to SEQ_LEN-1)

    // Projection signals
    fxp_t W_out [INPUT_SIZE][HIDDEN_SIZE]; // Output weight matrix (1×HIDDEN_SIZE)
    fxp_t proj_acc;                // Accumulator for matrix-vector multiplication
    logic [31:0] proj_idx;         // Index for projection computation
    logic mul_start;               // Start signal for multiplier
    logic mul_done;                // Done signal from multiplier
    logic mul_busy;                // Busy signal from multiplier
    fxp_t mul_result;              // Result from multiplier

    // State machine
    enum logic [4:0] {
        IDLE = 5'd0,
        INIT = 5'd1,
        LOAD_WEIGHTS = 5'd2,
        PROCESS = 5'd3,
        WAIT_LSTM = 5'd4,
        PROJ_INIT = 5'd5,
        PROJ_MUL = 5'd6,
        WAIT_MUL = 5'd7,
        PROJ_ACC = 5'd8,
        PROJ_STORE = 5'd9,
        UPDATE = 5'd10,
        DONE = 5'd11,
        DONE_HOLD = 5'd12
    } state, next_state;

    // Instantiate decoder_LSTM_cell
    decoder_LSTM_cell #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACT_WIDTH),
        .INPUT_SIZE(HIDDEN_SIZE), // LSTM input is z_hat_seq[t] of size HIDDEN_SIZE
        .HIDDEN_SIZE(HIDDEN_SIZE)
    ) lstm_cell_inst (
        .clk(clk),
        .reset(rst),
        .x_t(z_t),
        .h_prev(h_t),
        .c_prev(c_t),
        .h_t(h_next),
        .c_t(c_next),
        .start(lstm_start),
        .done(lstm_done)
    );

    // Instantiate multiplier for projection
    multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACT_WIDTH)
    ) mul_inst (
        .clk(clk),
        .reset(rst),
        .start(mul_start),
        .a(W_out[0][proj_idx]), // Only one output dimension
        .b(h_t[proj_idx]),
        .result(mul_result),
        .done(mul_done),
        .busy(mul_busy)
    );

    // Timeout counter
    logic [31:0] timeout_cnt;
    logic timeout;

    // Load W_out from output_weights.mem
    initial begin
        $readmemh("output_weights.mem", W_out); // Expect 1×HIDDEN_SIZE values
    end

    // Sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            time_step <= 0;
            timeout_cnt <= 0;
            timeout <= 0;
            done <= 0;
            lstm_start <= 0;
            mul_start <= 0;
            proj_idx <= 0;
            proj_acc <= 0;
            for (int i = 0; i < HIDDEN_SIZE; i++) begin
                h_t[i] <= 0;
                c_t[i] <= 0;
                h_out[i] <= 0;
            end
            for (int t = 0; t < SEQ_LEN; t++) begin
                x_recon[t][0] <= 0; // INPUT_SIZE=1
            end
        end else begin
    state <= next_state;
    timeout_cnt <= (state == WAIT_LSTM || state == WAIT_MUL) && !timeout ? timeout_cnt + 1 : 0;
    timeout <= (timeout_cnt >= TIMEOUT_CYCLES) ? 1 : timeout;
    done <= (state == DONE_HOLD) ? 1 : 0;

    // Update time step and states
    if (state == UPDATE) begin
        time_step <= time_step + 1;
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            h_t[i] <= h_next[i];
            c_t[i] <= c_next[i];
        end

        // Display LSTM output
        $display("=== [LSTM DONE at t = %0d] ===", time_step);
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            $display("h_next[%0d] = %f, c_next[%0d] = %f", i, $itor(h_next[i]) / (1 << FRACT_WIDTH),
                                                           i, $itor(c_next[i]) / (1 << FRACT_WIDTH));
        end
    end else if (state == INIT) begin
        time_step <= 0;
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            h_t[i] <= 0;
            c_t[i] <= 0;
        end
    end

    // Update h_out in DONE state
    if (state == DONE) begin
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            h_out[i] <= h_t[i];
        end

        // Display final h_out
        $display("=== [FINAL h_out after t = %0d] ===", time_step);
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            $display("h_out[%0d] = %f", i, $itor(h_t[i]) / (1 << FRACT_WIDTH));
        end
    end

    // Control lstm_start
    lstm_start <= (state == PROCESS) ? 1 : 0;

    // Control projection
    if (state == PROJ_INIT) begin
        proj_idx <= 0;
        proj_acc <= 0;

        // Display h_t before projection
        $display("=== [Projection INPUT at t = %0d] ===", time_step);
        for (int i = 0; i < HIDDEN_SIZE; i++) begin
            $display("h_t[%0d] = %f", i, $itor(h_t[i]) / (1 << FRACT_WIDTH));
        end
    end else if (state == PROJ_ACC) begin
        proj_idx <= proj_idx + 1;
        proj_acc <= proj_acc + mul_result;
    end else if (state == PROJ_STORE) begin
        x_recon[time_step][0] <= proj_acc + b_out;

        // Display projection result
        $display("=== [Projection OUTPUT at t = %0d] ===", time_step);
        $display("x_hat[%0d] = %f = proj_acc + b_out", time_step,
                 $itor(proj_acc + b_out) / (1 << FRACT_WIDTH));
    end

    // Control mul_start
    mul_start <= (state == PROJ_MUL) ? 1 : 0;
end

    end

    // Combinational logic
    always_comb begin
        next_state = state;
        z_t = z_hat_seq[time_step]; // Select current input

        case (state)
            IDLE: begin
                if (start) begin
                    next_state = INIT;
                end
            end
            INIT: begin
                next_state = LOAD_WEIGHTS;
            end
            LOAD_WEIGHTS: begin
                next_state = PROCESS;
            end
            PROCESS: begin
                next_state = WAIT_LSTM;
            end
            WAIT_LSTM: begin
                if (timeout) begin
                    next_state = DONE;
                end else if (lstm_done) begin
                    next_state = PROJ_INIT;
                end
            end
            PROJ_INIT: begin
                next_state = PROJ_MUL;
            end
            PROJ_MUL: begin
                next_state = WAIT_MUL;
            end
            WAIT_MUL: begin
                if (timeout) begin
                    next_state = DONE;
                end else if (mul_done) begin
                    next_state = PROJ_ACC;
                end
            end
            PROJ_ACC: begin
                if (proj_idx + 1 == HIDDEN_SIZE) begin
                    next_state = PROJ_STORE;
                end else begin
                    next_state = PROJ_MUL;
                end
            end
            PROJ_STORE: begin
                next_state = UPDATE;
            end
            UPDATE: begin
                if (time_step + 1 == SEQ_LEN) begin
                    next_state = DONE;
                end else begin
                    next_state = PROCESS;
                end
            end
            DONE: begin
                next_state = DONE_HOLD;
            end
            DONE_HOLD: begin
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule