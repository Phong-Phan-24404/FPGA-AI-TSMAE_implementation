module memory_module #(
    parameter MEMORY_SIZE = 10,
    parameter HIDDEN_SIZE = 10,
    parameter DATA_WIDTH = 32,    // Q8.24 fixed-point
    parameter FRACTION_BITS = 24
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic signed [DATA_WIDTH-1:0] z [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] z_hat [HIDDEN_SIZE],
    output logic signed [DATA_WIDTH-1:0] q [MEMORY_SIZE],
    output logic done
);

    // Memory declaration (unchanged)
    logic signed [DATA_WIDTH-1:0] memory [0:MEMORY_SIZE-1][0:HIDDEN_SIZE-1];
    initial begin
        logic signed [DATA_WIDTH-1:0] flat_memory [0:MEMORY_SIZE*HIDDEN_SIZE-1];
        $readmemh("memory.mem", flat_memory);
        for (int i = 0; i < MEMORY_SIZE; i++) begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                memory[i][j] = flat_memory[i * HIDDEN_SIZE + j];
            end
        end
        $display("=== Memory Loaded ===");
        for (int i = 0; i < MEMORY_SIZE; i++) begin
            for (int j = 0; j < HIDDEN_SIZE; j++) begin
                 $display("memory[%0d][%0d] = %08h", i, j, memory[i][j]);
            end
        end
    end

    // Internal signals
    logic signed [DATA_WIDTH-1:0] sim [0:MEMORY_SIZE-1];
    logic signed [DATA_WIDTH-1:0] exp_sim [0:MEMORY_SIZE-1];
    logic signed [DATA_WIDTH-1:0] sum_exp_sim;
    logic signed [DATA_WIDTH-1:0] q_softmax [0:MEMORY_SIZE-1];
    logic signed [DATA_WIDTH-1:0] q_rectified [0:MEMORY_SIZE-1];
    logic signed [DATA_WIDTH-1:0] sum_q_rectified;
    logic signed [DATA_WIDTH-1:0] z_hat_internal [0:HIDDEN_SIZE-1];
    logic signed [DATA_WIDTH-1:0] q_internal [0:MEMORY_SIZE-1];
    logic collecting_sum;
    logic signed [DATA_WIDTH-1:0] max_sim;
    logic [3:0] i_exp; // Tracks index for exp_result
    logic exp_start;   // New signal to trigger exp module
    logic signed [DATA_WIDTH-1:0] next_sum;
    // Declare thêm trên đầu module
logic signed [DATA_WIDTH-1:0] num_reg, den_reg;
logic [3:0] i_reg;
// ở phần declaration signals, thêm:
logic [3:0] i_norm_reg;
logic signed [DATA_WIDTH-1:0] num_norm_reg, den_norm_reg;



    // State machine states
    typedef enum logic [3:0] {
        IDLE            = 4'd0,
        COMPUTE_SIM     = 4'd1,
        FIND_MAX_SIM    = 4'd2,
        COMPUTE_SOFTMAX = 4'd3,
        RECTIFY         = 4'd4,
        NORMALIZE       = 4'd5,
        COMPUTE_Z_HAT   = 4'd6,
        DONE            = 4'd7
    } state_t;
    state_t state, next_state;

    // Sparsity threshold in Q8.24 (0.05 = 0x00_0C_CC_C0)
    localparam logic signed [DATA_WIDTH-1:0] SPARSITY_THRESHOLD = 32'h000CCCC0;

    // Counters and control signals
    logic [3:0] i, j;
    logic signed [DATA_WIDTH-1:0] accum;
    logic signed [DATA_WIDTH-1:0] exp_result;
    logic signed [DATA_WIDTH-1:0] div_result;
    // thêm khai báo tạm
