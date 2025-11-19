//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
//Date        : Tue Nov 18 12:10:53 2025
//Host        : S-K running 64-bit major release  (build 9200)
//Command     : generate_target design_1_wrapper.bd
//Design      : design_1_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module design_1_wrapper
   (pmod_btn_sw1,
    pmod_i2s2_bclk,
    pmod_i2s2_dout,
    pmod_i2s2_lrclk,
    pmod_i2s_bclk,
    pmod_i2s_dout,
    pmod_i2s_lrclk,
    pmod_led_d1);
  input pmod_btn_sw1;
  output pmod_i2s2_bclk;
  output pmod_i2s2_dout;
  output pmod_i2s2_lrclk;
  output pmod_i2s_bclk;
  input pmod_i2s_dout;
  output pmod_i2s_lrclk;
  output pmod_led_d1;

  wire pmod_btn_sw1;
  wire pmod_i2s2_bclk;
  wire pmod_i2s2_dout;
  wire pmod_i2s2_lrclk;
  wire pmod_i2s_bclk;
  wire pmod_i2s_dout;
  wire pmod_i2s_lrclk;
  wire pmod_led_d1;

  design_1 design_1_i
       (.pmod_btn_sw1(pmod_btn_sw1),
        .pmod_i2s2_bclk(pmod_i2s2_bclk),
        .pmod_i2s2_dout(pmod_i2s2_dout),
        .pmod_i2s2_lrclk(pmod_i2s2_lrclk),
        .pmod_i2s_bclk(pmod_i2s_bclk),
        .pmod_i2s_dout(pmod_i2s_dout),
        .pmod_i2s_lrclk(pmod_i2s_lrclk),
        .pmod_led_d1(pmod_led_d1));
endmodule
