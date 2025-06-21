`timescale 1ns/1ps

module memory_module_tb;
  // Parameter definitions
  localparam int MEMORY_SIZE   = 10;
  localparam int HIDDEN_SIZE   = 10;
  localparam int DATA_WIDTH    = 32;  // Q8.24 fixed-point
  localparam int FRACTION_BITS = 24;

  // Testbench signals
  logic clk;
  logic reset;
  logic start;
logic signed [DATA_WIDTH-1:0] z [HIDDEN_SIZE];
logic signed [DATA_WIDTH-1:0] z_hat [HIDDEN_SIZE];
logic signed [DATA_WIDTH-1:0] q [MEMORY_SIZE];

  logic done;

  // Instantiate the DUT
  // Instantiate the DUT
  memory_module #(
    .MEMORY_SIZE(MEMORY_SIZE),
    .HIDDEN_SIZE(HIDDEN_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .FRACTION_BITS(FRACTION_BITS)
  ) dut (
    .clk(clk),
    .reset(reset),
    .start(start),
    .z(z),
    .z_hat(z_hat),
    .q(q),
    .done(done)
  );

  // Clock generation: 10ns period
  initial clk = 0;
  always #5 clk = ~clk;

  // Test stimulus
  initial begin
    // Apply reset
    reset = 1;
    start = 0;
    #20;
    reset = 0;

    // Initialize input vector z with fixed Q8.24 values
    z[0] = 32'hfffe2112; // -0.00730789
    z[1] = 32'hfffa3005; // -0.02270476
    z[2] = 32'hfffdf2d8; // -0.00801322
    z[3] = 32'hfffddf57; // -0.00831087
    z[4] = 32'h000a70aa; //  0.04078164
    z[5] = 32'h00042252; //  0.01614867
    z[6] = 32'h000ae6d1; //  0.04258447
    z[7] = 32'hfff0ce1e; // -0.05935493
    z[8] = 32'h000330b7; //  0.01246207
    z[9] = 32'h001d0174; //  0.11330345


    // Start the operation
    #10;
    start = 1;
    @(posedge clk);
    start = 0;

    // Wait for completion
    wait(done);
    #10;

    // Display results
    $display("=== Simulation Results ===");
    for (int i = 0; i < HIDDEN_SIZE; i++) begin
      $display("z_hat[%0d] = %08h", i, z_hat[i]);
    end
    for (int i = 0; i < MEMORY_SIZE; i++) begin
      $display("q[%0d]     = %08h", i, q[i]);
    end

    #10;
    $finish;
  end
endmodule