logic signed [DATA_WIDTH-1:0] old_sum, new_sum;
    logic compute_done;

    // Submodule signals
    logic signed [DATA_WIDTH-1:0] mult_a, mult_b;
    logic signed [DATA_WIDTH-1:0] mult_result;
    logic mult_done;
    logic mult_start;
    logic mult_busy;

    logic signed [DATA_WIDTH-1:0] div_numerator, div_denominator;
    logic div_done;
    logic div_start;

    logic signed [DATA_WIDTH-1:0] exp_input;
    logic exp_done;

    // Control flags
    logic compute_done_flag;
    logic compute_done_pulse;
    assign compute_done_pulse = compute_done;

    logic op_issued;

    // Instantiate submodules (unchanged)
    multiplier #(
        .DATA_WIDTH(DATA_WIDTH), 
        .FRACTION_BITS(FRACTION_BITS)
    ) mult (
        .clk(clk), 
        .reset(reset), 
        .start(mult_start),
        .a(mult_a), 
        .b(mult_b), 
        .result(mult_result), 
        .done(mult_done),
        .busy(mult_busy)
    );

    divider #(
        .DATA_WIDTH(DATA_WIDTH), 
        .FRACTION_BITS(FRACTION_BITS)
    ) div (
        .clk(clk), 
        .reset(reset), 
        .start(div_start),
        .numerator(div_numerator), 
        .denominator(div_denominator),
        .result(div_result), 
        .done(div_done)
    );

    // Modified exp module instantiation with start signal
    exp #(
        .DATA_WIDTH(DATA_WIDTH), 
        .FRACTION_BITS(FRACTION_BITS)
    ) exp_unit (
        .clk(clk), 
        .reset(reset), 
        .start(exp_start), // Add start signal
        .x(exp_input), 
        .result(exp_result), 
        .done(exp_done)
    );

    // FSM next-state logic (unchanged)
    always_comb begin
        next_state = state;
        case (state)
            IDLE:
                if (start)
                    next_state = COMPUTE_SIM;
            COMPUTE_SIM:
                if (compute_done_pulse)
                    next_state = FIND_MAX_SIM;
            FIND_MAX_SIM:
                if (compute_done_pulse)
                    next_state = COMPUTE_SOFTMAX;
            COMPUTE_SOFTMAX:
                if (compute_done_pulse)
                    next_state = RECTIFY;
            RECTIFY:
                if (compute_done_pulse)
                    next_state = NORMALIZE;
            NORMALIZE:
                if (compute_done_pulse)
                    next_state = COMPUTE_Z_HAT;
            COMPUTE_Z_HAT:
                if (compute_done_pulse)
                    next_state = DONE;
            DONE:
                next_state = IDLE;
            default:
                next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state              <= IDLE;
            i                  <= 0;
            j                  <= 0;
            i_exp              <= 0;
            accum              <= 0;
            done               <= 0;
            compute_done_flag  <= 0;
            compute_done       <= 0;
            sum_exp_sim        <= 0;
            sum_q_rectified    <= 0;
            z_hat_internal     <= '{default:0};
            exp_sim            <= '{default:0};
            sim                <= '{default:0};
            q_softmax          <= '{default:0};
            q_rectified        <= '{default:0};
            q_internal         <= '{default:0};
            exp_input          <= 0;
            exp_start          <= 0;
            div_start          <= 0;
            mult_start         <= 0;
            op_issued          <= 0;
            collecting_sum     <= 1;
            max_sim            <= 0;
                i_reg            <= 0;
    num_reg          <= 0;
    den_reg          <= 0;
            i_norm_reg       <= 0;
        num_norm_reg     <= 0;
        den_norm_reg     <= 0;
        end else begin
            compute_done       <= compute_done_flag;
            compute_done_flag  <= 0;
            state              <= next_state;

            case (state)
                IDLE: begin
                    done               <= 0;
                    i                  <= 0;
                    j                  <= 0;
                    i_exp              <= 0;
                    accum              <= 0;
                    sum_exp_sim        <= 0;
                    sum_q_rectified    <= 0;
                    op_issued          <= 0;
                    max_sim            <= 0;
                    exp_start          <= 0;
                        i_reg            <= 0;
    num_reg          <= 0;
    den_reg          <= 0;
            i_norm_reg       <= 0;
        num_norm_reg     <= 0;
        den_norm_reg     <= 0;
                end

                COMPUTE_SIM: begin
                    if (!compute_done_flag && next_state == COMPUTE_SIM) begin
                        if (j < HIDDEN_SIZE && !op_issued) begin
                            mult_a     <= z[j];
                            mult_b     <= memory[i][j];
                            mult_start <= 1;
                            op_issued  <= 1;
                        end else begin
                            mult_start <= 0;
                        end

                        if (mult_done) begin
                            accum <= accum + mult_result;
                            j     <= j + 1;
                            op_issued <= 0;
                        end

                        if (j == HIDDEN_SIZE && !op_issued && !mult_busy) begin
                            sim[i] <= accum;
                     //       $display("[SIM] sim[%0d] = %08h", i, accum);
                            accum <= 0;
                            j <= 0;
                            i <= i + 1;

                            if (i == MEMORY_SIZE - 1) begin
                                compute_done_flag <= 1;
                                i <= 0;
                            end
                        end
                    end else begin
                        mult_start <= 0;
                        op_issued  <= 0;
                    end
                end

                FIND_MAX_SIM: begin
                    if (!compute_done_flag && next_state == FIND_MAX_SIM) begin
                        if (i == 0 && !op_issued) begin
                            max_sim <= sim[0];
                            i <= i + 1;
                        end else if (i < MEMORY_SIZE) begin
                            if ($signed(sim[i]) > $signed(max_sim)) begin
                                max_sim <= sim[i];
                            end
                            i <= i + 1;
                        end
                        if (i == MEMORY_SIZE) begin
                            compute_done_flag <= 1;
                            i <= 0;
                      //      $display("[FIND_MAX_SIM] max_sim = %08h", max_sim);
                        end
                    end
                end

                COMPUTE_SOFTMAX: begin
                    if (!compute_done_flag && next_state == COMPUTE_SOFTMAX) begin
                        if (i == 0 && !op_issued) begin
                            sum_exp_sim <= 0;
                            exp_sim     <= '{default:0};
                        end

                        if (!op_issued && i < MEMORY_SIZE) begin
                            exp_input <= sim[i] - max_sim;
                            exp_start <= 1;
                            i_exp     <= i;
                            op_issued <= 1;
                      //      $display("[SOFTMAX] sim[%0d] - max_sim = %08h - %08h = %08h", i, sim[i], max_sim, sim[i] - max_sim);
                        end else begin
                            exp_start <= 0;
                        end

                        if (exp_done) begin
                            exp_sim[i_exp] <= exp_result;
                            sum_exp_sim <= sum_exp_sim + exp_result;
                     //       $display("[SOFTMAX] exp_sim[%0d] = %08h", i_exp, exp_result);
                            exp_start <= 0;
                            op_issued <= 0;

                            if (i < MEMORY_SIZE - 1) begin
                                i <= i + 1;
                            end else begin
                                compute_done_flag <= 1;
                                i <= 0;
                        //        $display("[SOFTMAX] sum_exp_sim = %08h", sum_exp_sim + exp_result);
                            end
                        end
                    end else begin
                        op_issued <= 0;
                        exp_start <= 0;
                    end
                end

                RECTIFY: begin
                    if (!compute_done_flag && next_state == RECTIFY) begin
                        if (i == 0 && !op_issued) begin
                            sum_q_rectified <= 0;
                        end

                    // Trong state RECTIFY:
                    if (!op_issued) begin
                        // Gán vào register tạm
                        num_reg      <= exp_sim[i];
                        den_reg      <= sum_exp_sim;
                        i_reg        <= i;
                        div_numerator   <= exp_sim[i];
                        div_denominator <= sum_exp_sim;
                        div_start       <= 1;
                        op_issued       <= 1;
                      //  $display("[RECTIFY] start[%0d]: num=%08h den=%08h", i, exp_sim[i], sum_exp_sim);
                    end else begin
                        div_start <= 0;
                    end
                    
 // Khi divider trả về:
