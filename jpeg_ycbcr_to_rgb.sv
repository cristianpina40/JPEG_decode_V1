`timescale 1ns / 1ps
// Baseline JPEG 4:4:4 color conversion and frame-buffer writer.
//
// The input stream is expected to contain one 8x8 Y block, then the matching
// 8x8 Cb block, then the matching 8x8 Cr block for each MCU. Component indices
// are assumed to be Y=0, Cb=1, Cr=2. This matches a restricted first version
// with 4:4:4 sampling and the component order normalized by the header logic.
//
// The module buffers the three planes for an MCU, converts corresponding
// samples using the standard JPEG YCbCr equations, clips RGB to 8 bits, and
// writes in-bounds pixels at row-major addresses. Edge samples outside the
// declared image dimensions are skipped.
module jpeg_ycbcr_to_rgb (
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   start_frame_i,
    input  logic [15:0]            image_width_i,
    input  logic [15:0]            image_height_i,

    input  logic                   sample_valid_i,
    output logic                   sample_ready_o,
    input  logic [5:0]             sample_index_i,
    input  logic [7:0]             sample_data_i,
    input  logic [1:0]             component_index_i,
    input  logic                   sample_block_start_i,
    input  logic                   sample_block_last_i,

    output logic                   pixel_valid_o,
    input  logic                   pixel_ready_i,
    output logic [31:0]            pixel_address_o,
    output logic [23:0]            pixel_rgb_o,
    output logic                   frame_done_o,
    output logic                   error_o
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_COLLECT_Y,
        ST_COLLECT_CB,
        ST_COLLECT_CR,
        ST_WRITE_PIXELS,
        ST_DONE,
        ST_ERROR
    } state_t;

    state_t state, state_next;

    logic [511:0] y_block, y_block_next;
    logic [511:0] cb_block, cb_block_next;
    logic [511:0] cr_block, cr_block_next;

    logic [5:0] input_index, input_index_next;
    logic [5:0] pixel_index, pixel_index_next;
    logic [31:0] mcu_x, mcu_x_next;
    logic [31:0] mcu_y, mcu_y_next;
    logic [31:0] mcu_columns, mcu_columns_next;
    logic [31:0] mcu_rows, mcu_rows_next;

    logic [31:0] mcu_columns_calc;
    logic [31:0] mcu_rows_calc;
    logic [7:0] y_sample;
    logic [7:0] cb_sample;
    logic [7:0] cr_sample;
    logic signed [8:0] cb_centered;
    logic signed [8:0] cr_centered;
    logic signed [31:0] y_q16;
    logic signed [31:0] red_accum;
    logic signed [31:0] green_accum;
    logic signed [31:0] blue_accum;
    logic signed [31:0] red_value;
    logic signed [31:0] green_value;
    logic signed [31:0] blue_value;
    logic [31:0] pixel_x;
    logic [31:0] pixel_y;
    logic pixel_in_bounds;
    logic input_block_good;

    function automatic logic [7:0] clamp_u8(input logic signed [31:0] value);
        begin
            if (value < 32'sd0)
                clamp_u8 = 8'd0;
            else if (value > 32'sd255)
                clamp_u8 = 8'd255;
            else
                clamp_u8 = value[7:0];
        end
    endfunction

    always_comb begin
        mcu_columns_calc = ({16'd0, image_width_i} + 32'd7) >> 3;
        mcu_rows_calc = ({16'd0, image_height_i} + 32'd7) >> 3;

        sample_ready_o = (state == ST_COLLECT_Y) ||
                         (state == ST_COLLECT_CB) ||
                         (state == ST_COLLECT_CR);
        frame_done_o = (state == ST_DONE);
        error_o = (state == ST_ERROR);

        pixel_x = (mcu_x << 3) + {29'd0, pixel_index[2:0]};
        pixel_y = (mcu_y << 3) + {29'd0, pixel_index[5:3]};
        pixel_in_bounds = (pixel_x < {16'd0, image_width_i}) &&
                          (pixel_y < {16'd0, image_height_i});

        pixel_valid_o = (state == ST_WRITE_PIXELS) && pixel_in_bounds;
        pixel_address_o = (pixel_y * {16'd0, image_width_i}) + pixel_x;

        y_sample = y_block[pixel_index*8 +: 8];
        cb_sample = cb_block[pixel_index*8 +: 8];
        cr_sample = cr_block[pixel_index*8 +: 8];
        cb_centered = $signed({1'b0, cb_sample}) - 9'sd128;
        cr_centered = $signed({1'b0, cr_sample}) - 9'sd128;
        y_q16 = $signed({1'b0, y_sample}) <<< 16;

        // Q16 coefficients: 1.402, 0.344136, 0.714136, and 1.772.
        red_accum = y_q16 + (cr_centered * 32'sd91881) + 32'sd32768;
        green_accum = y_q16 - (cb_centered * 32'sd22554) -
                      (cr_centered * 32'sd46802) + 32'sd32768;
        blue_accum = y_q16 + (cb_centered * 32'sd116130) + 32'sd32768;

        red_value = red_accum >>> 16;
        green_value = green_accum >>> 16;
        blue_value = blue_accum >>> 16;
        pixel_rgb_o = {clamp_u8(red_value),
                       clamp_u8(green_value),
                       clamp_u8(blue_value)};

        case (state)
            ST_COLLECT_Y:  input_block_good = (component_index_i == 2'd0);
            ST_COLLECT_CB: input_block_good = (component_index_i == 2'd1);
            ST_COLLECT_CR: input_block_good = (component_index_i == 2'd2);
            default:       input_block_good = 1'b0;
        endcase
        input_block_good = input_block_good &&
                           (sample_index_i == input_index) &&
                           ((input_index == 6'd0) == sample_block_start_i) &&
                           ((input_index == 6'd63) == sample_block_last_i);
    end

    // State transitions and next-value logic are combinational.
    always_comb begin
        state_next = state;
        y_block_next = y_block;
        cb_block_next = cb_block;
        cr_block_next = cr_block;
        input_index_next = input_index;
        pixel_index_next = pixel_index;
        mcu_x_next = mcu_x;
        mcu_y_next = mcu_y;
        mcu_columns_next = mcu_columns;
        mcu_rows_next = mcu_rows;

        case (state)
            ST_IDLE: begin
                if (start_frame_i) begin
                    if ((image_width_i == 16'd0) || (image_height_i == 16'd0)) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        mcu_columns_next = mcu_columns_calc;
                        mcu_rows_next = mcu_rows_calc;
                        mcu_x_next = 32'd0;
                        mcu_y_next = 32'd0;
                        input_index_next = 6'd0;
                        state_next = ST_COLLECT_Y;
                    end
                end
            end

            ST_COLLECT_Y: begin
                if (sample_valid_i && sample_ready_o) begin
                    if (!input_block_good) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        y_block_next[input_index*8 +: 8] = sample_data_i;
                        if (input_index == 6'd63) begin
                            input_index_next = 6'd0;
                            state_next = ST_COLLECT_CB;
                        end
                        else begin
                            input_index_next = input_index + 6'd1;
                        end
                    end
                end
            end

            ST_COLLECT_CB: begin
                if (sample_valid_i && sample_ready_o) begin
                    if (!input_block_good) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        cb_block_next[input_index*8 +: 8] = sample_data_i;
                        if (input_index == 6'd63) begin
                            input_index_next = 6'd0;
                            state_next = ST_COLLECT_CR;
                        end
                        else begin
                            input_index_next = input_index + 6'd1;
                        end
                    end
                end
            end

            ST_COLLECT_CR: begin
                if (sample_valid_i && sample_ready_o) begin
                    if (!input_block_good) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        cr_block_next[input_index*8 +: 8] = sample_data_i;
                        if (input_index == 6'd63) begin
                            input_index_next = 6'd0;
                            pixel_index_next = 6'd0;
                            state_next = ST_WRITE_PIXELS;
                        end
                        else begin
                            input_index_next = input_index + 6'd1;
                        end
                    end
                end
            end

            ST_WRITE_PIXELS: begin
                // Skip padded samples at the right/bottom image boundaries.
                if (!pixel_in_bounds || (pixel_valid_o && pixel_ready_i)) begin
                    if (pixel_index == 6'd63) begin
                        pixel_index_next = 6'd0;
                        if (mcu_x == (mcu_columns - 32'd1)) begin
                            mcu_x_next = 32'd0;
                            if (mcu_y == (mcu_rows - 32'd1)) begin
                                state_next = ST_DONE;
                            end
                            else begin
                                mcu_y_next = mcu_y + 32'd1;
                                state_next = ST_COLLECT_Y;
                            end
                        end
                        else begin
                            mcu_x_next = mcu_x + 32'd1;
                            state_next = ST_COLLECT_Y;
                        end
                    end
                    else begin
                        pixel_index_next = pixel_index + 6'd1;
                    end
                end
            end

            ST_DONE: begin
                if (start_frame_i) begin
                    if ((image_width_i == 16'd0) || (image_height_i == 16'd0)) begin
                        state_next = ST_ERROR;
                    end
                    else begin
                        mcu_columns_next = mcu_columns_calc;
                        mcu_rows_next = mcu_rows_calc;
                        mcu_x_next = 32'd0;
                        mcu_y_next = 32'd0;
                        input_index_next = 6'd0;
                        state_next = ST_COLLECT_Y;
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
            y_block <= '0;
            cb_block <= '0;
            cr_block <= '0;
            input_index <= 6'd0;
            pixel_index <= 6'd0;
            mcu_x <= 32'd0;
            mcu_y <= 32'd0;
            mcu_columns <= 32'd0;
            mcu_rows <= 32'd0;
        end
        else begin
            state <= state_next;
            y_block <= y_block_next;
            cb_block <= cb_block_next;
            cr_block <= cr_block_next;
            input_index <= input_index_next;
            pixel_index <= pixel_index_next;
            mcu_x <= mcu_x_next;
            mcu_y <= mcu_y_next;
            mcu_columns <= mcu_columns_next;
            mcu_rows <= mcu_rows_next;
        end
    end

endmodule
