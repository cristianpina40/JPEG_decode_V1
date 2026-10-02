
`timescale 1ns / 1ps

// JPEG marker/segment parser. Entropy bytes are emitted unstuffed: FF 00 is
// delivered as one FF byte. Non-stuffed markers are consumed by this parser.
module jpeg_bitstream_reader #(
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
    input  logic        clk,
    input  logic        aresetn,
    input  logic        start,

    input  logic [7:0]  byte_data,
    input  logic        byte_valid,
    output logic        byte_ready,

    output logic [7:0]  cfg_marker,
    output logic [15:0] cfg_index,
    output logic [7:0]  cfg_data,
    output logic        cfg_valid,
    input  logic        cfg_ready,

    output logic [7:0]  entropy_data,
    output logic        entropy_valid,
    input  logic        entropy_ready,

    output logic        image_start,
    output logic        image_end,
    output logic        error
);

    typedef enum logic [3:0] {
        ST_WAIT_SOI_FF,
        ST_WAIT_SOI_CODE,
        ST_WAIT_MARKER_FF,
        ST_MARKER_CODE,
        ST_LENGTH_HI,
        ST_LENGTH_LO,
        ST_SEGMENT_PAYLOAD,
        ST_ENTROPY,
        ST_ENTROPY_AFTER_FF,
        ST_DONE
    } state_t;

    state_t state, state_next;
    logic [7:0] marker, marker_next;
    logic [7:0] length_hi, length_hi_next;
    logic [15:0] payload_remaining, payload_remaining_next;
    logic [15:0] payload_index, payload_index_next;
    logic error_next;
    logic image_start_next, image_end_next;
    logic accepted_byte;

    logic is_restart_marker;

    always_comb begin
        state_next = state;
        marker_next = marker;
        length_hi_next = length_hi;
        payload_remaining_next = payload_remaining;
        payload_index_next = payload_index;
        error_next = error;
        image_start_next = 1'b0;
        image_end_next = 1'b0;

        byte_ready = !start;
        cfg_marker = marker;
        cfg_index = payload_index;
        cfg_data = byte_data;
        cfg_valid = 1'b0;
        entropy_data = byte_data;
        entropy_valid = 1'b0;
        accepted_byte = byte_valid && byte_ready;
        is_restart_marker = (byte_data >= RST0) && (byte_data <= RST7);

        case (state)
            ST_WAIT_SOI_FF: begin
                if (accepted_byte && (byte_data == 8'hFF))
                    state_next = ST_WAIT_SOI_CODE;
            end

            ST_WAIT_SOI_CODE: begin
                if (accepted_byte) begin
                    if (byte_data == SOI) begin
                        image_start_next = 1'b1;
                        state_next = ST_WAIT_MARKER_FF;
                    end
                    else if (byte_data != 8'hFF) begin
                        state_next = ST_WAIT_SOI_FF;
                    end
                end
            end

            ST_WAIT_MARKER_FF: begin
                if (accepted_byte && (byte_data == 8'hFF))
                    state_next = ST_MARKER_CODE;
            end

            ST_MARKER_CODE: begin
                if (accepted_byte && (byte_data != 8'hFF)) begin
                    if (byte_data == EOI) begin
                        image_end_next = 1'b1;
                        state_next = ST_DONE;
                    end
                    else if (byte_data == SOI) begin
                        error_next = 1'b1;
                        image_start_next = 1'b1;
                        state_next = ST_WAIT_MARKER_FF;
                    end
                    else if (is_restart_marker || (byte_data == 8'h01)) begin
                        // RST markers and TEM are standalone, with no length.
                        if (is_restart_marker)
                            error_next = 1'b1;
                        state_next = ST_WAIT_MARKER_FF;
                    end
                    else if (byte_data == SOF2) begin
                        // Progressive JPEG is outside this baseline decoder.
                        error_next = 1'b1;
                        state_next = ST_DONE;
                    end
                    else begin
                        marker_next = byte_data;
                        state_next = ST_LENGTH_HI;
                    end
                end
            end

            ST_LENGTH_HI: begin
                if (accepted_byte) begin
                    length_hi_next = byte_data;
                    state_next = ST_LENGTH_LO;
                end
            end

            ST_LENGTH_LO: begin
                if (accepted_byte) begin
                    if ({length_hi, byte_data} < 16'd2) begin
                        error_next = 1'b1;
                        state_next = ST_DONE;
                    end
                    else begin
                        payload_remaining_next = {length_hi, byte_data} - 16'd2;
                        payload_index_next = 16'd0;
                        if ({length_hi, byte_data} == 16'd2) begin
                            if (marker == SOS)
                                state_next = ST_ENTROPY;
                            else
                                state_next = ST_WAIT_MARKER_FF;
                        end
                        else begin
                            state_next = ST_SEGMENT_PAYLOAD;
                        end
                    end
                end
            end

            ST_SEGMENT_PAYLOAD: begin
                cfg_valid = byte_valid;
                byte_ready = !start && cfg_ready;
                accepted_byte = byte_valid && byte_ready;
                if (accepted_byte) begin
                    payload_index_next = payload_index + 16'd1;
                    payload_remaining_next = payload_remaining - 16'd1;
                    if (payload_remaining == 16'd1) begin
                        if (marker == SOS)
                            state_next = ST_ENTROPY;
                        else
                            state_next = ST_WAIT_MARKER_FF;
                    end
                end
            end

            ST_ENTROPY: begin
                if (byte_valid && (byte_data == 8'hFF)) begin
                    // Hold the FF prefix until the next byte identifies data/marker.
                    byte_ready = !start;
                    accepted_byte = byte_valid && byte_ready;
                    if (accepted_byte)
                        state_next = ST_ENTROPY_AFTER_FF;
                end
                else begin
                    entropy_valid = byte_valid;
                    byte_ready = !start && entropy_ready;
                    accepted_byte = byte_valid && byte_ready;
                end
            end

            ST_ENTROPY_AFTER_FF: begin
                if (byte_valid && (byte_data == 8'h00)) begin
                    // FF 00 is one literal FF entropy byte for the bit reservoir.
                    entropy_data = 8'hFF;
                    entropy_valid = 1'b1;
                    byte_ready = !start && entropy_ready;
                    accepted_byte = byte_valid && byte_ready;
                    if (accepted_byte)
                        state_next = ST_ENTROPY;
                end
                else if (byte_valid && (byte_data == 8'hFF)) begin
                    byte_ready = !start;
                    accepted_byte = byte_valid && byte_ready;
                    if (accepted_byte)
                        state_next = ST_ENTROPY_AFTER_FF;
                end
                else if (accepted_byte) begin
                    if (byte_data == EOI) begin
                        image_end_next = 1'b1;
                        state_next = ST_DONE;
                    end
                    else if (is_restart_marker) begin
                        // Restart handling is unsupported in this first version.
                        error_next = 1'b1;
                        state_next = ST_ENTROPY;
                    end
                    else begin
                        // Unexpected in-scan marker (including progressive/DNL markers).
                        error_next = 1'b1;
                        state_next = ST_DONE;
                    end
                end
            end

            ST_DONE: begin
                byte_ready = 1'b0;
                if (start) begin
                    state_next = ST_WAIT_SOI_FF;
                    marker_next = 8'd0;
                    length_hi_next = 8'd0;
                    payload_remaining_next = 16'd0;
                    payload_index_next = 16'd0;
                    error_next = 1'b0;
                end
            end

            default: begin
                state_next = ST_WAIT_SOI_FF;
                error_next = 1'b1;
            end
        endcase

    end

    always_ff @(posedge clk) begin
        if (!aresetn) begin
            state <= ST_WAIT_SOI_FF;
            marker <= 8'd0;
            length_hi <= 8'd0;
            payload_remaining <= 16'd0;
            payload_index <= 16'd0;
            image_start <= 1'b0;
            image_end <= 1'b0;
            error <= 1'b0;
        end
        else if (start) begin
            state <= ST_WAIT_SOI_FF;
            marker <= 8'd0;
            length_hi <= 8'd0;
            payload_remaining <= 16'd0;
            payload_index <= 16'd0;
            image_start <= 1'b0;
            image_end <= 1'b0;
            error <= 1'b0;
        end
        else begin
            state <= state_next;
            marker <= marker_next;
            length_hi <= length_hi_next;
            payload_remaining <= payload_remaining_next;
            payload_index <= payload_index_next;
            image_start <= image_start_next;
            image_end <= image_end_next;
            error <= error_next;
        end
    end

endmodule