if (div_done) begin
    op_issued <= 0;

    // Dùng luôn num_reg/den_reg và i_reg để đảm bảo không bị lệch chỉ số
    if (den_reg != 0) begin
        q_softmax[i_reg] <= div_result;

        if (div_result > SPARSITY_THRESHOLD)
            q_rectified[i_reg] <= div_result - SPARSITY_THRESHOLD;
        else
            q_rectified[i_reg] <= 0;

    end else begin
        q_softmax[i_reg]   <= 0;
        q_rectified[i_reg] <= 0;
    end

    // Tiếp tục tăng i (con trỏ) như trước
    if (i < MEMORY_SIZE - 1) begin
        i <= i + 1;
    end else begin
        compute_done_flag <= 1;
        i <= 0;
       
    end
end
                    end else begin
                        div_start  <= 0;
                        op_issued  <= 0;
                    end
                end

                NORMALIZE: begin
    if (!compute_done_flag && next_state == NORMALIZE) begin
        if (collecting_sum) begin
            // reset đầu dãy
            if (i == 0 && !op_issued) begin
                sum_q_rectified <= 0;
            end

            // -------- tính và in bằng biến tạm --------
            old_sum = sum_q_rectified;
            new_sum = old_sum + (q_rectified[i][DATA_WIDTH-1] ? 0 : q_rectified[i]);
            sum_q_rectified <= new_sum;  // non-blocking

            // tăng chỉ số hoặc chuyển phase
            if (i < MEMORY_SIZE - 1) begin
                i <= i + 1;
            end else begin
                i <= 0;
                collecting_sum <= 0;
                op_issued <= 0;
                
            end
        end
                        
                        else begin

    if (!op_issued) begin
        // Latch trước vào regs tạm
        num_norm_reg        <= (q_rectified[i][DATA_WIDTH-1] ? 0 : q_rectified[i]);
        den_norm_reg        <= sum_q_rectified;
        i_norm_reg          <= i;

        // Thực sự issue divider
        div_numerator       <= (q_rectified[i][DATA_WIDTH-1] ? 0 : q_rectified[i]);
        div_denominator     <= sum_q_rectified;
        div_start           <= 1;
        op_issued           <= 1;

    end else begin
        div_start <= 0;
    end

    if (div_done) begin
        op_issued <= 0;

        // Dùng i_norm_reg, num_norm_reg, den_norm_reg để cập nhật và in
        q_internal[i_norm_reg] <= div_result;
    

        if (i < MEMORY_SIZE - 1)
            i <= i + 1;
        else begin
            compute_done_flag <= 1;
            i <= 0;
            collecting_sum <= 1;
        end
    end
