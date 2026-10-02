`timescale 1ns / 1ps
// Small-area, iterative, separable 8x8 JPEG inverse DCT.
//
// Input is one dequantized coefficient block in natural row-major order.
// The block is buffered, transformed in two passes using one multiply-accumulate
// datapath, and then emitted as 64 signed spatial samples in row-major order.
// The fixed-point transform matrix is Q14, with A[x,u] = 0.5*C(u)*cos(...).
// Applying A in both dimensions includes the JPEG IDCT's overall 1/4 factor.
//
// Output samples are centered around zero. Add 128 and clamp to 0..255 in the
// following level-shift/pixel stage.
module jpeg_idct_8x8 (
    input  logic                   clk,
    input  logic                   rst,

    input  logic                   coef_valid_i,
    output logic                   coef_ready_o,
    input  logic [5:0]             coef_index_i,
    input  logic signed [23:0]     coef_data_i,
    input  logic [1:0]             component_index_i,
    input  logic                   coef_block_start_i,
    input  logic                   coef_block_last_i,

    output logic                   sample_valid_o,
    input  logic                   sample_ready_i,
    output logic [5:0]             sample_index_o,
    output logic signed [23:0]     sample_data_o,
    output logic [1:0]             sample_component_index_o,
    output logic                   sample_block_start_o,
    output logic                   sample_block_last_o,

    output logic                   error_o
);

    typedef enum logic [2:0] {
        ST_COLLECT,
        ST_HORIZONTAL_MAC,
        ST_VERTICAL_MAC,
        ST_OUTPUT,
        ST_ERROR
    } state_t;

    state_t state, state_next;

    logic [64*24-1:0] coefficient_buffer, coefficient_buffer_next;
    logic [64*48-1:0] horizontal_buffer, horizontal_buffer_next;
    logic [64*24-1:0] sample_buffer, sample_buffer_next;

    logic [5:0] input_index, input_index_next;
    logic [1:0] block_component, block_component_next;
    logic [5:0] horizontal_output_index, horizontal_output_index_next;
    logic [2:0] horizontal_inner_index, horizontal_inner_index_next;
    logic [5:0] vertical_output_index, vertical_output_index_next;
    logic [2:0] vertical_inner_index, vertical_inner_index_next;
    logic [5:0] sample_output_index, sample_output_index_next;

    logic signed [47:0] horizontal_accumulator, horizontal_accumulator_next;
    logic signed [63:0] vertical_accumulator, vertical_accumulator_next;

    logic signed [23:0] horizontal_input_coefficient;
    logic signed [15:0] horizontal_matrix_value;
    logic signed [39:0] horizontal_product;
    logic signed [47:0] horizontal_sum;

    logic signed [47:0] vertical_input_value;
    logic signed [15:0] vertical_matrix_value;
    logic signed [63:0] vertical_product;
    logic signed [63:0] vertical_sum;
    logic signed [63:0] rounded_vertical_sum;

    function automatic logic signed [15:0] idct_matrix_q14(
        input logic [2:0] x,
        input logic [2:0] u
    );
        begin
            idct_matrix_q14 = 16'sd0;
            case (x)
                3'd0: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 =  16'sd8035;
                    2: idct_matrix_q14 =  16'sd7568; 3: idct_matrix_q14 =  16'sd6811;
                    4: idct_matrix_q14 =  16'sd5793; 5: idct_matrix_q14 =  16'sd4551;
                    6: idct_matrix_q14 =  16'sd3135; 7: idct_matrix_q14 =  16'sd1598;
                endcase
                3'd1: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 =  16'sd6811;
                    2: idct_matrix_q14 =  16'sd3135; 3: idct_matrix_q14 = -16'sd1598;
                    4: idct_matrix_q14 = -16'sd5793; 5: idct_matrix_q14 = -16'sd8035;
                    6: idct_matrix_q14 = -16'sd7568; 7: idct_matrix_q14 = -16'sd4551;
                endcase
                3'd2: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 =  16'sd4551;
                    2: idct_matrix_q14 = -16'sd3135; 3: idct_matrix_q14 = -16'sd8035;
                    4: idct_matrix_q14 = -16'sd5793; 5: idct_matrix_q14 =  16'sd1598;
                    6: idct_matrix_q14 =  16'sd7568; 7: idct_matrix_q14 =  16'sd6811;
                endcase
                3'd3: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 =  16'sd1598;
                    2: idct_matrix_q14 = -16'sd7568; 3: idct_matrix_q14 = -16'sd4551;
                    4: idct_matrix_q14 =  16'sd5793; 5: idct_matrix_q14 =  16'sd6811;
                    6: idct_matrix_q14 = -16'sd3135; 7: idct_matrix_q14 = -16'sd8035;
                endcase
                3'd4: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 = -16'sd1598;
                    2: idct_matrix_q14 = -16'sd7568; 3: idct_matrix_q14 =  16'sd4551;
                    4: idct_matrix_q14 =  16'sd5793; 5: idct_matrix_q14 = -16'sd6811;
                    6: idct_matrix_q14 = -16'sd3135; 7: idct_matrix_q14 =  16'sd8035;
                endcase
                3'd5: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 = -16'sd4551;
                    2: idct_matrix_q14 = -16'sd3135; 3: idct_matrix_q14 =  16'sd8035;
                    4: idct_matrix_q14 = -16'sd5793; 5: idct_matrix_q14 = -16'sd1598;
                    6: idct_matrix_q14 =  16'sd7568; 7: idct_matrix_q14 = -16'sd6811;
                endcase
                3'd6: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 = -16'sd6811;
                    2: idct_matrix_q14 =  16'sd3135; 3: idct_matrix_q14 =  16'sd1598;
                    4: idct_matrix_q14 = -16'sd5793; 5: idct_matrix_q14 =  16'sd8035;
                    6: idct_matrix_q14 = -16'sd7568; 7: idct_matrix_q14 =  16'sd4551;
                endcase
                3'd7: case (u)
                    0: idct_matrix_q14 =  16'sd5793; 1: idct_matrix_q14 = -16'sd8035;
                    2: idct_matrix_q14 =  16'sd7568; 3: idct_matrix_q14 = -16'sd6811;
                    4: idct_matrix_q14 =  16'sd5793; 5: idct_matrix_q14 = -16'sd4551;
                    6: idct_matrix_q14 =  16'sd3135; 7: idct_matrix_q14 = -16'sd1598;
                endcase
                default: idct_matrix_q14 = 16'sd0;
            endcase
        end
    endfunction

    always_comb begin
        coef_ready_o = (state == ST_COLLECT);

        sample_valid_o = (state == ST_OUTPUT);
        sample_index_o = sample_output_index;
        sample_data_o = $signed(sample_buffer[sample_output_index*24 +: 24]);
        sample_component_index_o = block_component;
        sample_block_start_o = sample_valid_o && (sample_output_index == 6'd0);
        sample_block_last_o = sample_valid_o && (sample_output_index == 6'd63);
        error_o = (state == ST_ERROR);

        horizontal_input_coefficient =
            $signed(coefficient_buffer[
                ({horizontal_output_index[5:3], horizontal_inner_index} * 24) +: 24
            ]);
        horizontal_matrix_value = idct_matrix_q14(
            horizontal_output_index[2:0], horizontal_inner_index
        );
        horizontal_product =
            $signed({{16{horizontal_input_coefficient[23]}}, horizontal_input_coefficient}) *
            $signed({{24{horizontal_matrix_value[15]}}, horizontal_matrix_value});
        horizontal_sum = horizontal_accumulator +
                         {{8{horizontal_product[39]}}, horizontal_product};

        vertical_input_value = $signed(horizontal_buffer[
            ({vertical_inner_index, vertical_output_index[2:0]} * 48) +: 48
        ]);
        vertical_matrix_value = idct_matrix_q14(
            vertical_output_index[5:3], vertical_inner_index
        );
        vertical_product =
            $signed({{16{vertical_input_value[47]}}, vertical_input_value}) *
            $signed({{48{vertical_matrix_value[15]}}, vertical_matrix_value});
        vertical_sum = vertical_accumulator + vertical_product;
        if (vertical_sum >= 0)
            rounded_vertical_sum = vertical_sum + 64'sd134217728;
        else
            rounded_vertical_sum = vertical_sum - 64'sd134217728;
    end

    // State transitions and all next-value logic are combinational.
    always_comb begin
        state_next = state;
        coefficient_buffer_next = coefficient_buffer;
        horizontal_buffer_next = horizontal_buffer;
        sample_buffer_next = sample_buffer;
        input_index_next = input_index;
        block_component_next = block_component;
        horizontal_output_index_next = horizontal_output_index;
        horizontal_inner_index_next = horizontal_inner_index;
        vertical_output_index_next = vertical_output_index;
        vertical_inner_index_next = vertical_inner_index;
        sample_output_index_next = sample_output_index;
        horizontal_accumulator_next = horizontal_accumulator;
        vertical_accumulator_next = vertical_accumulator;

        case (state)
            ST_COLLECT: begin
                if (coef_valid_i && coef_ready_o) begin
                    if ((coef_index_i != input_index) ||
                        (component_index_i > 2'd2) ||
                        ((input_index == 6'd0) && !coef_block_start_i) ||
                        ((input_index != 6'd0) && coef_block_start_i) ||
                        (coef_block_last_i != (input_index == 6'd63)) ||
                        ((input_index != 6'd0) &&
                         (component_index_i != block_component))) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        coefficient_buffer_next[input_index*24 +: 24] = coef_data_i;
                        if (input_index == 6'd0)
                            block_component_next = component_index_i;

                        if (input_index == 6'd63) begin
                            input_index_next = 6'd0;
                            horizontal_output_index_next = 6'd0;
                            horizontal_inner_index_next = 3'd0;
                            horizontal_accumulator_next = 48'sd0;
                            state_next = ST_HORIZONTAL_MAC;
                        end
                        else begin
                            input_index_next = input_index + 6'd1;
                        end
                    end
                end
            end

            ST_HORIZONTAL_MAC: begin
                if (horizontal_inner_index == 3'd7) begin
                    horizontal_buffer_next[horizontal_output_index*48 +: 48] = horizontal_sum;
                    horizontal_accumulator_next = 48'sd0;
                    horizontal_inner_index_next = 3'd0;

                    if (horizontal_output_index == 6'd63) begin
                        vertical_output_index_next = 6'd0;
                        vertical_inner_index_next = 3'd0;
                        vertical_accumulator_next = 64'sd0;
                        state_next = ST_VERTICAL_MAC;
                    end
                    else begin
                        horizontal_output_index_next = horizontal_output_index + 6'd1;
                    end
                end
                else begin
                    horizontal_inner_index_next = horizontal_inner_index + 3'd1;
                    horizontal_accumulator_next = horizontal_sum;
                end
            end

            ST_VERTICAL_MAC: begin
                if (vertical_inner_index == 3'd7) begin
                    sample_buffer_next[vertical_output_index*24 +: 24] =
                        rounded_vertical_sum >>> 28;
                    vertical_accumulator_next = 64'sd0;
                    vertical_inner_index_next = 3'd0;

                    if (vertical_output_index == 6'd63) begin
                        sample_output_index_next = 6'd0;
                        state_next = ST_OUTPUT;
                    end
                    else begin
                        vertical_output_index_next = vertical_output_index + 6'd1;
                    end
                end
                else begin
                    vertical_inner_index_next = vertical_inner_index + 3'd1;
                    vertical_accumulator_next = vertical_sum;
                end
            end

            ST_OUTPUT: begin
                if (sample_valid_o && sample_ready_i) begin
                    if (sample_output_index == 6'd63) begin
                        sample_output_index_next = 6'd0;
                        input_index_next = 6'd0;
                        state_next = ST_COLLECT;
                    end
                    else begin
                        sample_output_index_next = sample_output_index + 6'd1;
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
            state <= ST_COLLECT;
            coefficient_buffer <= '0;
            horizontal_buffer <= '0;
            sample_buffer <= '0;
            input_index <= 6'd0;
            block_component <= 2'd0;
            horizontal_output_index <= 6'd0;
            horizontal_inner_index <= 3'd0;
            vertical_output_index <= 6'd0;
            vertical_inner_index <= 3'd0;
            sample_output_index <= 6'd0;
            horizontal_accumulator <= 48'sd0;
            vertical_accumulator <= 64'sd0;
        end
        else begin
            state <= state_next;
            coefficient_buffer <= coefficient_buffer_next;
            horizontal_buffer <= horizontal_buffer_next;
            sample_buffer <= sample_buffer_next;
            input_index <= input_index_next;
            block_component <= block_component_next;
            horizontal_output_index <= horizontal_output_index_next;
            horizontal_inner_index <= horizontal_inner_index_next;
            vertical_output_index <= vertical_output_index_next;
            vertical_inner_index <= vertical_inner_index_next;
            sample_output_index <= sample_output_index_next;
            horizontal_accumulator <= horizontal_accumulator_next;
            vertical_accumulator <= vertical_accumulator_next;
        end
    end

endmodule

