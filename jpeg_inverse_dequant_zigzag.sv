`timescale 1ns / 1ps
// Reorders one entropy-decoded 8x8 coefficient block from JPEG zig-zag order
// into natural row-major order and applies the selected fixed quant table.
//
// The fixed quant ROMs are the Annex K example tables in jpeg_fixed_tables.sv.
// This module therefore supports only table IDs 0 and 1, and only works for
// JPEGs whose DQT values match those ROMs.
//
// Input contract:
//   * One block arrives as 64 handshaken coefficients, index 0 through 63.
//   * coef_index_i is the JPEG zig-zag position.
//   * component_index_i is 0, 1, or 2 in the same component order used by
//     q_table_ids_i (component 0 in [11:8], component 1 in [7:4], component 2
//     in [3:0]).
//
// Output contract:
//   * After collecting all 64 inputs, emit 64 dequantized values in natural
//     row-major order. coeff_index_o is 0..63; index = row*8 + column.
//   * Connect this stream to an IDCT block. The output values are signed 24-bit
//     DCT coefficients after inverse quantization.
module jpeg_inverse_zigzag_dequant (
    input  logic                   clk,
    input  logic                   rst,

    input  logic                   coef_valid_i,
    output logic                   coef_ready_o,
    input  logic [5:0]             coef_index_i,
    input  logic signed [15:0]     coef_data_i,
    input  logic [1:0]             component_index_i,

    // SOF0 quant-table selectors, packed in the same component order as above.
    input  logic [11:0]            q_table_ids_i,

    output logic                   idct_coef_valid_o,
    input  logic                   idct_coef_ready_i,
    output logic [5:0]             idct_coef_index_o,
    output logic signed [23:0]     idct_coef_data_o,
    output logic [1:0]             idct_component_index_o,
    output logic                   idct_block_start_o,
    output logic                   idct_block_last_o,

    output logic                   error_o
);

    typedef enum logic [1:0] {
        ST_COLLECT,
        ST_OUTPUT,
        ST_ERROR
    } state_t;

    state_t state, state_next;

    // Packed 64 x 24-bit storage; each coefficient is written at its natural
    // row-major position after inverse-zigzag mapping.
    logic [64*24-1:0] block_buffer;
    logic [64*24-1:0] block_buffer_next;
    logic [5:0] expected_zigzag_index;
    logic [5:0] expected_zigzag_index_next;
    logic [5:0] output_index;
    logic [5:0] output_index_next;
    logic [1:0] block_component;
    logic [1:0] block_component_next;

    logic [5:0] natural_index;
    logic [3:0] selected_q_table_id;
    logic [7:0] quant_value_q0;
    logic [7:0] quant_value_q1;
    logic [7:0] selected_quant_value;
    logic signed [23:0] coefficient_extended;
    logic signed [23:0] quant_extended;
    logic signed [23:0] dequantized_value;

    function automatic logic [5:0] zigzag_to_natural(input logic [5:0] index);
        begin
            case (index)
                 0: zigzag_to_natural =  0;  1: zigzag_to_natural =  1;
                 2: zigzag_to_natural =  8;  3: zigzag_to_natural = 16;
                 4: zigzag_to_natural =  9;  5: zigzag_to_natural =  2;
                 6: zigzag_to_natural =  3;  7: zigzag_to_natural = 10;
                 8: zigzag_to_natural = 17;  9: zigzag_to_natural = 24;
                10: zigzag_to_natural = 32; 11: zigzag_to_natural = 25;
                12: zigzag_to_natural = 18; 13: zigzag_to_natural = 11;
                14: zigzag_to_natural =  4; 15: zigzag_to_natural =  5;
                16: zigzag_to_natural = 12; 17: zigzag_to_natural = 19;
                18: zigzag_to_natural = 26; 19: zigzag_to_natural = 33;
                20: zigzag_to_natural = 40; 21: zigzag_to_natural = 48;
                22: zigzag_to_natural = 41; 23: zigzag_to_natural = 34;
                24: zigzag_to_natural = 27; 25: zigzag_to_natural = 20;
                26: zigzag_to_natural = 13; 27: zigzag_to_natural =  6;
                28: zigzag_to_natural =  7; 29: zigzag_to_natural = 14;
                30: zigzag_to_natural = 21; 31: zigzag_to_natural = 28;
                32: zigzag_to_natural = 35; 33: zigzag_to_natural = 42;
                34: zigzag_to_natural = 49; 35: zigzag_to_natural = 56;
                36: zigzag_to_natural = 57; 37: zigzag_to_natural = 50;
                38: zigzag_to_natural = 43; 39: zigzag_to_natural = 36;
                40: zigzag_to_natural = 29; 41: zigzag_to_natural = 22;
                42: zigzag_to_natural = 15; 43: zigzag_to_natural = 23;
                44: zigzag_to_natural = 30; 45: zigzag_to_natural = 37;
                46: zigzag_to_natural = 44; 47: zigzag_to_natural = 51;
                48: zigzag_to_natural = 58; 49: zigzag_to_natural = 59;
                50: zigzag_to_natural = 52; 51: zigzag_to_natural = 45;
                52: zigzag_to_natural = 38; 53: zigzag_to_natural = 31;
                54: zigzag_to_natural = 39; 55: zigzag_to_natural = 46;
                56: zigzag_to_natural = 53; 57: zigzag_to_natural = 60;
                58: zigzag_to_natural = 61; 59: zigzag_to_natural = 54;
                60: zigzag_to_natural = 47; 61: zigzag_to_natural = 55;
                62: zigzag_to_natural = 62; 63: zigzag_to_natural = 63;
                default: zigzag_to_natural = 0;
            endcase
        end
    endfunction

    jpeg_quant_table_0_luma u_quant_table_0 (
        .index_i (coef_index_i),
        .value_o (quant_value_q0)
    );

    jpeg_quant_table_1_chroma u_quant_table_1 (
        .index_i (coef_index_i),
        .value_o (quant_value_q1)
    );

    always_comb begin
        selected_q_table_id = 4'hF;
        case (component_index_i)
            2'd0: selected_q_table_id = q_table_ids_i[11:8];
            2'd1: selected_q_table_id = q_table_ids_i[7:4];
            2'd2: selected_q_table_id = q_table_ids_i[3:0];
            default: selected_q_table_id = 4'hF;
        endcase

        selected_quant_value = 8'd0;
        case (selected_q_table_id)
            4'd0: selected_quant_value = quant_value_q0;
            4'd1: selected_quant_value = quant_value_q1;
            default: selected_quant_value = 8'd0;
        endcase

        natural_index = zigzag_to_natural(coef_index_i);
        coefficient_extended = {{8{coef_data_i[15]}}, coef_data_i};
        quant_extended = $signed({16'd0, selected_quant_value});
        dequantized_value = coefficient_extended * quant_extended;

        coef_ready_o = (state == ST_COLLECT);

        idct_coef_valid_o = (state == ST_OUTPUT);
        idct_coef_index_o = output_index;
        idct_coef_data_o = $signed(block_buffer[output_index*24 +: 24]);
        idct_component_index_o = block_component;
        idct_block_start_o = idct_coef_valid_o && (output_index == 6'd0);
        idct_block_last_o  = idct_coef_valid_o && (output_index == 6'd63);
        error_o = (state == ST_ERROR);
    end

    // All state transitions and register next-value decisions are combinational.
    always_comb begin
        state_next                 = state;
        block_buffer_next          = block_buffer;
        expected_zigzag_index_next = expected_zigzag_index;
        output_index_next          = output_index;
        block_component_next       = block_component;

        case (state)
            ST_COLLECT: begin
                if (coef_valid_i && coef_ready_o) begin
                    if ((coef_index_i != expected_zigzag_index) ||
                        (component_index_i > 2'd2) ||
                        (selected_q_table_id > 4'd1) ||
                        ((expected_zigzag_index != 6'd0) &&
                         (component_index_i != block_component))) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        block_buffer_next[natural_index*24 +: 24] = dequantized_value;

                        if (expected_zigzag_index == 6'd0)
                            block_component_next = component_index_i;

                        if (expected_zigzag_index == 6'd63) begin
                            output_index_next = 6'd0;
                            state_next = ST_OUTPUT;
                        end
                        else begin
                            expected_zigzag_index_next = expected_zigzag_index + 6'd1;
                        end
                    end
                end
            end

            ST_OUTPUT: begin
                if (idct_coef_valid_o && idct_coef_ready_i) begin
                    if (output_index == 6'd63) begin
                        output_index_next = 6'd0;
                        expected_zigzag_index_next = 6'd0;
                        state_next = ST_COLLECT;
                    end
                    else begin
                        output_index_next = output_index + 6'd1;
                    end
                end
            end

            ST_ERROR: begin
                state_next = ST_ERROR;
            end

            default: begin
                state_next = ST_ERROR;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state                  <= ST_COLLECT;
            block_buffer           <= '0;
            expected_zigzag_index  <= 6'd0;
            output_index           <= 6'd0;
            block_component        <= 2'd0;
        end
        else begin
            state                 <= state_next;
            block_buffer          <= block_buffer_next;
            expected_zigzag_index <= expected_zigzag_index_next;
            output_index          <= output_index_next;
            block_component       <= block_component_next;
        end
    end

endmodule