end


                    end else begin
                        div_start <= 0;
                        op_issued <= 0;
                    end
                end

                COMPUTE_Z_HAT: begin
                    if (!compute_done_flag && next_state == COMPUTE_Z_HAT) begin
                        if (j == 0 && i == 0 && !op_issued && !mult_start) begin
                            z_hat_internal <= '{default:0};
                        end

                        if (!op_issued && j < HIDDEN_SIZE) begin
                            mult_a     <= q_internal[i];
                            mult_b     <= memory[i][j];
                            mult_start <= 1;
                            op_issued  <= 1;
                        end else begin
                            mult_start <= 0;
                        end

                        if (mult_done) begin
                            z_hat_internal[j] <= z_hat_internal[j] + mult_result;
                            op_issued <= 0;

                            if (i < MEMORY_SIZE - 1) begin
                                i <= i + 1;
                            end else begin
                                i <= 0;
                         
                                j <= j + 1;
                            end
                        end

                        if (j == HIDDEN_SIZE - 1 && i == MEMORY_SIZE - 1 && mult_done) begin
                            compute_done_flag <= 1;
                            j <= 0;
                        end
                    end else begin
                        mult_start <= 0;
                        op_issued <= 0;
                    end
                end

                DONE: begin
                    z_hat <= z_hat_internal;
                    q     <= q_internal;
                    done  <= 1;
                    for (int k = 0; k < HIDDEN_SIZE; k++) begin
                        // $display("[DONE] z_hat[%0d] = %08h", k, z_hat_internal[k]);
                    end
                end
            endcase
        end
    end
endmodule

