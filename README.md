# TSMAE Hardware Implementation in SystemVerilog for FPGA

## Overview

This project presents a hardware implementation of the Time-Series Memory-Augmented Autoencoder (TSMAE), as described in the IEEE paper "TSMAE: A Novel Anomaly Detection Approach for Internet of Things Time Series Data" (Gao et al., IEEE TNSE, 2023). The TSMAE is designed for anomaly detection in time-series IoT data, leveraging a memory-enhanced LSTM autoencoder architecture. This implementation is written in SystemVerilog, utilizing signed fixed-point Q8.24 arithmetic, and is tailored for deployment on FPGA platforms. The design is fully configurable and replicates the behavior of a Python-trained TSMAE model by incorporating its pretrained weights and biases.
## Synthesis Status

The current full system includes DPI-C modules for nonlinear functions and fixed-point division, which are not synthesizable. To ensure compatibility with FPGA/ASIC toolchains:

- A synthesizable version of the encoder + memory pipeline is under development using LUT-based sigmoid and a pipelined divider.
- Individual RTL blocks (e.g., `encoder_LSTM`, `memory_module`) can be synthesized standalone after removing DPI-C dependencies and memory loading.
- Full-system synthesis is feasible and planned; current focus is on functional verification and hardware-software matching.

Timing and resource reports will be provided in future updates.
## System Architecture

The hardware design is modular and consists of the following key components:

- **TSMAE Top Module**: Orchestrates the data flow through the encoder, memory, and decoder stages.
- **Encoder LSTM**: Processes time-series input to generate a latent vector `z`.
- **Memory Module**: Performs similarity-based sparse addressing to produce the memory-adjusted latent vector `z_hat`.
- **Decoder LSTM**: Reconstructs the input sequence from `z_hat`.
- **Arithmetic Units**: Includes fixed-point implementations of `softmax`, `tanh`, `sigmoid`, and other operations.

### Hyperparameters

| Parameter       | Value       | Description                              |
|-----------------|-------------|------------------------------------------|
| DATA_WIDTH      | 32 bits     | Total bit width for fixed-point data     |
| FRACT_WIDTH     | 24 bits     | Fractional bits in Q8.24 format          |
| INPUT_SIZE      | 1           | Dimension of input time-series data      |
| HIDDEN_SIZE     | 10          | Size of LSTM hidden states               |
| MEMORY_SIZE     | 10          | Size of memory module                    |
| SEQ_LEN         | 10          | Length of input sequence                 |
| SCALE_WTS       | 0.05        | Scaling factor for weights               |
| FIXED-POINT     | Q8.24       | Fixed-point format for arithmetic        |

## Directory Structure

```
TSMAE-fixedpoint-8.24/
├── docs/
│   └── TSMAE_A_Novel_Anomaly_Detection_Approach_for_Internet_of_Things_Time_Series_Data.pdf
├── sim/
│   └── TSMAE_wave_form_viewer.png
├── src/
│   ├── data/
│   │   ├── b_hh_dec.mem
│   │   ├── b_hh_enc.mem
│   │   ├── b_ih_dec.mem
│   │   ├── b_ih_enc.mem
│   │   ├── memory.mem
│   │   ├── output_bias.mem
│   │   ├── output_weights.mem
│   │   ├── test_inputs.mem
│   │   ├── W_hh_dec.mem
│   │   ├── W_hh_enc.mem
│   │   ├── W_ih_dec.mem
│   │   └── W_ih_enc.mem
│   ├── DPI-C/
│   │   ├── fxp_div.cpp
│   │   ├── sigmoid.c
│   │   └── tanh.c
│   └── verilog/
│       ├── submodule/
│       │   ├── decoder_LSTM.sv
│       │   ├── decoder_lstm_cell.sv
│       │   ├── encoder_LSTM.sv
│       │   ├── encoder_lstm_cell.sv
│       │   └── memory_module.sv
│       ├── testbench/
│       │   ├── tb_decoder.sv
│       │   ├── tb_decoder_cell.sv
│       │   ├── tb_encoder.sv
│       │   ├── tb_encoder_cell.sv
│       │   ├── tb_memory.sv
│       │   └── tb_top_module/
│       │       └── tb_tsmae.sv
│       └── top_module/
│           └── tsmae.sv
└── verify/
    ├── TSMAE_model.py
    ├── comparison_TSMAE_verilog_result.txt
    ├── reference_TSMAE.py
    └── reference_TSMAE_python_result.txt
```

## Simulation Instructions

To simulate the TSMAE design:

1. Compile the SystemVerilog source files in the `src/verilog` directory using a Verilog simulator (e.g., ModelSim, Vivado, or Verilator).
2. Load the input sequence, weights, and biases from the Python-trained model into the `.mem` files located in `src/data`.
3. Run the simulation for the encoder, memory, and decoder pipeline.
4. Compare the simulation outputs with the reference results in the `verify` directory to validate correctness.

## Testing and Validation

The project includes comprehensive testbenches for the main modules:

- `tb_encoder_cell.sv`
- `tb_decoder_cell.sv`
- `tb_encoder.sv`
- `tb_decoder.sv`
- `tb_memory_module.sv`
- `tb_tsmae.sv`

Test cases are derived from the Python reference implementation (`reference_TSMAE.py`). The simulation results are stored in:

- `comparison_TSMAE_verilog_result.txt`: Outputs from the Verilog simulation.
- `reference_TSMAE_python_result.txt`: Outputs from the Python reference model.

These files contain matching results for the input `x`, latent vector `z`, memory-adjusted vector `z_hat`, and reconstructed output `x_recon`, confirming that the hardware implementation accurately replicates the software model within the constraints of Q8.24 fixed-point arithmetic.

Waveforms from the simulation can be visualized using the `TSMAE_wave_form_viewer.png` file in the `sim` directory.

## Synthesis Guidelines

To prepare the design for FPGA or ASIC synthesis, the following modifications are recommended:

1. **DPI-C Modules**: Replace the DPI-C functions (`sigmoid.c`, `tanh.c`, `fxp_div.cpp`) with lookup tables (LUTs) or equivalent SystemVerilog implementations to ensure synthesizability.
2. **Memory Initialization**: The `$readmemh` function used for memory initialization is not synthesizable in RTL modules. Instead, perform memory loading in the testbench or use FPGA-compatible formats (e.g., `.coe` or `.mif` files) for BRAM preloading.

## Authors

- **TSMAE Verilog Implementation**: Phan Chau Phong
- **Based on**: Gao et al., "TSMAE: A Novel Anomaly Detection Approach for IoT Time Series Data," IEEE Transactions on Network and Service Management, 2023.
