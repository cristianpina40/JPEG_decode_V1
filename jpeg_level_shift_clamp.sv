`timescale 1ns / 1ps
// JPEG level-shift and clamp stage.
//
// IDCT output is centered around zero. JPEG sample values are formed by adding
// 128, then saturating to the legal unsigned 8-bit range [0, 255]. This is a
// combinational ready/valid pass-through stage and preserves block metadata.
module jpeg_level_shift_clamp (
    input  logic                   sample_valid_i,
    output logic                   sample_ready_o,
    input  logic [5:0]             sample_index_i,
    input  logic signed [23:0]     sample_data_i,
    input  logic [1:0]             component_index_i,
    input  logic                   sample_block_start_i,
    input  logic                   sample_block_last_i,

    output logic                   pixel_valid_o,
    input  logic                   pixel_ready_i,
    output logic [5:0]             pixel_index_o,
    output logic [7:0]             pixel_data_o,
    output logic [1:0]             component_index_o,
    output logic                   pixel_block_start_o,
    output logic                   pixel_block_last_o
);

    logic signed [24:0] shifted_sample;

    always_comb begin
        // A transfer is accepted only when the downstream pixel consumer is ready.
        sample_ready_o = pixel_ready_i;
        pixel_valid_o = sample_valid_i;

        pixel_index_o = sample_index_i;
        component_index_o = component_index_i;
        pixel_block_start_o = sample_block_start_i;
        pixel_block_last_o = sample_block_last_i;

        shifted_sample = $signed({sample_data_i[23], sample_data_i}) + 25'sd128;

        if (shifted_sample < 25'sd0)
            pixel_data_o = 8'd0;
        else if (shifted_sample > 25'sd255)
            pixel_data_o = 8'd255;
        else
            pixel_data_o = shifted_sample[7:0];
    end

endmodule
