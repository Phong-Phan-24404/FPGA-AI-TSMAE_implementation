`timescale 1ns / 1ps
module encoder_LSTM #(
    parameter int DATA_WIDTH  = 32,
    parameter int FRACT_WIDTH = 24,
    parameter int HIDDEN_SIZE = 10,
    parameter int SEQ_LEN     = 10,
    parameter int NUM_FEATURES = 1,
    parameter int TIMEOUT_CYCLES = 1000000
)(
    input  logic                clk,
    input  logic                rst,
    input  logic                start,
    input  logic signed [DATA_WIDTH-1:0] x [SEQ_LEN][NUM_FEATURES],
    output logic signed [DATA_WIDTH-1:0] h_out [HIDDEN_SIZE],
    output logic                done
);

    // Typedefs for fixed-point
    typedef logic signed [DATA_WIDTH-1:0] fxp_t;

    // Internal signals
    fxp_t h_t [HIDDEN_SIZE];      // Current hidden state
    fxp_t c_t [HIDDEN_SIZE];      // Current cell state
    fxp_t h_next [HIDDEN_SIZE];   // Next hidden state from LSTM_cell
    fxp_t c_next [HIDDEN_SIZE];   // Next cell state from LSTM_cell
    fxp_t x_t [NUM_FEATURES];     // Current input at time t
    logic lstm_start;             // Start signal for LSTM_cell
    logic lstm_done;              // Done signal from LSTM_cell
    logic [31:0] time_step;       // Current time step (0 to SEQ_LEN-1)

    // State machine
    enum logic [2:0] {
        IDLE = 3'd0,
        INIT = 3'd1,
        PROCESS = 3'd2,
        WAIT_LSTM = 3'd3,
        UPDATE = 3'd4,
        DONE = 3'd5
    } state;

    // Timeout counter
    logic [31:0] timeout_cnt;
    logic timeout;

    // Instantiate LSTM_cell
    LSTM_cell #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACT_WIDTH(FRACT_WIDTH),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) lstm_cell_inst (
        .clk(clk),
        .rst(rst),
        .x_t(x_t[0]), // Assuming NUM_FEATURES=1 for scalar input
        .h_prev(h_t),
        .c_prev(c_t),
        .h_out(h_next),
        .c_out(c_next),
        .start(lstm_start),
        .done(lstm_done)
    );

    // Next state and control signals
    logic [2:0] next_state;
    logic update_time_step;
    logic clear_time_step;
    logic update_states;
    logic clear_states;
    logic update_h_out;
    logic set_lstm_start;
    logic clear_timeout_cnt;
    logic set_timeout;
    logic set_done;

    // Sequential logic (minimal)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            time_step <= 0;
            timeout_cnt <= 0;
            timeout <= 0;
            done <= 0;
            lstm_start <= 0;
            for (int i = 0; i < HIDDEN_SIZE; i++) begin
                h_t[i] <= 0;
                c_t[i] <= 0;
                h_out[i] <= 0;
            end
        end else begin
            state <= next_state;

            // Update time step
            if (clear_time_step)
                time_step <= 0;
            else if (update_time_step)
                time_step <= time_step + 1;

            // Update states
            if (clear_states) begin
                for (int i = 0; i < HIDDEN_SIZE; i++) begin
                    h_t[i] <= 0;
                    c_t[i] <= 0;
                end
            end else if (update_states) begin
                for (int i = 0; i < HIDDEN_SIZE; i++) begin
                    h_t[i] <= h_next[i];
                    c_t[i] <= c_next[i];
                end
            end

            // Update h_out
            if (update_h_out) begin
                for (int i = 0; i < HIDDEN_SIZE; i++) begin
                    h_out[i] <= h_t[i];
                end
            end

            // Update timeout counter
            if (clear_timeout_cnt)
                timeout_cnt <= 0;
            else if (state == WAIT_LSTM && !timeout)
                timeout_cnt <= timeout_cnt + 1;

            // Update timeout flag
            if (set_timeout)
                timeout <= 1;
            else
                timeout <= 0;

            // Update lstm_start
            lstm_start <= set_lstm_start ? 1 : 0;

            // Update done
            done <= set_done ? 1 : 0;
        end
    end

    // Combinational logic (expanded)
    always_comb begin
        // Default values
        next_state = state;
        update_time_step = 0;
        clear_time_step = 0;
        update_states = 0;
        clear_states = 0;
        update_h_out = 0;
        set_lstm_start = 0;
        clear_timeout_cnt = 0;
        set_timeout = 0;
        set_done = 0;
        x_t = x[time_step]; // Select current input

        case (state)
            IDLE: begin
                if (start)
                    next_state = INIT;
            end
            INIT: begin
                clear_time_step = 1;
                clear_states = 1;
                clear_timeout_cnt = 1;
                next_state = PROCESS;
            end
            PROCESS: begin
                set_lstm_start = 1;
                next_state = WAIT_LSTM;
            end
            WAIT_LSTM: begin
                clear_timeout_cnt = 0; // Keep counting
                set_timeout = (timeout_cnt >= TIMEOUT_CYCLES);
                if (timeout)
                    next_state = DONE;
                else if (lstm_done) begin
                    next_state = UPDATE;
                    clear_timeout_cnt = 1;
                end
            end
            UPDATE: begin
                update_time_step = 1;
                update_states = 1;
                if (time_step + 1 == SEQ_LEN)
                    next_state = DONE;
                else
                    next_state = PROCESS;
            end
            DONE: begin
                update_h_out = 1;
                set_done = 1;
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule