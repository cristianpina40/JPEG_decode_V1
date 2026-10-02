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
