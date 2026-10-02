`timescale 1ns / 1ps




module datapath_control #(
    parameter logic [7:0] SOF0_MARKER = 8'hC0,
    parameter logic [7:0] SOS_MARKER  = 8'hDA
) (
    input  logic        clk,
    input  logic        rst,

    // One payload byte from the input parser.
    // cfg_index_i starts at 0 after the segment length bytes.
    input  logic [7:0]  cfg_marker_i,
    input  logic [15:0] cfg_index_i,
    input  logic [7:0]  cfg_data_i,
    input  logic        cfg_valid_i,
    output logic        cfg_ready_o,

    output jpeg_header_types_pkg::sof0_data_t sof0_data_o,
    output jpeg_header_types_pkg::sos_data_t  sos_data_o
);

    import jpeg_header_types_pkg::*;

    sof0_data_t sof0_data, sof0_data_next;
    sos_data_t  sos_data,  sos_data_next;

    integer component_slot;
    logic [15:0] sos_tail_start;

    // This block never stalls the parser.
    always_comb begin
        cfg_ready_o = 1'b1;

        sof0_data_next = sof0_data;
        sos_data_next  = sos_data;

        component_slot = 0;
        sos_tail_start = 16'd0;

        if (cfg_valid_i && cfg_ready_o) begin
            case (cfg_marker_i)

                SOF0_MARKER: begin
                    case (cfg_index_i)
                        16'd0: begin
                            sof0_data_next.valid     = 1'b0;
                            sof0_data_next.precision = cfg_data_i;
                        end

                        16'd1: sof0_data_next.height[15:8] = cfg_data_i;
                        16'd2: sof0_data_next.height[7:0]  = cfg_data_i;
                        16'd3: sof0_data_next.width[15:8]  = cfg_data_i;
                        16'd4: sof0_data_next.width[7:0]   = cfg_data_i;
                        16'd5: sof0_data_next.component_count = cfg_data_i;

                        // Component 0: ID, sampling byte, quantization selector.
                        16'd6: sof0_data_next.comp0.component_id = cfg_data_i;
                        16'd7: begin
                            sof0_data_next.comp0.horizontal_sampling = cfg_data_i[7:4];
                            sof0_data_next.comp0.vertical_sampling   = cfg_data_i[3:0];
                        end
                        16'd8: sof0_data_next.comp0.quant_table_id = cfg_data_i;

                        // Component 1.
                        16'd9:  sof0_data_next.comp1.component_id = cfg_data_i;
                        16'd10: begin
                            sof0_data_next.comp1.horizontal_sampling = cfg_data_i[7:4];
                            sof0_data_next.comp1.vertical_sampling   = cfg_data_i[3:0];
                        end
                        16'd11: sof0_data_next.comp1.quant_table_id = cfg_data_i;

                        // Component 2.
                        16'd12: sof0_data_next.comp2.component_id = cfg_data_i;
                        16'd13: begin
                            sof0_data_next.comp2.horizontal_sampling = cfg_data_i[7:4];
                            sof0_data_next.comp2.vertical_sampling   = cfg_data_i[3:0];
                        end
                        16'd14: sof0_data_next.comp2.quant_table_id = cfg_data_i;

                        default: ;
                    endcase

                    // SOF0 payload ends at index 5 + 3*Nf.
                    if ((cfg_index_i ==
                         (16'd5 + (16'd3 * sof0_data.component_count))) &&
                        (sof0_data.component_count >= 8'd1) &&
                        (sof0_data.component_count <= 8'd3))
                        sof0_data_next.valid = 1'b1;
                end


                SOS_MARKER: begin
                    if (cfg_index_i == 16'd0) begin
                        sos_data_next.valid           = 1'b0;
                        sos_data_next.component_count = cfg_data_i;
                    end
                    else begin
                        // SOS component pairs start at index 1:
                        // ID, then packed DC/AC table selectors.
                        sos_tail_start =
                            16'd1 + (16'd2 * sos_data.component_count);

                        if (cfg_index_i < sos_tail_start) begin
                            component_slot = (cfg_index_i - 16'd1) >> 1;

                            if (cfg_index_i[0]) begin
                                case (component_slot)
                                    0: sos_data_next.comp0.component_id = cfg_data_i;
                                    1: sos_data_next.comp1.component_id = cfg_data_i;
                                    2: sos_data_next.comp2.component_id = cfg_data_i;
                                    default: ;
                                endcase
                            end
                            else begin
                                case (component_slot)
                                    0: begin
                                        sos_data_next.comp0.dc_table_id = cfg_data_i[7:4];
                                        sos_data_next.comp0.ac_table_id = cfg_data_i[3:0];
                                    end
                                    1: begin
                                        sos_data_next.comp1.dc_table_id = cfg_data_i[7:4];
                                        sos_data_next.comp1.ac_table_id = cfg_data_i[3:0];
                                    end
                                    2: begin
                                        sos_data_next.comp2.dc_table_id = cfg_data_i[7:4];
                                        sos_data_next.comp2.ac_table_id = cfg_data_i[3:0];
                                    end
                                    default: ;
                                endcase
                            end
                        end
                        else begin
                            case (cfg_index_i - sos_tail_start)
                                16'd0: sos_data_next.spectral_start = cfg_data_i;
                                16'd1: sos_data_next.spectral_end   = cfg_data_i;
                                16'd2: sos_data_next.successive_approximation = cfg_data_i;
                                default: ;
                            endcase
                        end
                    end

                    // SOS payload ends at index 3 + 2*Ns.
                    if ((cfg_index_i ==
                         (16'd3 + (16'd2 * sos_data.component_count))) &&
                        (sos_data.component_count >= 8'd1) &&
                        (sos_data.component_count <= 8'd3))
                        sos_data_next.valid = 1'b1;
                end

                default: ; // Ignore other marker payloads.
            endcase
        end
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            sof0_data <= '0;
            sos_data  <= '0;
        end
        else begin
            sof0_data <= sof0_data_next;
            sos_data  <= sos_data_next;
        end
    end

    assign sof0_data_o = sof0_data;
    assign sos_data_o  = sos_data;

endmodule