module exp #(
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24
)(
    input  logic                    clk,
    input  logic                    reset,
    input  logic                    start,
    input  logic signed [DATA_WIDTH-1:0] x,
    output logic signed [DATA_WIDTH-1:0] result,
    output logic                    done
);

    // FSM
    typedef enum logic [1:0] {IDLE, CALC, DONE} state_t;
    state_t state, next_state;

    // Internal Registers
    logic signed [DATA_WIDTH-1:0] x_reg;
    logic signed [DATA_WIDTH-1:0] x1, x2, x3, x4, x5, x6, x7;
    logic signed [DATA_WIDTH-1:0] term2, term3, term4, term5, term6, term7;
    logic signed [DATA_WIDTH-1:0] result_comb;

    // Precomputed Constants (Q8.24)
    localparam logic [DATA_WIDTH-1:0] ONE       = 32'h01000000; // 1.0
    localparam logic [DATA_WIDTH-1:0] INV_2     = 32'h00800000; // 1/2
    localparam logic [DATA_WIDTH-1:0] INV_6     = 32'h02AAAAAB; // 1/6
    localparam logic [DATA_WIDTH-1:0] INV_24    = 32'h00AAAAAB; // 1/24
    localparam logic [DATA_WIDTH-1:0] INV_120   = 32'h002AAAAA; // 1/120
    localparam logic [DATA_WIDTH-1:0] INV_720   = 32'h0002E8BA; // 1/720
    localparam logic [DATA_WIDTH-1:0] INV_5040  = 32'h000085D1; // 1/5040

    // FSM transition
    always_comb begin
        case (state)
            IDLE:  next_state = start ? CALC : IDLE;
            CALC:  next_state = DONE;
            DONE:  next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done  <= 0;
            result <= 0;
            x_reg  <= 0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    done  <= 0;
                    if (start) begin
                        x_reg <= x;
                    end
                end

                CALC: begin
                    x1 = x_reg;
                    x2 = (x1 * x1) >>> FRACTION_BITS;
                    x3 = (x2 * x1) >>> FRACTION_BITS;
                    x4 = (x3 * x1) >>> FRACTION_BITS;
                    x5 = (x4 * x1) >>> FRACTION_BITS;
                    x6 = (x5 * x1) >>> FRACTION_BITS;
                    x7 = (x6 * x1) >>> FRACTION_BITS;

                    term2 = (x2 * INV_2)    >>> FRACTION_BITS;
                    term3 = (x3 * INV_6)    >>> FRACTION_BITS;
                    term4 = (x4 * INV_24)   >>> FRACTION_BITS;
                    term5 = (x5 * INV_120)  >>> FRACTION_BITS;
                    term6 = (x6 * INV_720)  >>> FRACTION_BITS;
                    term7 = (x7 * INV_5040) >>> FRACTION_BITS;

                    result_comb = ONE + x1 + term2 + term3 + term4 + term5 + term6 + term7;
                    result <= result_comb;
                end

                DONE: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule


// Multiplier module
module multiplier #(
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24
)(
    input  logic clk,
    input  logic reset,
    input  logic start,   // start trigger
    input  logic signed [DATA_WIDTH-1:0] a,
    input  logic signed [DATA_WIDTH-1:0] b,
    output logic signed [DATA_WIDTH-1:0] result,
    output logic done,
    output logic busy     // optional
);
    logic signed [2*DATA_WIDTH-1:0] product;
    logic [1:0] state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state  <= 0;
            result <= 0;
            done   <= 0;
            busy   <= 0;
        end else begin
            case (state)
                0: begin
                    if (start) begin
                        product <= $signed(a) * $signed(b);
                        busy    <= 1;
                        done    <= 0;
                        // $display("[MUL] @%0t - START: a = %08h, b = %08h", $time, a, b);
                        state <= 1;
                    end
                end
                1: begin
                    result <= product[DATA_WIDTH + FRACTION_BITS - 1 : FRACTION_BITS];
                    done   <= 1;
                    state  <= 2;
                end
                2: begin
                    done   <= 0;
                    busy   <= 0;
                    state  <= 0;
                end
            endcase
        end
    end
endmodule

module divider #(
    parameter DATA_WIDTH = 32,
    parameter FRACTION_BITS = 24
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic signed [DATA_WIDTH-1:0] numerator,
    input  logic signed [DATA_WIDTH-1:0] denominator,
    output logic signed [DATA_WIDTH-1:0] result,
    output logic done
);

    // Import DPI-C function
    import "DPI-C" function int fxp_div_q8_24(input int a, input int b);

    typedef enum logic [1:0] {IDLE, CALC, DONE} state_t;
    state_t state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state  <= IDLE;
            result <= 0;
            done   <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        result <= fxp_div_q8_24(numerator, denominator);
                        state  <= DONE;
                    end
                end
                DONE: begin
                    done <= 1;
                    if (!start)
                        state <= IDLE;
                end
            endcase
        end
    end

endmodule

