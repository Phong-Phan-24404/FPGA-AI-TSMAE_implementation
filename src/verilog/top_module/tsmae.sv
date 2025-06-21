`timescale 1ns / 1ps
module TSMAE #(
    parameter int DATA_WIDTH      = 32,
    parameter int FRACT_WIDTH     = 24,
    parameter int HIDDEN_SIZE     = 10,
    parameter int INPUT_SIZE      = 1,  // Input and output dimension
    parameter int SEQ_LEN         = 10,
    parameter int MEMORY_SIZE     = 10,
    parameter int TIMEOUT_CYCLES  = 1000000
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic signed [DATA_WIDTH-1:0] x [SEQ_LEN][INPUT_SIZE],
    output logic signed [DATA_WIDTH-1:0] x_recon [SEQ_LEN][INPUT_SIZE],
    output logic signed [DATA_WIDTH-1:0] q [MEMORY_SIZE],
    output logic signed [DATA_WIDTH-1:0] z [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] z_hat [HIDDEN_SIZE],
    output logic done
);
    // Local parameters
    localparam int DECODER_INPUT_SIZE  = HIDDEN_SIZE;  // 10
    localparam int DECODER_OUTPUT_SIZE = INPUT_SIZE;   // 1 (not used in decoder_LSTM)
    // Type definition
    typedef logic signed [DATA_WIDTH-1:0] fxp_t;

    // Internal signals
    fxp_t z_int [HIDDEN_SIZE];
    fxp_t z_hat_int [HIDDEN_SIZE];
    fxp_t z_hat_seq [SEQ_LEN][DECODER_INPUT_SIZE];
    fxp_t q_int [MEMORY_SIZE];
    fxp_t decoder_h_out [HIDDEN_SIZE];
    logic enc_start, enc_done;
    logic mem_start, mem_done;
    logic dec_start, dec_done;
    logic [31:0] timeout_cnt;
    logic timeout;
    logic enc_done_lat, mem_done_lat, dec_done_lat;

    // FSM states
    enum logic [3:0] {
        IDLE        = 4'd0,
        ENC_START   = 4'd1,
        ENC_WAIT    = 4'd2,
        MEM_START   = 4'd3,
        MEM_WAIT    = 4'd4,
        REPEAT_Z_HAT= 4'd5,
        DEC_START   = 4'd6,
        DEC_WAIT    = 4'd7,
        DONE        = 4'd8,
        DONE_HOLD   = 4'd9
    } state, next_state;

    // Submodule instantiations
    encoder_LSTM #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACT_WIDTH(FRACT_WIDTH),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .SEQ_LEN(SEQ_LEN),
        .NUM_FEATURES(INPUT_SIZE),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) encoder_inst (
        .clk(clk),
        .rst(rst),
        .start(enc_start),
        .x(x),
        .h_out(z_int),
        .done(enc_done)
    );

    memory_module #(
        .MEMORY_SIZE(MEMORY_SIZE),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTION_BITS(FRACT_WIDTH)
    ) memory_inst (
        .clk(clk),
        .reset(rst),
        .start(mem_start),
        .z(z_int),
        .z_hat(z_hat_int),
        .q(q_int),
        .done(mem_done)
    );

// Decoder instantiation (corrected)
    decoder_LSTM #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACT_WIDTH(FRACT_WIDTH),
        .HIDDEN_SIZE(HIDDEN_SIZE),     // Input dimension per time step = 10
        .INPUT_SIZE(INPUT_SIZE),       // Output dimension = 1
        .SEQ_LEN(SEQ_LEN),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) decoder_inst (
        .clk(clk),
        .rst(rst),
        .start(dec_start),
        .z_hat_seq(z_hat_seq),         // Corrected port name
        .h_out(decoder_h_out),
        .x_recon(x_recon),
        .done(dec_done)
    );
real z_val;

    // Sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            timeout_cnt <= 0;
            timeout <= 0;
            done <= 0;
            enc_start <= 0;
            mem_start <= 0;
            dec_start <= 0;
            enc_done_lat <= 0;
            mem_done_lat <= 0;
            dec_done_lat <= 0;
            for (int i = 0; i < HIDDEN_SIZE; i++) begin
                z[i] <= 0;
                z_hat[i] <= 0;
            end
            for (int i = 0; i < MEMORY_SIZE; i++) begin
                q[i] <= 0;
            end
            for (int t = 0; t < SEQ_LEN; t++) begin
                for (int i = 0; i < DECODER_INPUT_SIZE; i++) begin
                    z_hat_seq[t][i] <= 0;
                end
            end
        end else begin
            state <= next_state;

            // Timeout counter
            if (state == ENC_WAIT || state == MEM_WAIT || state == DEC_WAIT) begin
                timeout_cnt <= timeout_cnt + 1;
                if (timeout_cnt >= TIMEOUT_CYCLES - 1) timeout <= 1;
            end else begin
                timeout_cnt <= 0;
                timeout <= 0;
            end

            // Latch done signals
            if (enc_done) enc_done_lat <= 1;
            if (mem_done) mem_done_lat <= 1;
            if (dec_done) dec_done_lat <= 1;

            // Reset latches when leaving wait states
            if (state == ENC_WAIT  && next_state != ENC_WAIT)  enc_done_lat <= 0;
            if (state == MEM_WAIT  && next_state != MEM_WAIT)  mem_done_lat <= 0;
            if (state == DEC_WAIT  && next_state != DEC_WAIT)  dec_done_lat <= 0;

            // Data latching
            if (state == ENC_WAIT && enc_done) begin
                for (int i = 0; i < HIDDEN_SIZE; i++) begin
                    z[i] <= z_int[i];
                end
                
                    // DEBUG: display encoder output
    $display("\n%0s", "="*60);
    $display("Encoder Output z:");
    for (int i = 0; i < HIDDEN_SIZE; i++) begin
        z_val = $itor(z_int[i]) / (1 << FRACT_WIDTH);
        $display("z[%0d] = %0.10f", i, z_val);
    end
                
            end
            if (state == MEM_WAIT && mem_done) begin
                for (int i = 0; i < HIDDEN_SIZE; i++) begin
                    z_hat[i] <= z_hat_int[i];
                end
                for (int i = 0; i < MEMORY_SIZE; i++) begin
                    q[i] <= q_int[i];
                end
            end
            if (state == REPEAT_Z_HAT) begin
                for (int t = 0; t < SEQ_LEN; t++) begin
                    for (int i = 0; i < DECODER_INPUT_SIZE; i++) begin
                        z_hat_seq[t][i] <= z_hat_int[i];
                    end
                end
            end

            // Control signals
            enc_start <= (state == ENC_START);
            mem_start <= (state == MEM_START);
            dec_start <= (state == DEC_START);
            done <= (state == DONE_HOLD);
        end
    end

    // State machine
    always_comb begin
        next_state = state;
        case (state)
            IDLE:        if (start) next_state = ENC_START;
            ENC_START:   next_state = ENC_WAIT;
            ENC_WAIT:    if (timeout) next_state = DONE;
                        else if (enc_done_lat) next_state = MEM_START;
            MEM_START:   next_state = MEM_WAIT;
            MEM_WAIT:    if (timeout) next_state = DONE;
                        else if (mem_done_lat) next_state = REPEAT_Z_HAT;
            REPEAT_Z_HAT:next_state = DEC_START;
            DEC_START:   next_state = DEC_WAIT;
            DEC_WAIT:    if (timeout || dec_done_lat) next_state = DONE;
            DONE:        next_state = DONE_HOLD;
            DONE_HOLD:   next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

endmodule