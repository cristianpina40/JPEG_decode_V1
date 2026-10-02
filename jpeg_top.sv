`timescale 1ns / 1ps
// Top-level restricted baseline JPEG decoder.
//
// Supported first-version format:
//   * baseline sequential, 8-bit, three-component 4:4:4
//   * SOF0 and SOS list components in the same Y, Cb, Cr order
//   * fixed Annex K example Huffman/quantization tables (IDs 0 and 1)
//   * no restart intervals
//
// jpeg_bitstream_reader removes FF 00 stuffing and forwards unstuffed entropy
// bytes. jpeg_entropy_bit_reader only buffers those bytes into an MSB-first
// bit reservoir. The framebuffer write interface is exposed at this module's
// outputs; the RAM/DDR controller itself is outside this module.

package jpeg_header_types_pkg;

    typedef struct packed {
        logic [7:0] component_id;
        logic [3:0] horizontal_sampling;
        logic [3:0] vertical_sampling;
        logic [7:0] quant_table_id;
    } sof0_component_t;

    typedef struct packed {
        logic valid;
        logic [7:0] precision;
        logic [15:0] height;
        logic [15:0] width;
        logic [7:0] component_count;
        sof0_component_t comp0;
        sof0_component_t comp1;
        sof0_component_t comp2;
    } sof0_data_t;

    typedef struct packed {
        logic [7:0] component_id;
        logic [3:0] dc_table_id;
        logic [3:0] ac_table_id;
    } sos_component_t;

    typedef struct packed {
        logic valid;
        logic [7:0] component_count;
        sos_component_t comp0;
        sos_component_t comp1;
        sos_component_t comp2;
        logic [7:0] spectral_start;
        logic [7:0] spectral_end;
        logic [7:0] successive_approximation;
    } sos_data_t;

endpackage


module jpeg_top #(
    parameter logic [7:0] SOI   = 8'hD8,
    parameter logic [7:0] EOI   = 8'hD9,
    parameter logic [7:0] SOF0  = 8'hC0,
    parameter logic [7:0] SOF2  = 8'hC2,
    parameter logic [7:0] DQT   = 8'hDB,
    parameter logic [7:0] DHT   = 8'hC4,
    parameter logic [7:0] SOS   = 8'hDA,
    parameter logic [7:0] DRI   = 8'hDD,
    parameter logic [7:0] COM   = 8'hFE,
    parameter logic [7:0] APP0  = 8'hE0,
    parameter logic [7:0] APP15 = 8'hEF,
    parameter logic [7:0] RST0  = 8'hD0,
    parameter logic [7:0] RST7  = 8'hD7
) (
    input  logic         clk,
    input  logic         aresetn,
    input  logic         start,

    // Input JPEG byte stream.
    input  logic [7:0]   byte_data,
    input  logic         byte_valid,
    output logic         byte_ready,

    // Framebuffer write port.
    output logic         pixel_valid_o,
    input  logic         pixel_ready_i,
    output logic [31:0]  pixel_address_o,
    output logic [23:0]  pixel_rgb_o,

    output logic         image_start_o,
    output logic         image_end_o,
    output logic         scan_done_o,
    output logic         image_done_o,
    output logic         error_o
);

    import jpeg_header_types_pkg::*;

    logic rst;
    logic header_rst;

    logic [7:0] cfg_marker;
    logic [15:0] cfg_index;
    logic [7:0] cfg_data;
    logic cfg_valid;
    logic cfg_ready;

    logic [7:0] entropy_data;
    logic entropy_valid;
    logic entropy_ready;
    logic parser_error;

    sof0_data_t sof0_data;
    sos_data_t sos_data;
    logic cfg_datapath_ready;

    logic headers_available;
    logic headers_supported;
    logic header_error;
    logic restart_unsupported;
    logic scan_started;
    logic scan_start_pulse;
    logic [11:0] q_table_ids;
    logic [11:0] dc_table_ids;
    logic [11:0] ac_table_ids;
    logic [15:0] frame_width;
    logic [15:0] frame_height;

    logic [15:0] bit_lookahead;
    logic [6:0] bits_available;
    logic [4:0] consume_count;
    logic consume_valid;
    logic consume_ready;

    logic coef_valid;
    logic coef_ready;
    logic [5:0] coef_index;
    logic signed [15:0] coef_data;
    logic [1:0] coef_component_index;
    logic entropy_error;

    logic idct_coef_valid;
    logic idct_coef_ready;
    logic [5:0] idct_coef_index;
    logic signed [23:0] idct_coef_data;
    logic [1:0] idct_coef_component_index;
    logic idct_coef_block_start;
    logic idct_coef_block_last;
    logic dequant_error;

    logic idct_sample_valid;
    logic idct_sample_ready;
    logic [5:0] idct_sample_index;
    logic signed [23:0] idct_sample_data;
    logic [1:0] idct_sample_component_index;
    logic idct_sample_block_start;
    logic idct_sample_block_last;
    logic idct_error;

    logic pixel8_valid;
    logic pixel8_ready;
    logic [5:0] pixel8_index;
    logic [7:0] pixel8_data;
    logic [1:0] pixel8_component_index;
    logic pixel8_block_start;
    logic pixel8_block_last;

    logic framebuffer_error;

    assign rst = ~aresetn;
    assign header_rst = rst | start;
    assign cfg_ready = cfg_datapath_ready;
    assign frame_width = sof0_data.width;
    assign frame_height = sof0_data.height;

    // Require the frame and scan component order to match. That makes scan
    // component indices 0/1/2 correspond to Y/Cb/Cr throughout the datapath.
    always_comb begin
        headers_available = sof0_data.valid && sos_data.valid;

        q_table_ids = {
            sof0_data.comp0.quant_table_id[3:0],
            sof0_data.comp1.quant_table_id[3:0],
            sof0_data.comp2.quant_table_id[3:0]
        };
        dc_table_ids = {
            sos_data.comp0.dc_table_id,
            sos_data.comp1.dc_table_id,
            sos_data.comp2.dc_table_id
        };
        ac_table_ids = {
            sos_data.comp0.ac_table_id,
            sos_data.comp1.ac_table_id,
            sos_data.comp2.ac_table_id
        };

        headers_supported =
            (sof0_data.precision == 8'd8) &&
            (sof0_data.width != 16'd0) &&
            (sof0_data.height != 16'd0) &&
            (sof0_data.component_count == 8'd3) &&
            (sos_data.component_count == 8'd3) &&
            (sof0_data.comp0.horizontal_sampling == 4'd1) &&
            (sof0_data.comp0.vertical_sampling == 4'd1) &&
            (sof0_data.comp1.horizontal_sampling == 4'd1) &&
            (sof0_data.comp1.vertical_sampling == 4'd1) &&
            (sof0_data.comp2.horizontal_sampling == 4'd1) &&
            (sof0_data.comp2.vertical_sampling == 4'd1) &&
            (sos_data.comp0.component_id == sof0_data.comp0.component_id) &&
            (sos_data.comp1.component_id == sof0_data.comp1.component_id) &&
            (sos_data.comp2.component_id == sof0_data.comp2.component_id) &&
            (sof0_data.comp0.quant_table_id <= 8'd1) &&
            (sof0_data.comp1.quant_table_id <= 8'd1) &&
            (sof0_data.comp2.quant_table_id <= 8'd1) &&
            (sos_data.comp0.dc_table_id <= 4'd1) &&
            (sos_data.comp1.dc_table_id <= 4'd1) &&
            (sos_data.comp2.dc_table_id <= 4'd1) &&
            (sos_data.comp0.ac_table_id <= 4'd1) &&
            (sos_data.comp1.ac_table_id <= 4'd1) &&
            (sos_data.comp2.ac_table_id <= 4'd1) &&
            (sos_data.spectral_start == 8'd0) &&
            (sos_data.spectral_end == 8'd63) &&
            (sos_data.successive_approximation == 8'd0);

        header_error = headers_available && !headers_supported;
        scan_start_pulse = headers_available && headers_supported &&
                           !scan_started && !start;
    end

    always_ff @(posedge clk) begin
        if (rst || start)
            scan_started <= 1'b0;
        else if (scan_start_pulse)
            scan_started <= 1'b1;
    end

    // This implementation has no restart-marker support. A nonzero DRI
    // payload means restart markers may occur in the entropy stream.
    always_ff @(posedge clk) begin
        if (rst || start)
            restart_unsupported <= 1'b0;
        else if (cfg_valid && cfg_ready && (cfg_marker == DRI) &&
                 (cfg_data != 8'd0))
            restart_unsupported <= 1'b1;
    end

    jpeg_bitstream_reader #(
        .SOI   (SOI),
        .EOI   (EOI),
        .SOF0  (SOF0),
        .SOF2  (SOF2),
        .DQT   (DQT),
        .DHT   (DHT),
        .SOS   (SOS),
        .DRI   (DRI),
        .COM   (COM),
        .APP0  (APP0),
        .APP15 (APP15),
        .RST0  (RST0),
        .RST7  (RST7)
    ) u_jpeg_bitstream_reader (
        .clk          (clk),
        .aresetn      (aresetn),
        .start        (start),
        .byte_data    (byte_data),
        .byte_valid   (byte_valid),
        .byte_ready   (byte_ready),
        .cfg_marker   (cfg_marker),
        .cfg_index    (cfg_index),
        .cfg_data     (cfg_data),
        .cfg_valid    (cfg_valid),
        .cfg_ready    (cfg_ready),
        .entropy_data (entropy_data),
        .entropy_valid(entropy_valid),
        .entropy_ready(entropy_ready),
        .image_start  (image_start_o),
        .image_end    (image_end_o),
        .error        (parser_error)
    );

    datapath_control u_datapath_control (
        .clk          (clk),
        .rst          (header_rst),
        .cfg_marker_i (cfg_marker),
        .cfg_index_i  (cfg_index),
        .cfg_data_i   (cfg_data),
        .cfg_valid_i  (cfg_valid),
        .cfg_ready_o  (cfg_datapath_ready),
        .sof0_data_o  (sof0_data),
        .sos_data_o   (sos_data)
    );

    jpeg_entropy_bit_reader u_entropy_bit_reader (
        .clk              (clk),
        .rst              (rst),
        .scan_start_i     (scan_start_pulse),
        .byte_data_i      (entropy_data),
        .byte_valid_i     (entropy_valid),
        .byte_ready_o     (entropy_ready),
        .consume_count_i  (consume_count),
        .consume_valid_i  (consume_valid),
        .consume_ready_o  (consume_ready),
        .lookahead_o      (bit_lookahead),
        .bits_available_o (bits_available),
        .marker_valid_o   (),
        .marker_code_o    ()
    );

    jpeg_entropy_controller u_entropy_controller (
        .clk               (clk),
        .rst               (rst),
        .start_scan_i      (scan_start_pulse),
        .image_width_i     (frame_width),
        .image_height_i    (frame_height),
        .dc_table_ids_i    (dc_table_ids),
        .ac_table_ids_i    (ac_table_ids),
        .lookahead_i       (bit_lookahead),
        .bits_available_i  (bits_available),
        .consume_valid_o   (consume_valid),
        .consume_count_o   (consume_count),
        .consume_ready_i   (consume_ready),
        .coef_valid_o      (coef_valid),
        .coef_ready_i      (coef_ready),
        .coef_index_o      (coef_index),
        .coef_data_o       (coef_data),
        .component_index_o (coef_component_index),
        .scan_done_o       (scan_done_o),
        .error_o           (entropy_error)
    );

    jpeg_inverse_zigzag_dequant u_inverse_zigzag_dequant (
        .clk                    (clk),
        .rst                    (rst),
        .coef_valid_i           (coef_valid),
        .coef_ready_o           (coef_ready),
        .coef_index_i           (coef_index),
        .coef_data_i            (coef_data),
        .component_index_i      (coef_component_index),
        .q_table_ids_i          (q_table_ids),
        .idct_coef_valid_o      (idct_coef_valid),
        .idct_coef_ready_i      (idct_coef_ready),
        .idct_coef_index_o      (idct_coef_index),
        .idct_coef_data_o       (idct_coef_data),
        .idct_component_index_o (idct_coef_component_index),
        .idct_block_start_o     (idct_coef_block_start),
        .idct_block_last_o      (idct_coef_block_last),
        .error_o                (dequant_error)
    );

    jpeg_idct_8x8 u_idct_8x8 (
        .clk                      (clk),
        .rst                      (rst),
        .coef_valid_i             (idct_coef_valid),
        .coef_ready_o             (idct_coef_ready),
        .coef_index_i             (idct_coef_index),
        .coef_data_i              (idct_coef_data),
        .component_index_i        (idct_coef_component_index),
        .coef_block_start_i       (idct_coef_block_start),
        .coef_block_last_i        (idct_coef_block_last),
        .sample_valid_o           (idct_sample_valid),
        .sample_ready_i           (idct_sample_ready),
        .sample_index_o           (idct_sample_index),
        .sample_data_o            (idct_sample_data),
        .sample_component_index_o(idct_sample_component_index),
        .sample_block_start_o     (idct_sample_block_start),
        .sample_block_last_o      (idct_sample_block_last),
        .error_o                  (idct_error)
    );

    jpeg_level_shift_clamp u_level_shift_clamp (
        .sample_valid_i       (idct_sample_valid),
        .sample_ready_o       (idct_sample_ready),
        .sample_index_i       (idct_sample_index),
        .sample_data_i        (idct_sample_data),
        .component_index_i    (idct_sample_component_index),
        .sample_block_start_i (idct_sample_block_start),
        .sample_block_last_i  (idct_sample_block_last),
        .pixel_valid_o        (pixel8_valid),
        .pixel_ready_i        (pixel8_ready),
        .pixel_index_o        (pixel8_index),
        .pixel_data_o         (pixel8_data),
        .component_index_o    (pixel8_component_index),
        .pixel_block_start_o  (pixel8_block_start),
        .pixel_block_last_o   (pixel8_block_last)
    );

    jpeg_ycbcr_to_rgb u_ycbcr_to_rgb_framebuffer (
        .clk                  (clk),
        .rst                  (rst),
        .start_frame_i        (scan_start_pulse),
        .image_width_i        (frame_width),
        .image_height_i       (frame_height),
        .sample_valid_i       (pixel8_valid),
        .sample_ready_o       (pixel8_ready),
        .sample_index_i       (pixel8_index),
        .sample_data_i        (pixel8_data),
        .component_index_i    (pixel8_component_index),
        .sample_block_start_i (pixel8_block_start),
        .sample_block_last_i  (pixel8_block_last),
        .pixel_valid_o        (pixel_valid_o),
        .pixel_ready_i        (pixel_ready_i),
        .pixel_address_o      (pixel_address_o),
        .pixel_rgb_o           (pixel_rgb_o),
        .frame_done_o          (image_done_o),
        .error_o               (framebuffer_error)
    );

    assign error_o = parser_error | header_error | restart_unsupported | entropy_error |
                     dequant_error | idct_error | framebuffer_error;

endmodule
