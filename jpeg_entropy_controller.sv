`timescale 1ns / 1ps
// Entropy decoder for a restricted first JPEG version:
//   * baseline sequential, 8-bit samples
//   * three components in 4:4:4 sampling (one Y, Cb, Cr block per MCU)
//   * fixed Annex K Huffman tables with IDs 0 and 1
//   * restart intervals disabled
//
// The controller consumes the bit-reader lookahead, reconstructs one block of
// signed quantized DCT coefficients, then streams its 64 coefficients in
// zig-zag order to the dequantizer/IDCT side.
module jpeg_entropy_controller (
    input  logic        clk,
    input  logic        rst,
    input  logic        start_scan_i,
    input  logic [15:0] image_width_i,
    input  logic [15:0] image_height_i,

    // Table selectors from SOS, packed by scan component:
    // component 0 is [11:8], component 1 is [7:4], component 2 is [3:0].
    input  logic [11:0] dc_table_ids_i,
    input  logic [11:0] ac_table_ids_i,

    // Connection to jpeg_entropy_bit_reader.
    input  logic [15:0] lookahead_i,
    input  logic [6:0]  bits_available_i,
    output logic        consume_valid_o,
    output logic [4:0]  consume_count_o,
    input  logic        consume_ready_i,

    // Completed coefficient block stream. coef_index_o is zig-zag position.
    output logic        coef_valid_o,
    input  logic        coef_ready_i,
    output logic [5:0]  coef_index_o,
    output logic signed [15:0] coef_data_o,
    output logic [1:0]  component_index_o,

    output logic        scan_done_o,
    output logic        error_o
);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_BLOCK_START,
        ST_DC_HUFF,
        ST_DC_EXTRA,
        ST_AC_HUFF,
        ST_AC_EXTRA,
        ST_BLOCK_OUTPUT,
        ST_DONE,
        ST_ERROR
    } state_t;

    state_t state, state_next;

    logic [1:0]  component_index, component_index_next;
    logic [6:0]  ac_position, ac_position_next;
    logic [4:0]  dc_category, dc_category_next;
    logic [3:0]  ac_size, ac_size_next;
    logic [5:0]  output_index, output_index_next;
    logic [31:0] blocks_remaining, blocks_remaining_next;

    // One packed 64-entry block; coefficient 0 occupies the least-significant
    // 16 bits, coefficient 63 the most-significant 16 bits.
    logic [1023:0] coefficient_block, coefficient_block_next;

    logic signed [15:0] dc_predictor_0, dc_predictor_0_next;
    logic signed [15:0] dc_predictor_1, dc_predictor_1_next;
    logic signed [15:0] dc_predictor_2, dc_predictor_2_next;

    logic [3:0] selected_dc_table_id;
    logic [3:0] selected_ac_table_id;
    logic signed [15:0] selected_dc_predictor;

    logic dc0_valid, dc1_valid, ac0_valid, ac1_valid;
    logic [4:0] dc0_length, dc1_length, ac0_length, ac1_length;
    logic [7:0] dc0_symbol, dc1_symbol, ac0_symbol, ac1_symbol;

    logic selected_huff_valid;
    logic [4:0] selected_huff_length;
    logic [7:0] selected_huff_symbol;

    logic [15:0] dc_raw_bits, ac_raw_bits;
    logic signed [15:0] decoded_dc_difference, decoded_ac_value;
    logic signed [15:0] decoded_dc_value;
    logic [31:0] mcu_columns, mcu_rows, total_blocks;

    function automatic logic signed [15:0] extend_amplitude (
        input logic [15:0] raw_value,
        input logic [4:0]  size
    );
        logic [16:0] threshold;
        logic [16:0] magnitude_mask;
        logic signed [16:0] extended_value;
        begin
            if (size == 5'd0) begin
                extend_amplitude = 16'sd0;
            end
            else begin
                threshold     = 17'd1 << (size - 1'b1);
                magnitude_mask = (17'd1 << size) - 17'd1;

                if ({1'b0, raw_value} < threshold)
                    extended_value = $signed({1'b0, raw_value}) -
                                     $signed(magnitude_mask);
                else
                    extended_value = $signed({1'b0, raw_value});

                extend_amplitude = extended_value[15:0];
            end
        end
    endfunction

    // Each fixed Huffman module is combinational. The controller selects the
    // active DC or AC result using the current SOS table ID.
    jpeg_huffman_dc0_luma u_dc0 (
        .code_prefix_i  (lookahead_i),
        .symbol_valid_o (dc0_valid),
        .code_length_o  (dc0_length),
        .symbol_o       (dc0_symbol)
    );

    jpeg_huffman_dc1_chroma u_dc1 (
        .code_prefix_i  (lookahead_i),
        .symbol_valid_o (dc1_valid),
        .code_length_o  (dc1_length),
        .symbol_o       (dc1_symbol)
    );

    jpeg_huffman_ac0_luma u_ac0 (
        .code_prefix_i  (lookahead_i),
        .symbol_valid_o (ac0_valid),
        .code_length_o  (ac0_length),
        .symbol_o       (ac0_symbol)
    );

    jpeg_huffman_ac1_chroma u_ac1 (
        .code_prefix_i  (lookahead_i),
        .symbol_valid_o (ac1_valid),
        .code_length_o  (ac1_length),
        .symbol_o       (ac1_symbol)
    );

    // Select the SOS table IDs and DC predictor for the current component.
    always_comb begin
        selected_dc_table_id = 4'd0;
        selected_ac_table_id = 4'd0;
        selected_dc_predictor = 16'sd0;

        case (component_index)
            2'd0: begin
                selected_dc_table_id = dc_table_ids_i[11:8];
                selected_ac_table_id = ac_table_ids_i[11:8];
                selected_dc_predictor = dc_predictor_0;
            end
            2'd1: begin
                selected_dc_table_id = dc_table_ids_i[7:4];
                selected_ac_table_id = ac_table_ids_i[7:4];
                selected_dc_predictor = dc_predictor_1;
            end
            2'd2: begin
                selected_dc_table_id = dc_table_ids_i[3:0];
                selected_ac_table_id = ac_table_ids_i[3:0];
                selected_dc_predictor = dc_predictor_2;
            end
            default: begin
                selected_dc_table_id = 4'hF;
                selected_ac_table_id = 4'hF;
                selected_dc_predictor = 16'sd0;
            end
        endcase
    end

    // Mux the selected Huffman table's combinational lookup result.
    always_comb begin
        selected_huff_valid  = 1'b0;
        selected_huff_length = 5'd0;
        selected_huff_symbol = 8'd0;

        case (state)
            ST_DC_HUFF: begin
                case (selected_dc_table_id)
                    4'd0: begin
                        selected_huff_valid  = dc0_valid;
                        selected_huff_length = dc0_length;
                        selected_huff_symbol = dc0_symbol;
                    end
                    4'd1: begin
                        selected_huff_valid  = dc1_valid;
                        selected_huff_length = dc1_length;
                        selected_huff_symbol = dc1_symbol;
                    end
                    default: ;
                endcase
            end

            ST_AC_HUFF: begin
                case (selected_ac_table_id)
                    4'd0: begin
                        selected_huff_valid  = ac0_valid;
                        selected_huff_length = ac0_length;
                        selected_huff_symbol = ac0_symbol;
                    end
                    4'd1: begin
                        selected_huff_valid  = ac1_valid;
                        selected_huff_length = ac1_length;
                        selected_huff_symbol = ac1_symbol;
                    end
                    default: ;
                endcase
            end

            default: ;
        endcase
    end

    // Image is restricted to 4:4:4: one MCU is one 8x8 block per component.
    always_comb begin
        mcu_columns = ({16'd0, image_width_i}  + 32'd7) >> 3;
        mcu_rows    = ({16'd0, image_height_i} + 32'd7) >> 3;
        total_blocks = mcu_columns * mcu_rows * 32'd3;
    end

    always_comb begin
        state_next            = state;
        component_index_next  = component_index;
        ac_position_next      = ac_position;
        dc_category_next      = dc_category;
        ac_size_next          = ac_size;
        output_index_next     = output_index;
        blocks_remaining_next = blocks_remaining;
        coefficient_block_next = coefficient_block;

        dc_predictor_0_next = dc_predictor_0;
        dc_predictor_1_next = dc_predictor_1;
        dc_predictor_2_next = dc_predictor_2;

        consume_valid_o = 1'b0;
        consume_count_o = 5'd0;
        coef_valid_o = 1'b0;
        coef_index_o = output_index;
        coef_data_o = $signed(coefficient_block[output_index*16 +: 16]);
        component_index_o = component_index;
        scan_done_o = (state == ST_DONE);
        error_o = (state == ST_ERROR);

        dc_raw_bits = 16'd0;
        ac_raw_bits = 16'd0;
        decoded_dc_difference = 16'sd0;
        decoded_ac_value = 16'sd0;
        decoded_dc_value = 16'sd0;

        case (state)
            ST_IDLE: begin
                if (start_scan_i) begin
                    if ((image_width_i == 16'd0) ||
                        (image_height_i == 16'd0) ||
                        (total_blocks == 32'd0) ||
                        (dc_table_ids_i[11:8] > 4'd1) ||
                        (dc_table_ids_i[7:4]  > 4'd1) ||
                        (dc_table_ids_i[3:0]  > 4'd1) ||
                        (ac_table_ids_i[11:8] > 4'd1) ||
                        (ac_table_ids_i[7:4]  > 4'd1) ||
                        (ac_table_ids_i[3:0]  > 4'd1)) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        component_index_next = 2'd0;
                        blocks_remaining_next = total_blocks;
                        dc_predictor_0_next = 16'sd0;
                        dc_predictor_1_next = 16'sd0;
                        dc_predictor_2_next = 16'sd0;
                        state_next = ST_BLOCK_START;
                    end
                end
            end

            ST_BLOCK_START: begin
                coefficient_block_next = 1024'd0;
                ac_position_next = 7'd1;
                output_index_next = 6'd0;
                state_next = ST_DC_HUFF;
            end

            ST_DC_HUFF: begin
                // A code may be accepted only if its complete prefix is buffered.
                if (selected_huff_valid &&
                    (selected_huff_length <= bits_available_i)) begin
                    consume_valid_o = 1'b1;
                    consume_count_o = selected_huff_length;

                    if (consume_ready_i) begin
                        if (selected_huff_symbol > 8'd11) begin
                            state_next = ST_ERROR;
                        end
                        else begin
                            dc_category_next = selected_huff_symbol[4:0];
                            state_next = ST_DC_EXTRA;
                        end
                    end
                end
            end

            ST_DC_EXTRA: begin
                if (dc_category == 5'd0) begin
                    decoded_dc_value = selected_dc_predictor;
                    coefficient_block_next[15:0] = decoded_dc_value;
                    state_next = ST_AC_HUFF;
                end
                else if (bits_available_i >= dc_category) begin
                    consume_valid_o = 1'b1;
                    consume_count_o = dc_category;

                    if (consume_ready_i) begin
                        dc_raw_bits = lookahead_i >> (16 - dc_category);
                        decoded_dc_difference = extend_amplitude(dc_raw_bits, dc_category);
                        decoded_dc_value = selected_dc_predictor + decoded_dc_difference;
                        coefficient_block_next[15:0] = decoded_dc_value;

                        case (component_index)
                            2'd0: dc_predictor_0_next = decoded_dc_value;
                            2'd1: dc_predictor_1_next = decoded_dc_value;
                            2'd2: dc_predictor_2_next = decoded_dc_value;
                            default: state_next = ST_ERROR;
                        endcase

                        if (state_next != ST_ERROR)
                            state_next = ST_AC_HUFF;
                    end
                end
            end

            ST_AC_HUFF: begin
                if (selected_huff_valid &&
                    (selected_huff_length <= bits_available_i)) begin
                    consume_valid_o = 1'b1;
                    consume_count_o = selected_huff_length;

                    if (consume_ready_i) begin
                        if (selected_huff_symbol == 8'h00) begin
                            // EOB: the untouched coefficient locations are zero.
                            output_index_next = 6'd0;
                            state_next = ST_BLOCK_OUTPUT;
                        end
                        else if (selected_huff_symbol == 8'hF0) begin
                            // ZRL skips sixteen zero AC coefficients.
                            if ((ac_position + 7'd16) > 7'd64) begin
                                state_next = ST_ERROR;
                            end
                            else if ((ac_position + 7'd16) == 7'd64) begin
                                output_index_next = 6'd0;
                                state_next = ST_BLOCK_OUTPUT;
                            end
                            else begin
                                ac_position_next = ac_position + 7'd16;
                            end
                        end
                        else if (selected_huff_symbol[3:0] == 4'd0) begin
                            // Other size-zero run symbols are not valid here.
                            state_next = ST_ERROR;
                        end
                        else if (selected_huff_symbol[3:0] > 4'd10) begin
                            state_next = ST_ERROR;
                        end
                        else if ((ac_position +
                                  {3'd0, selected_huff_symbol[7:4]}) > 7'd63) begin
                            state_next = ST_ERROR;
                        end
                        else begin
                            ac_position_next = ac_position +
                                               {3'd0, selected_huff_symbol[7:4]};
                            ac_size_next = selected_huff_symbol[3:0];
                            state_next = ST_AC_EXTRA;
                        end
                    end
                end
            end

            ST_AC_EXTRA: begin
                if (bits_available_i >= {3'd0, ac_size}) begin
                    consume_valid_o = 1'b1;
                    consume_count_o = {1'b0, ac_size};

                    if (consume_ready_i) begin
                        ac_raw_bits = lookahead_i >> (16 - ac_size);
                        decoded_ac_value = extend_amplitude(ac_raw_bits,
                                                            {1'b0, ac_size});
                        coefficient_block_next[ac_position*16 +: 16] =
                            decoded_ac_value;

                        if (ac_position == 7'd63) begin
                            output_index_next = 6'd0;
                            state_next = ST_BLOCK_OUTPUT;
                        end
                        else begin
                            ac_position_next = ac_position + 7'd1;
                            state_next = ST_AC_HUFF;
                        end
                    end
                end
            end

            ST_BLOCK_OUTPUT: begin
                coef_valid_o = 1'b1;

                if (coef_ready_i) begin
                    if (output_index == 6'd63) begin
                        if (blocks_remaining == 32'd1) begin
                            blocks_remaining_next = 32'd0;
                            state_next = ST_DONE;
                        end
                        else begin
                            blocks_remaining_next = blocks_remaining - 32'd1;
                            if (component_index == 2'd2)
                                component_index_next = 2'd0;
                            else
                                component_index_next = component_index + 2'd1;
                            state_next = ST_BLOCK_START;
                        end
                    end
                    else begin
                        output_index_next = output_index + 6'd1;
                    end
                end
            end

            ST_DONE: begin
                // Allow another scan without requiring a module reset.
                if (start_scan_i) begin
                    if ((image_width_i == 16'd0) ||
                        (image_height_i == 16'd0) ||
                        (total_blocks == 32'd0) ||
                        (dc_table_ids_i[11:8] > 4'd1) ||
                        (dc_table_ids_i[7:4]  > 4'd1) ||
                        (dc_table_ids_i[3:0]  > 4'd1) ||
                        (ac_table_ids_i[11:8] > 4'd1) ||
                        (ac_table_ids_i[7:4]  > 4'd1) ||
                        (ac_table_ids_i[3:0]  > 4'd1)) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        component_index_next = 2'd0;
                        blocks_remaining_next = total_blocks;
                        dc_predictor_0_next = 16'sd0;
                        dc_predictor_1_next = 16'sd0;
                        dc_predictor_2_next = 16'sd0;
                        state_next = ST_BLOCK_START;
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
            state <= ST_IDLE;
            component_index <= 2'd0;
            ac_position <= 7'd1;
            dc_category <= 5'd0;
            ac_size <= 4'd0;
            output_index <= 6'd0;
            blocks_remaining <= 32'd0;
            coefficient_block <= 1024'd0;
            dc_predictor_0 <= 16'sd0;
            dc_predictor_1 <= 16'sd0;
            dc_predictor_2 <= 16'sd0;
        end
        else begin
            state <= state_next;
            component_index <= component_index_next;
            ac_position <= ac_position_next;
            dc_category <= dc_category_next;
            ac_size <= ac_size_next;
            output_index <= output_index_next;
            blocks_remaining <= blocks_remaining_next;
            coefficient_block <= coefficient_block_next;
            dc_predictor_0 <= dc_predictor_0_next;
            dc_predictor_1 <= dc_predictor_1_next;
            dc_predictor_2 <= dc_predictor_2_next;
        end
    end

endmodule
