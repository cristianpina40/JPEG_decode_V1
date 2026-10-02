# RTL JPEG Decoder

A first-pass, synthesizable SystemVerilog datapath for decoding a restricted subset of baseline JPEG. The design is split into streaming blocks so the marker parser, entropy decoder, transform stages, and output writer can be developed or replaced independently.

## Supported input subset

The current top-level accepts an 8-bit baseline sequential JPEG (`SOF0`) with three components and 4:4:4 sampling. The frame header and scan header must list the same components in the same order. This implementation treats component 0 as Y, component 1 as Cb, and component 2 as Cr. The SOS parameters must describe a sequential scan (`Ss=0`, `Se=63`, `Ah/Al=0`).

The JPEG must use the fixed Annex K example tables included in `jpeg_fixed_tables.sv`:

- Quantization table ID 0: fixed luma quantization table.
- Quantization table ID 1: fixed chroma quantization table.
- Huffman table ID 0: fixed luminance DC and AC tables.
- Huffman table ID 1: fixed chrominance DC and AC tables.

The parser reads and forwards DQT/DHT segment payload bytes as configuration data, but the current top-level does not load them into writable tables or compare them with the fixed ROM contents. As a result, a JPEG with custom DQT/DHT contents, other table IDs, or incompatible table assignments will not decode correctly. The headers select IDs 0 and 1; the actual table values are compile-time constants.

Progressive JPEG (`SOF2`), restart intervals/restart markers, non-4:4:4 sampling, grayscale, arithmetic coding, multiple scans, and precision other than 8 bits are unsupported. Nonzero DRI is reported as unsupported. APP and COM segments are skipped by their lengths. The parser removes entropy byte stuffing (`FF 00` becomes a literal `FF`) before forwarding bytes to the bit reservoir.

## Data path

1. `jpeg_bitstream_reader.sv` searches for SOI, parses marker codes and segment lengths, forwards segment payload bytes with `cfg_marker/cfg_index/cfg_data/cfg_valid`, skips unsupported metadata payloads, and emits unstuffed entropy bytes after SOS. It reports EOI and parser errors.
2. `datapath_control.sv` captures SOF0 dimensions, component IDs, sampling factors, and quantization selectors, plus SOS component IDs, DC/AC table selectors, and scan parameters. These header fields come from the JPEG stream; they are not hardcoded.
3. `jpeg_entropy_bit_reader.sv` collects entropy bytes into an MSB-first bit reservoir and provides a lookahead window and bit-consumption handshake.
4. `jpeg_entropy_controller.sv` uses fixed Huffman lookups to decode one DC value followed by AC run/size symbols for each block. It applies DC prediction and emits 64 quantized coefficients in zig-zag order. Blocks are sequenced Y, Cb, Cr for each 8x8 MCU under the supported 4:4:4 assumption.
5. `jpeg_inverse_zigzag_dequant.sv` maps zig-zag coefficients to 8x8 matrix positions and multiplies them by the selected fixed quantization values.
6. `jpeg_idct_8x8.sv` performs the inverse discrete cosine transform and emits 64 spatial samples per block.
7. `jpeg_level_shift_clamp.sv` adds the JPEG level shift of 128 and clamps samples to unsigned 8-bit values.
8. `jpeg_ycbcr_to_rgb_framebuffer.sv` buffers matching Y, Cb, and Cr blocks, converts each pixel to RGB, clips channels, and emits row-major framebuffer addresses. Pixels beyond the image width or height at partial edge blocks are omitted.
9. `jpeg_top.sv` wires these blocks together and exposes a ready/valid RGB framebuffer write interface. The framebuffer memory, DDR controller, and display pipeline are external.

## What is hardcoded

| Value or behavior | Where it is defined | Current behavior |
|---|---|---|
| Luma/chroma quantization values | `jpeg_fixed_tables.sv`, `jpeg_quant_table_0_luma` and `jpeg_quant_table_1_chroma` | Two 64-entry combinational lookup tables addressed by zig-zag coefficient index. Values are constants in `case` statements. |
| Four Huffman tables | `jpeg_fixed_tables.sv`, `jpeg_huffman_dc0_luma`, `jpeg_huffman_dc1_chroma`, `jpeg_huffman_ac0_luma`, `jpeg_huffman_ac1_chroma` | Canonical code-length counts and ordered symbol lists are compile-time `localparam` constants. The lookup calculates the matching code and symbol combinationally. |
| Supported table IDs | `jpeg_top.sv` | IDs 0 and 1 only; the JPEG headers select which ROM to use. |
| Component order and sampling | `jpeg_top.sv` and color-output block | Three components, 1x1 sampling each, ordered Y/Cb/Cr. |
| Color conversion coefficients | `jpeg_ycbcr_to_rgb_framebuffer.sv` | Fixed-point integer constants implement the standard YCbCr-to-RGB equations. |
| IDCT matrix coefficients | `jpeg_idct_8x8.sv` | Fixed-point cosine matrix values are returned by a constant lookup function. |

The image width, height, component IDs, quantization-table selectors, Huffman-table selectors, and scan parameters are read from SOF0/SOS payload bytes. They are runtime inputs, but the top level accepts only values that fit the supported subset above.

## Source files

| File | Purpose |
|---|---|
| `jpeg_header_types_pkg.sv` | Packed SOF0 and SOS header structures. |
| `jpeg_bitstream_reader.sv` | JPEG marker/segment parser and entropy byte un-stuffing. |
| `datapath_control.sv` | SOF0/SOS payload capture. |
| `jpeg_entropy_bit_reader.sv` | Entropy bit reservoir. |
| `jpeg_fixed_tables.sv` | Fixed quantization and Huffman tables. |
| `jpeg_entropy_controller.sv` | DC/AC Huffman decoding and coefficient-block assembly. |
| `jpeg_inverse_zigzag_dequant.sv` | Inverse zig-zag and dequantization. |
| `jpeg_idct_8x8.sv` | 8x8 inverse DCT. |
| `jpeg_level_shift_clamp.sv` | Add 128 and clamp to 8 bits. |
| `jpeg_ycbcr_to_rgb_framebuffer.sv` | 4:4:4 color conversion and framebuffer write generation. |
| `jpeg_top.sv` | Top-level integration and external interfaces. |

## Integration

Instantiate `jpeg_top` and provide a byte stream using `byte_data`, `byte_valid`, and `byte_ready`. Assert `start` to reset/re-arm the parser for a new image. The input producer must hold each byte stable while `byte_valid` is high and wait for `byte_ready` before advancing.

Connect `pixel_valid_o`, `pixel_address_o`, and `pixel_rgb_o` to a framebuffer writer; the consumer asserts `pixel_ready_i` when it can accept a write. `image_start_o` and `image_end_o` report parser-level SOI/EOI events. `scan_done_o` reports completion of entropy decoding, `image_done_o` reports completion of framebuffer pixel output, and `error_o` is the combined error indication.

The RTL does not allocate a framebuffer, perform DDR transfers, or drive HDMI. Those functions belong in surrounding system logic. Compile `jpeg_header_types_pkg.sv` before modules that reference its typedefs. A typical source order is the package, fixed tables, parser/header and datapath modules, then `jpeg_top.sv`.

## Current status

This is an RTL starting point, not a validated general-purpose JPEG decoder. No testbench or automated regression is included in this source set. Before relying on it, simulate it with known baseline 8-bit 4:4:4 JPEG vectors whose DQT/DHT data matches the fixed tables, check coefficient and pixel outputs against a reference decoder, and run the target FPGA/ASIC toolchain's SystemVerilog synthesis and timing checks.
