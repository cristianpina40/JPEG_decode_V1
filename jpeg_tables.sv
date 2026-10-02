`timescale 1ns / 1ps
// Fixed baseline JPEG reference tables (SystemVerilog).
// Huffman values are the Annex K example tables. Quantization values are Annex K.1 examples.
// A decoder using these ROMs must be fed JPEGs whose DHT/DQT values match these tables.
// Quantization ROM address is JPEG zig-zag coefficient index 0..63.

module jpeg_quant_table_0_luma (input logic [5:0] index_i, output logic [7:0] value_o);
    always_comb begin
        value_o = 8'd0;
        case (index_i)
            6'd0: value_o = 8'd16; // natural-order coefficient 0
            6'd1: value_o = 8'd11; // natural-order coefficient 1
            6'd2: value_o = 8'd12; // natural-order coefficient 8
            6'd3: value_o = 8'd14; // natural-order coefficient 16
            6'd4: value_o = 8'd12; // natural-order coefficient 9
            6'd5: value_o = 8'd10; // natural-order coefficient 2
            6'd 6: value_o = 8'd16; // natural-order coefficient 3
            6'd7: value_o = 8'd14; // natural-order coefficient 10
            6'd8: value_o = 8'd13; // natural-order coefficient 17
            6'd9: value_o = 8'd14; // natural-order coefficient 24
            6'd10: value_o = 8'd18; // natural-order coefficient 32
            6'd11: value_o = 8'd17; // natural-order coefficient 25
            6'd12: value_o = 8'd16; // natural-order coefficient 18
            6'd13: value_o = 8'd19; // natural-order coefficient 11
            6'd14: value_o = 8'd24; // natural-order coefficient 4
            6'd15: value_o = 8'd40; // natural-order coefficient 5
            6'd16: value_o = 8'd26; // natural-order coefficient 12
            6'd17: value_o = 8'd24; // natural-order coefficient 19
            6'd18: value_o = 8'd22; // natural-order coefficient 26
            6'd19: value_o = 8'd22; // natural-order coefficient 33
            6'd20: value_o = 8'd24; // natural-order coefficient 40
            6'd21: value_o = 8'd49; // natural-order coefficient 48
            6'd22: value_o = 8'd35; // natural-order coefficient 41
            6'd23: value_o = 8'd37; // natural-order coefficient 34
            6'd24: value_o = 8'd29; // natural-order coefficient 27
            6'd25: value_o = 8'd40; // natural-order coefficient 20
            6'd26: value_o = 8'd58; // natural-order coefficient 13
            6'd27: value_o = 8'd51; // natural-order coefficient 6
            6'd28: value_o = 8'd61; // natural-order coefficient 7
            6'd29: value_o = 8'd60; // natural-order coefficient 14
            6'd30: value_o = 8'd57; // natural-order coefficient 21
            6'd31: value_o = 8'd51; // natural-order coefficient 28
            6'd32: value_o = 8'd56; // natural-order coefficient 35
            6'd33: value_o = 8'd55; // natural-order coefficient 42
            6'd34: value_o = 8'd64; // natural-order coefficient 49
            6'd35: value_o = 8'd72; // natural-order coefficient 56
            6'd36: value_o = 8'd92; // natural-order coefficient 57
            6'd37: value_o = 8'd78; // natural-order coefficient 50
            6'd38: value_o = 8'd64; // natural-order coefficient 43
            6'd39: value_o = 8'd68; // natural-order coefficient 36
            6'd40: value_o = 8'd87; // natural-order coefficient 29
            6'd41: value_o = 8'd69; // natural-order coefficient 22
            6'd42: value_o = 8'd55; // natural-order coefficient 15
            6'd43: value_o = 8'd56; // natural-order coefficient 23
            6'd44: value_o = 8'd80; // natural-order coefficient 30
            6'd45: value_o = 8'd109; // natural-order coefficient 37
            6'd46: value_o = 8'd81; // natural-order coefficient 44
            6'd47: value_o = 8'd87; // natural-order coefficient 51
            6'd48: value_o = 8'd95; // natural-order coefficient 58
            6'd49: value_o = 8'd98; // natural-order coefficient 59
            6'd50: value_o = 8'd103; // natural-order coefficient 52
            6'd51: value_o = 8'd104; // natural-order coefficient 45
            6'd52: value_o = 8'd103; // natural-order coefficient 38
            6'd53: value_o = 8'd62; // natural-order coefficient 31
            6'd54: value_o = 8'd77; // natural-order coefficient 39
            6'd55: value_o = 8'd113; // natural-order coefficient 46
            6'd56: value_o = 8'd121; // natural-order coefficient 53
            6'd57: value_o = 8'd112; // natural-order coefficient 60
            6'd58: value_o = 8'd100; // natural-order coefficient 61
            6'd59: value_o = 8'd120; // natural-order coefficient 54
            6'd60: value_o = 8'd92; // natural-order coefficient 47
            6'd61: value_o = 8'd101; // natural-order coefficient 55
            6'd62: value_o = 8'd103; // natural-order coefficient 62
            6'd63: value_o = 8'd99; // natural-order coefficient 63
            default: value_o = 8'd0;
        endcase
    end
endmodule

module jpeg_quant_table_1_chroma (input logic [5:0] index_i, output logic [7:0] value_o);
    always_comb begin
        value_o = 8'd0;
        case (index_i)
            6'd 0: value_o = 8'd17; // natural-order coefficient 0
            6'd 1: value_o = 8'd18; // natural-order coefficient 1
            6'd 2: value_o = 8'd18; // natural-order coefficient 8
            6'd 3: value_o = 8'd24; // natural-order coefficient 16
            6'd 4: value_o = 8'd21; // natural-order coefficient 9
            6'd 5: value_o = 8'd24; // natural-order coefficient 2
            6'd 6: value_o = 8'd47; // natural-order coefficient 3
            6'd 7: value_o = 8'd26; // natural-order coefficient 10
            6'd 8: value_o = 8'd26; // natural-order coefficient 17
            6'd 9: value_o = 8'd47; // natural-order coefficient 24
            6'd10: value_o = 8'd99; // natural-order coefficient 32
            6'd11: value_o = 8'd66; // natural-order coefficient 25
            6'd12: value_o = 8'd56; // natural-order coefficient 18
            6'd13: value_o = 8'd66; // natural-order coefficient 11
            6'd14: value_o = 8'd99; // natural-order coefficient 4
            6'd15: value_o = 8'd99; // natural-order coefficient 5
            6'd16: value_o = 8'd99; // natural-order coefficient 12
            6'd17: value_o = 8'd99; // natural-order coefficient 19
            6'd18: value_o = 8'd99; // natural-order coefficient 26
            6'd19: value_o = 8'd99; // natural-order coefficient 33
            6'd20: value_o = 8'd99; // natural-order coefficient 40
            6'd21: value_o = 8'd99; // natural-order coefficient 48
            6'd22: value_o = 8'd99; // natural-order coefficient 41
            6'd23: value_o = 8'd99; // natural-order coefficient 34
            6'd24: value_o = 8'd99; // natural-order coefficient 27
            6'd25: value_o = 8'd99; // natural-order coefficient 20
            6'd26: value_o = 8'd99; // natural-order coefficient 13
            6'd27: value_o = 8'd99; // natural-order coefficient 6
            6'd28: value_o = 8'd99; // natural-order coefficient 7
            6'd29: value_o = 8'd99; // natural-order coefficient 14
            6'd30: value_o = 8'd99; // natural-order coefficient 21
            6'd31: value_o = 8'd99; // natural-order coefficient 28
            6'd32: value_o = 8'd99; // natural-order coefficient 35
            6'd33: value_o = 8'd99; // natural-order coefficient 42
            6'd34: value_o = 8'd99; // natural-order coefficient 49
            6'd35: value_o = 8'd99; // natural-order coefficient 56
            6'd36: value_o = 8'd99; // natural-order coefficient 57
            6'd37: value_o = 8'd99; // natural-order coefficient 50
            6'd38: value_o = 8'd99; // natural-order coefficient 43
            6'd39: value_o = 8'd99; // natural-order coefficient 36
            6'd40: value_o = 8'd99; // natural-order coefficient 29
            6'd41: value_o = 8'd99; // natural-order coefficient 22
            6'd42: value_o = 8'd99; // natural-order coefficient 15
            6'd43: value_o = 8'd99; // natural-order coefficient 23
            6'd44: value_o = 8'd99; // natural-order coefficient 30
            6'd45: value_o = 8'd99; // natural-order coefficient 37
            6'd46: value_o = 8'd99; // natural-order coefficient 44
            6'd47: value_o = 8'd99; // natural-order coefficient 51
            6'd48: value_o = 8'd99; // natural-order coefficient 58
            6'd49: value_o = 8'd99; // natural-order coefficient 59
            6'd50: value_o = 8'd99; // natural-order coefficient 52
            6'd51: value_o = 8'd99; // natural-order coefficient 45
            6'd52: value_o = 8'd99; // natural-order coefficient 38
            6'd53: value_o = 8'd99; // natural-order coefficient 31
            6'd54: value_o = 8'd99; // natural-order coefficient 39
            6'd55: value_o = 8'd99; // natural-order coefficient 46
            6'd56: value_o = 8'd99; // natural-order coefficient 53
            6'd57: value_o = 8'd99; // natural-order coefficient 60
            6'd58: value_o = 8'd99; // natural-order coefficient 61
            6'd59: value_o = 8'd99; // natural-order coefficient 54
            6'd60: value_o = 8'd99; // natural-order coefficient 47
            6'd61: value_o = 8'd99; // natural-order coefficient 55
            6'd62: value_o = 8'd99; // natural-order coefficient 62
            6'd63: value_o = 8'd99; // natural-order coefficient 63
            default: value_o = 8'd0;
        endcase
    end
endmodule

// Canonical Huffman prefix lookup shared by the four fixed-table wrappers.
// COUNT_BYTES[127:120] is the number of length-1 codes, then length 2, ..., 16.
// SYMBOL_BYTES packs the decoded symbols in canonical code order, first symbol at the MSB.
module jpeg_huffman_fixed_lookup #(
    parameter int SYMBOL_COUNT = 12,
    parameter logic [127:0] COUNT_BYTES = '0,
    parameter logic [8*SYMBOL_COUNT-1:0] SYMBOL_BYTES = '0
) (
    input  logic [15:0] code_prefix_i, // Next 16 bits, earliest bit at bit 15
    output logic        symbol_valid_o,
    output logic [4:0]  code_length_o,
    output logic [7:0]  symbol_o
);
    integer length;
    integer symbol_base;
    logic [16:0] first_code;
    logic [16:0] code_count;
    logic [16:0] prefix;
    logic [16:0] length_mask;
    logic [7:0]  count_at_length;
    integer matched_symbol_index;
    logic found;

    always_comb begin
        symbol_valid_o       = 1'b0;
        code_length_o        = 5'd0;
        symbol_o             = 8'd0;
        found                = 1'b0;
        first_code           = 17'd0;
        code_count           = 17'd0;
        prefix               = 17'd0;
        length_mask          = 17'd0;
        count_at_length      = 8'd0;
        symbol_base          = 0;
        matched_symbol_index = 0;

        // At each length, valid canonical codes form one contiguous range.
        for (length = 1; length <= 16; length = length + 1) begin
            count_at_length = COUNT_BYTES[(16-length)*8 +: 8];
            length_mask     = (17'd1 << length) - 17'd1;
            prefix          = (code_prefix_i >> (16-length)) & length_mask;
            code_count      = {9'd0, count_at_length};

            if (!found && (count_at_length != 8'd0) &&
                (prefix >= first_code) && (prefix < (first_code + code_count))) begin
                matched_symbol_index = symbol_base + (prefix - first_code);
                symbol_valid_o = 1'b1;
                code_length_o  = length;
                symbol_o       = SYMBOL_BYTES[8*(SYMBOL_COUNT-1-matched_symbol_index) +: 8];
                found          = 1'b1;
            end

            // First code of the next length follows the canonical rule.
            first_code = (first_code + code_count) << 1;
            symbol_base = symbol_base + count_at_length;
        end
    end
endmodule

// Standard Annex K DC luminance table (JPEG table ID 0).
module jpeg_huffman_dc0_luma (
    input  logic [15:0] code_prefix_i,
    output logic        symbol_valid_o,
    output logic [4:0]  code_length_o,
    output logic [7:0]  symbol_o
);
    localparam int SYMBOL_COUNT = 12;
    localparam logic [127:0] CODE_COUNTS = 128'h00010501010101010100000000000000;
    localparam logic [8*SYMBOL_COUNT-1:0] SYMBOL_BYTES = {
        { 8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B }
    };

    jpeg_huffman_fixed_lookup #(
        .SYMBOL_COUNT (SYMBOL_COUNT),
        .COUNT_BYTES  (CODE_COUNTS),
        .SYMBOL_BYTES (SYMBOL_BYTES)
    ) lookup (
        .code_prefix_i  (code_prefix_i),
        .symbol_valid_o (symbol_valid_o),
        .code_length_o  (code_length_o),
        .symbol_o       (symbol_o)
    );
endmodule

// Standard Annex K DC chrominance table (JPEG table ID 1).
module jpeg_huffman_dc1_chroma (
    input  logic [15:0] code_prefix_i,
    output logic        symbol_valid_o,
    output logic [4:0]  code_length_o,
    output logic [7:0]  symbol_o
);
    localparam int SYMBOL_COUNT = 12;
    localparam logic [127:0] CODE_COUNTS = 128'h00030101010101010101010000000000;
    localparam logic [8*SYMBOL_COUNT-1:0] SYMBOL_BYTES = {
        { 8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B }
    };

    jpeg_huffman_fixed_lookup #(
        .SYMBOL_COUNT (SYMBOL_COUNT),
        .COUNT_BYTES  (CODE_COUNTS),
        .SYMBOL_BYTES (SYMBOL_BYTES)
    ) lookup (
        .code_prefix_i  (code_prefix_i),
        .symbol_valid_o (symbol_valid_o),
        .code_length_o  (code_length_o),
        .symbol_o       (symbol_o)
    );
endmodule

// Standard Annex K AC luminance table (JPEG table ID 0).
module jpeg_huffman_ac0_luma (
    input  logic [15:0] code_prefix_i,
    output logic        symbol_valid_o,
    output logic [4:0]  code_length_o,
    output logic [7:0]  symbol_o
);
    localparam int SYMBOL_COUNT = 162;
    localparam logic [127:0] CODE_COUNTS = 128'h0002010303020403050504040000017D;
    localparam logic [8*SYMBOL_COUNT-1:0] SYMBOL_BYTES = {
        { 8'h01, 8'h02, 8'h03, 8'h00, 8'h04, 8'h11, 8'h05, 8'h12, 8'h21, 8'h31, 8'h41, 8'h06 },
        { 8'h13, 8'h51, 8'h61, 8'h07, 8'h22, 8'h71, 8'h14, 8'h32, 8'h81, 8'h91, 8'hA1, 8'h08 },
        { 8'h23, 8'h42, 8'hB1, 8'hC1, 8'h15, 8'h52, 8'hD1, 8'hF0, 8'h24, 8'h33, 8'h62, 8'h72 },
        { 8'h82, 8'h09, 8'h0A, 8'h16, 8'h17, 8'h18, 8'h19, 8'h1A, 8'h25, 8'h26, 8'h27, 8'h28 },
        { 8'h29, 8'h2A, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39, 8'h3A, 8'h43, 8'h44, 8'h45 },
        { 8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57, 8'h58, 8'h59 },
        { 8'h5A, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h73, 8'h74, 8'h75 },
        { 8'h76, 8'h77, 8'h78, 8'h79, 8'h7A, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87, 8'h88, 8'h89 },
        { 8'h8A, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97, 8'h98, 8'h99, 8'h9A, 8'hA2, 8'hA3 },
        { 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6 },
        { 8'hB7, 8'hB8, 8'hB9, 8'hBA, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7, 8'hC8, 8'hC9 },
        { 8'hCA, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7, 8'hD8, 8'hD9, 8'hDA, 8'hE1, 8'hE2 },
        { 8'hE3, 8'hE4, 8'hE5, 8'hE6, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hF1, 8'hF2, 8'hF3, 8'hF4 },
        { 8'hF5, 8'hF6, 8'hF7, 8'hF8, 8'hF9, 8'hFA }
    };

    jpeg_huffman_fixed_lookup #(
        .SYMBOL_COUNT (SYMBOL_COUNT),
        .COUNT_BYTES  (CODE_COUNTS),
        .SYMBOL_BYTES (SYMBOL_BYTES)
    ) lookup (
        .code_prefix_i  (code_prefix_i),
        .symbol_valid_o (symbol_valid_o),
        .code_length_o  (code_length_o),
        .symbol_o       (symbol_o)
    );
endmodule

// Standard Annex K AC chrominance table (JPEG table ID 1).
module jpeg_huffman_ac1_chroma (
    input  logic [15:0] code_prefix_i,
    output logic        symbol_valid_o,
    output logic [4:0]  code_length_o,
    output logic [7:0]  symbol_o
);
    localparam int SYMBOL_COUNT = 162;
    localparam logic [127:0] CODE_COUNTS = 128'h00020102040403040705040400010277;
    localparam logic [8*SYMBOL_COUNT-1:0] SYMBOL_BYTES = {
        { 8'h00, 8'h01, 8'h02, 8'h03, 8'h11, 8'h04, 8'h05, 8'h21, 8'h31, 8'h06, 8'h12, 8'h41 },
        { 8'h51, 8'h07, 8'h61, 8'h71, 8'h13, 8'h22, 8'h32, 8'h81, 8'h08, 8'h14, 8'h42, 8'h91 },
        { 8'hA1, 8'hB1, 8'hC1, 8'h09, 8'h23, 8'h33, 8'h52, 8'hF0, 8'h15, 8'h62, 8'h72, 8'hD1 },
        { 8'h0A, 8'h16, 8'h24, 8'h34, 8'hE1, 8'h25, 8'hF1, 8'h17, 8'h18, 8'h19, 8'h1A, 8'h26 },
        { 8'h27, 8'h28, 8'h29, 8'h2A, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39, 8'h3A, 8'h43, 8'h44 },
        { 8'h45, 8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57, 8'h58 },
        { 8'h59, 8'h5A, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h73, 8'h74 },
        { 8'h75, 8'h76, 8'h77, 8'h78, 8'h79, 8'h7A, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87 },
        { 8'h88, 8'h89, 8'h8A, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97, 8'h98, 8'h99, 8'h9A },
        { 8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hB2, 8'hB3, 8'hB4 },
        { 8'hB5, 8'hB6, 8'hB7, 8'hB8, 8'hB9, 8'hBA, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7 },
        { 8'hC8, 8'hC9, 8'hCA, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7, 8'hD8, 8'hD9, 8'hDA },
        { 8'hE2, 8'hE3, 8'hE4, 8'hE5, 8'hE6, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hF2, 8'hF3, 8'hF4 },
        { 8'hF5, 8'hF6, 8'hF7, 8'hF8, 8'hF9, 8'hFA }
    };

    jpeg_huffman_fixed_lookup #(
        .SYMBOL_COUNT (SYMBOL_COUNT),
        .COUNT_BYTES  (CODE_COUNTS),
        .SYMBOL_BYTES (SYMBOL_BYTES)
    ) lookup (
        .code_prefix_i  (code_prefix_i),
        .symbol_valid_o (symbol_valid_o),
        .code_length_o  (code_length_o),
        .symbol_o       (symbol_o)
    );
endmodule
