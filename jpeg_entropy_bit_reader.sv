`timescale 1ns / 1ps
// JPEG entropy byte unstuffing and MSB-first bit reservoir.
// Feed only bytes after the SOS payload. The parser must obey byte_ready_o.
// MSB-first bit reservoir for already-unstuffed entropy bytes.
// jpeg_bitstream_reader owns FF 00 unstuffing and marker detection; it must
// present each entropy byte once and obey byte_ready_o.
module jpeg_entropy_bit_reader (
    input  logic       clk,
    input  logic       rst,
    input  logic       scan_start_i,

    input  logic [7:0] byte_data_i,
    input  logic       byte_valid_i,
    output logic       byte_ready_o,

    // Consume decoded Huffman-code bits or amplitude bits.
    input  logic [4:0] consume_count_i,
    input  logic       consume_valid_i,
    output logic       consume_ready_o,

    // Next bits are left-aligned: the next stream bit is lookahead_o[15].
    output logic [15:0] lookahead_o,
    output logic [6:0]  bits_available_o,

    // Marker handling belongs to jpeg_bitstream_reader; retained for
    // compatibility with the earlier module interface and tied inactive.
    output logic       marker_valid_o,
    output logic [7:0] marker_code_o
);

    // Valid bits occupy the low bit_count bits. The earliest bit is at
    // bit_buffer[bit_count-1]; later bytes are appended at the least-significant end.
    logic [63:0] bit_buffer, bit_buffer_next;
    logic [6:0]  bit_count, bit_count_next;

    always_comb begin
        bit_buffer_next = bit_buffer;
        bit_count_next = bit_count;

        // Leave room for one complete byte; the reservoir can hold 64 bits.
        byte_ready_o = (bit_count <= 7'd56) && !scan_start_i && !rst;
        consume_ready_o = (consume_count_i != 5'd0) &&
                          ({2'b00, consume_count_i} <= bit_count) &&
                          !scan_start_i && !rst;

        marker_valid_o = 1'b0;
        marker_code_o = 8'd0;

        // Remove requested bits first, then append a simultaneously accepted byte.
        if (consume_valid_i && consume_ready_o) begin
            bit_buffer_next = bit_buffer_next << consume_count_i;
            bit_count_next = bit_count_next - {2'b00, consume_count_i};
        end

        if (byte_valid_i && byte_ready_o) begin
            bit_buffer_next = (bit_buffer_next << 8) | {56'd0, byte_data_i};
            bit_count_next = bit_count_next + 7'd8;
        end

        // Expose the current registered queue, independent of this cycle's requests.
        if (bit_count >= 7'd16)
            lookahead_o = bit_buffer >> (bit_count - 7'd16);
        else
            lookahead_o = bit_buffer << (7'd16 - bit_count);

        bits_available_o = bit_count;
    end

    always_ff @(posedge clk) begin
        if (rst || scan_start_i) begin
            bit_buffer <= 64'd0;
            bit_count <= 7'd0;
        end
        else begin
            bit_buffer <= bit_buffer_next;
            bit_count <= bit_count_next;
        end
    end

endmodule

