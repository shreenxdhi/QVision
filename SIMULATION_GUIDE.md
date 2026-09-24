# Simulation Guide

## Quick start

```bash
# one-time: python venv with the reference tools
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --requirement requirements.txt

# self-checking end-to-end simulation (Icarus Verilog)
tclsh scripts/run_simulation.tcl

# full regression: every stage vs the Python golden model
python scripts/regression.py            # everything
python scripts/regression.py --quick    # smoke subset
```

## What is verified

| Layer | Check |
|---|---|
| Golden model (`scripts/golden_model.py`) | Bit-identical to the `qrcode` reference library on a forced-mask grid sampled across versions 1-40 (13 versions x 4 EC x 3 modes x 8 masks); version-info BCH matches the library for V7-40; matrices decode with zxing-cpp / OpenCV (kanji via zxing-cpp, which the golden's kanji packing is validated against - the `qrcode` library cannot encode kanji) |
| `qr_encoder` (packer) | Data codewords match ISO packing for every mode, all three count-field width classes (V1-9 / V10-26 / V27-40), the empty payload, alphanumeric specials (`$ % * + - . / :` - a 5-bit literal bug once corrupted these), exact-capacity fits and kanji pairs |
| `qr_rs_encoder` | Emitted interleaved stream matches `golden_model.interleave` for 48 (version, EC) layouts across every version decade, including mixed data-block sizes (e.g. V15-L = 5x87+1x88, V40-Q = 20x15+61x16) |
| `qr_matrix_builder` | Committed matrix and selected mask match the golden model exactly for one auto-selected payload per version 1-40 (alignment grids, version info, remainder bits, mask penalties) |
| Full pipeline | UART in (bit-banged, small payloads) and buffer preloaded (large payloads) runs: display matrix and mask match the golden model across all 40 versions, V40 at every EC, all modes incl. kanji, exact-capacity boundaries and the overflow-clamp path |

## Testbench details

`tb_qr_pipeline` (top-level):
- 100 MHz clock (matches `CLK_IN_HZ`), 115200 baud UART task
- `+PAYLOAD=<hex>` `+PLEN=<n>` payload selection ("HELLO" by default)
- `+GOLDEN=<hex>` optional expected display matrix (31329 bits fixed-width,
  MSB = module (0,0); leading zeros preserved)
- `+PRELOAD=1` writes the payload straight into `qr_buf` instead of
  bit-banging UART - use for anything beyond a few dozen bytes (2956 bytes
  at 115200 baud is ~0.26 s of sim time per message otherwise)
- `-Ptb_qr_pipeline.EC=<0..3>` selects the EC level (0=L 1=M 2=Q 3=H)
- Prints `SIZE <n>`, `MASK <d>`, `MATRIX <hex>` and `STATUS PASS/FAIL`

`tb_qr_packer`: `+PLEN=<n> +MODE=<0..3> +CNTW=<n> +DATA_CW=<n>`; fills the
buffer with a mode-specific deterministic byte pattern (mirrored by
`regression.py`) and prints the data codewords (`CW <hex>`).

`tb_qr_matrix_builder`: `+CW=<hex> +VER=<1..40> +TOTALCW=<n> +ECFMT=<0..3>`;
feeds the full codeword sequence and prints the chosen mask plus the
committed display matrix.

`tb_qr_rs_multiblock`: `+DATA=<hex> +ND=<n> +N1= +D1= +N2= +D2= +ECC=`;
prints the interleaved output stream (data phase, then parity phase).

`scripts/run_simulation.tcl`: compiles the full RTL and runs the pipeline on
"HELLO" against a hard-coded golden matrix (mask 2). If you change encoder
behaviour, regenerate the golden with:

```bash
python -c "import sys; sys.path.insert(0,'scripts'); import golden_model as gm; \
  rec = gm.generate(b'HELLO'); print(f\"{int(gm.matrix_bits(rec['matrix']),2):x}\")"
```

## Timeline (100 MHz, "HELLO" over UART)

- 0-100 ns: reset
- ~0-450 us: UART reception of 5 bytes at 115200
- commit → controller scan + version fit (~0.1 us) → packer (~1.6 us) →
  RS (~1 us) → function patterns + data placement (~6 us) → mask evaluation
  over 8 masks (~72 us) → format write + framebuffer commit (~5 us)
- `matrix_done` ≈ 86 us after commit; LED[0] lights

For V40 the mask evaluation dominates: 8 masks x 2 passes x 31329 modules ≈
0.5 M cycles ≈ 5 ms.

## Pass criteria

- `tclsh scripts/run_simulation.tcl` prints `STATUS PASS`
- `regression.py` ends with `REGRESSION PASSED - all checks green.`
- The regression's image decoders read the committed matrices back to the
  original payloads (done automatically inside the regression)
