`timescale 1ns/1ps
// QVision global configuration: define exactly ONE board family.
`define BOARD_FAMILY_ZYNQ          // RealDigital Blackboard, 100 MHz clock
// `define BOARD_FAMILY_S6          // Spartan-6, 50 MHz clock
// `define BOARD_FAMILY_S3          // Spartan-3, 50 MHz clock

`define CLK_IN_HZ  100000000       // Blackboard system clock
// `define CLK_IN_HZ 50000000      // use for Spartan-3 / Spartan-6 boards
`define UART_BAUD  115200
`define COLOR_BITS 4

// QR capabilities, versions 1-40, all EC levels and modes.
// Constants are re-derived by scripts/gen_tables.py.
`define QR_MIN_SIZE     21         // V1 modules per side
`define QR_MAX_SIZE     177        // V40 modules per side
`define FB_DEPTH        31329      // QR_MAX_SIZE^2
`define FB_ADDR_BITS    15
`define BUF_SIZE        4096       // payload buffer, power of two
`define BUF_ADDR_BITS   12         // max payload 2956 bytes (V40-L)
`define LEN_BITS        13         // 13 bits: a full 4096-byte buffer must not wrap
`define RS_MAX_DATA_CW  2956       // largest total data-codeword count (V40-L)
`define RS_MAX_PARITY   30         // largest per-block ECC count (V40-H)
`define RS_MAX_TOTAL    3706       // largest total codeword count (V40-L)
`define RS_MAX_BLOCKS   81         // largest block count (V40-Q)
`define RS_PARITY_RAM   (`RS_MAX_BLOCKS * `RS_MAX_PARITY)  // 2430 bytes
