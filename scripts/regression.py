#!/usr/bin/env python3
"""
QVision regression: runs every testbench under Icarus Verilog and compares
against the Python golden model (scripts/golden_model.py), which supports
QR versions 1-40, all four EC levels and the numeric / alphanumeric / byte /
kanji modes with automatic mode and version selection.

Also cross-checks the golden model itself against the `qrcode` reference
library and decodes rendered matrices with OpenCV (and zxing-cpp for kanji,
which OpenCV cannot decode).

Usage:
    python scripts/regression.py            # full regression
    python scripts/regression.py --quick    # smoke subset
"""
import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import golden_model as gm  # noqa: E402

RTL = ["rtl/qvision_config.vh", "rtl/qvision_sram.v",
       "rtl/reset_sync.v", "rtl/pix_clk_gen.v",
       "rtl/uart_rx.v", "rtl/qr_buf.v", "rtl/qr_encoder.v",
       "rtl/qr_rs_encoder.v", "rtl/qr_format_bch.v",
       "rtl/qr_matrix_builder.v", "rtl/qr_framebuffer.v",
       "rtl/qr_pixel_mapper.v", "rtl/vga_timing.v", "rtl/rgb_dac_out.v",
       "rtl/qr_controller.v", "rtl/qvision_top.v"]

failures = []


def check(name, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    print(f"  [{status}] {name}" + (f" - {detail}" if detail and not cond else ""))
    if not cond:
        failures.append(f"{name}: {detail}")


def run(cmd, timeout=1800):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                       cwd=ROOT)
    return p.stdout + p.stderr


def compile_tb(tb, out, extra=None, rtl=None):
    cmd = ["iverilog", "-g2012", "-DSIMULATION", "-I./rtl", "-o", out] + \
          (extra or []) + (rtl or RTL) + [tb]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if result.returncode != 0:
        print(result.stdout + result.stderr)
        sys.exit(f"compile failed: {tb}")
    return out


def hex_to_bits(h, width):
    """Fixed-width matrix dump: cells occupy the top `width` bits."""
    full = format(int(h, 16), f"0{width}b")
    return full[:width]


def bits_to_matrix(bits, size):
    return [[1 if bits[r * size + c] == "1" else 0 for c in range(size)]
            for r in range(size)]


def matrix_to_bits(mat):
    return "".join(str(v) for row in mat for v in row)


def render(mat, scale=8, quiet=4):
    import numpy as np
    n = len(mat)
    s = n + 2 * quiet
    img = np.full((s * scale, s * scale), 255, np.uint8)
    for r in range(n):
        for c in range(n):
            if mat[r][c]:
                img[(r + quiet) * scale:(r + quiet + 1) * scale,
                    (c + quiet) * scale:(c + quiet + 1) * scale] = 0
    return img


def test_golden_model():
    print("== golden model cross-checks ==")
    try:
        import qrcode
        from qrcode.util import QRData
    except ImportError:
        check("qrcode dependency available", False,
              "install dependencies from requirements.txt")
        return
    LIB_EC = {gm.EC_L: 1, gm.EC_M: 0, gm.EC_Q: 3, gm.EC_H: 2}
    LIB_MODE = {gm.MODE_NUM: 1, gm.MODE_ALNUM: 2, gm.MODE_BYTE: 4}
    fails = total = 0

    def cell_payload(mode, v, ec, fill=0.8):
        cap = gm.DATA_CW[v][ec] * 8
        per = {gm.MODE_NUM: 3.333, gm.MODE_ALNUM: 5.5, gm.MODE_BYTE: 8}[mode]
        n = max(1, int(cap * fill / per))
        if mode == gm.MODE_NUM:
            return bytes(b"0123456789"[i % 10] for i in range(n))
        if mode == gm.MODE_ALNUM:
            chars = b"ABC012 $%*+-./:"
            return bytes(chars[i % len(chars)] for i in range(n))
        return bytes((i * 13 + 5) % 251 for i in range(n))

    for v in (1, 2, 4, 5, 7, 10, 14, 20, 21, 27, 28, 35, 40):
        for ec in (gm.EC_L, gm.EC_M, gm.EC_Q, gm.EC_H):
            for mode in (gm.MODE_NUM, gm.MODE_ALNUM, gm.MODE_BYTE):
                p = cell_payload(mode, v, ec)
                mat, dmap, cw, occ = gm.build_base(p, mode, v, ec)
                for mask in range(8):
                    mine = gm.finalize(mat, dmap, mask, gm.SIZE[v], ec)
                    qr = qrcode.QRCode(version=v, error_correction=LIB_EC[ec],
                                       mask_pattern=mask)
                    qr.add_data(QRData(p, mode=LIB_MODE[mode]))
                    qr.make(fit=False)
                    ref = [[int(x) for x in row] for row in qr.modules]
                    total += 1
                    if mine != ref:
                        fails += 1
    check(f"golden vs qrcode library, forced grid ({total} matrices, "
          f"V1-40 sample)", fails == 0, f"{fails} mismatches")

    try:
        import zxingcpp
    except ImportError:
        check("zxing-cpp dependency available", False,
              "install dependencies from requirements.txt")
        return
    try:
        import cv2
        import numpy as np  # noqa: F401
    except ImportError:
        check("OpenCV dependency available", False,
              "install dependencies from requirements.txt")
        return
    detector = cv2.QRCodeDetector()
    decode_cases = [
        (b"HELLO", gm.EC_M),
        (b"", gm.EC_M),
        (b"QVISION FPGA QR CODE V2 TEST", gm.EC_L),
        (bytes((i * 7 + 3) % 251 for i in range(500)), gm.EC_L),
        (bytes((i * 29 + 11) % 251 for i in range(2956)), gm.EC_L),   # V40-L
        (bytes((i * 29 + 11) % 251 for i in range(1276)), gm.EC_H),   # V40-H
        (bytes((i * 29 + 11) % 251 for i in range(1666)), gm.EC_Q),   # V40-Q
        (b"0123456789" * 14, gm.EC_H),
    ]
    for payload, ec in decode_cases:
        rec = gm.generate(payload, ec)
        expect = rec["payload"]
        img = render(rec["matrix"], scale=4)
        if payload == b"":
            data, _, _ = detector.detectAndDecode(img)
            check(f"OpenCV decodes golden V{rec['version']}-{rec['ec']} empty",
                  data == "", f"decoded {data[:24]!r}")
            continue
        res = zxingcpp.read_barcode(img)
        ok = res is not None and res.bytes == expect.encode("latin-1")
        detail = "" if ok else \
            f"decoded {(res.bytes[:24] if res else 'not found')!r}"
        check(f"zxing decodes golden V{rec['version']}-{rec['ec']} "
              f"{payload[:12]!r}", ok, detail)

    kanji_cases = [
        "日本語テスト",
        "漢字モードのテストです。" * 20,
    ]
    for text in kanji_cases:
        payload = text.encode("shift_jis")
        rec = gm.generate(payload)
        check(f"kanji auto-select for {text[:8]!r}", rec["mode"] == "kanji",
              rec["mode"])
        res = zxingcpp.read_barcode(render(rec["matrix"], scale=4))
        ok = res is not None and res.text == text
        check(f"zxing decodes golden kanji {text[:8]!r}", ok,
              f"decoded {res.text[:16]!r}" if res else "not found")


def tb_packer_bytes(mode, length):
    """The deterministic byte sequence tb_qr_packer fills for a mode."""
    if mode == gm.MODE_NUM:
        return bytes(0x30 + i % 10 for i in range(length))
    if mode == gm.MODE_ALNUM:
        alpha = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
        return bytes(ord(alpha[i % 45]) for i in range(length))
    if mode == gm.MODE_KANJI:
        out = bytearray()
        for i in range(length):
            if i % 2 == 0:
                out.append(0x82 + (i >> 1) % 8)
            else:
                out.append(0x41 + i % 40)
        return bytes(out)
    return bytes(0x41 + i % 64 for i in range(length))


def test_packer(tmp):
    print("== qr_encoder (packer): numeric / alnum / byte / kanji packing ==")
    out = compile_tb("sim/tb_qr_packer.v", os.path.join(tmp, "pk.out"))
    cases = [
        (5, gm.MODE_ALNUM, 1, gm.EC_M),
        (0, gm.MODE_BYTE, 1, gm.EC_M),
        (8, gm.MODE_NUM, 1, gm.EC_M),
        (41, gm.MODE_NUM, 1, gm.EC_L),            # only 1 terminator bit
        (60, gm.MODE_NUM, 3, gm.EC_M),
        (78, gm.MODE_BYTE, 4, gm.EC_L),             # exact V4-L fit
        (23, gm.MODE_ALNUM, 2, gm.EC_M),            # full alnum alphabet
        (28, gm.MODE_ALNUM, 2, gm.EC_L),
        (500, gm.MODE_BYTE, 15, gm.EC_L),           # 16-bit count field
        (2953, gm.MODE_BYTE, 40, gm.EC_L),          # V40-L exact byte fit
        (12, gm.MODE_KANJI, 1, gm.EC_M),
        (400, gm.MODE_KANJI, 17, gm.EC_Q),          # 10-bit count field
        (700, gm.MODE_KANJI, 27, gm.EC_H),          # 13-bit count field
    ]
    for length, mode, v, ec in cases:
        fill = tb_packer_bytes(mode, length)
        cnt_w = gm.COUNT_BITS[v][gm.MODE_NAME[mode]]
        exp = gm.pack_data(fill, mode, v, ec)
        res = run(["vvp", out, f"+PLEN={length}", f"+MODE={mode}",
                   f"+CNTW={cnt_w}", f"+DATA_CW={gm.DATA_CW[v][ec]}"])
        line = next((l for l in res.splitlines() if l.startswith("CW ")), "")
        got = line[3:].strip()
        exp_hex = "".join(f"{b:02x}" for b in exp)
        check(f"packer len={length} {gm.MODE_NAME[mode]} V{v} cntw={cnt_w}",
              got == exp_hex,
              f"got {got[:48]} want {exp_hex[:48]}")


def test_rs(tmp):
    print("== qr_rs_encoder: block layouts incl. mixed data sizes ==")
    out = compile_tb("sim/tb_qr_rs_multiblock.v", os.path.join(tmp, "rs.out"),
                     rtl=["rtl/qvision_sram.v", "rtl/qr_rs_encoder.v"])
    ok = bad = 0
    for v in (1, 3, 4, 5, 7, 10, 15, 20, 25, 30, 35, 40):
        for ec in (gm.EC_L, gm.EC_M, gm.EC_Q, gm.EC_H):
            groups = gm.BLOCKS[v][ec]
            data_total = gm.DATA_CW[v][ec]
            payload = bytes((i * 7 + 3) % 251 for i in range(data_total))
            expected = bytes(gm.interleave(payload, groups))
            args = []
            off = 0
            if len(groups) == 1:
                d, e, n = groups[0]
                args = [f"+N1={n}", f"+D1={d}", f"+N2=0", f"+D2={d}", f"+ECC={e}"]
            else:
                (d1, e, n1), (d2, e2, n2) = groups
                args = [f"+N1={n1}", f"+D1={d1}", f"+N2={n2}", f"+D2={d2}",
                        f"+ECC={e}"]
            res = run(["vvp", out, f"+DATA={payload.hex()}", f"+ND={data_total}"]
                      + args)
            lines = res.strip().splitlines()
            got = lines[0].strip() if lines else ""
            want = expected.hex()
            name = f"RS V{v}-{gm.EC_NAME[ec]} {groups}"
            if got == want:
                ok += 1
            else:
                bad += 1
                check(name, False, f"got {got[:48]} want {want[:48]}")
    check(f"RS sweep ({ok} layouts)", bad == 0)


def test_matrix_builder(tmp):
    print("== qr_matrix_builder: layout, zigzag, mask selection, V1-40 ==")
    out = compile_tb("sim/tb_qr_matrix_builder.v", os.path.join(tmp, "mb.out"))
    seen = set()
    bad = 0
    for v in range(1, 41):
        for ec in ((gm.EC_M, gm.EC_H) if v % 7 == 0 else (gm.EC_M,)):
            cnt = gm.COUNT_BITS[v]["byte"]
            n = (gm.DATA_CW[v][ec] * 8 - (4 + cnt)) // 8
            payload = bytes((i * 13 + 5) % 251 for i in range(n))
            rec = gm.generate(payload, ec)
            if rec["version"] != v:
                check(f"builder V{v} payload selection", False,
                      f"payload selected V{rec['version']}")
                continue
            seen.add((v, gm.EC_NAME[ec]))
            cw_hex = "".join(f"{b:02x}" for b in rec["codewords"])
            res = run(["vvp", out, f"+CW={cw_hex}", f"+VER={v}",
                       f"+TOTALCW={len(rec['codewords'])}",
                       f"+ECFMT={gm.EC_FORMAT[ec]}"], timeout=3600)
            mask = next((int(l.split()[1]) for l in res.splitlines()
                         if l.startswith("MASK ")), -1)
            matline = next((l for l in res.splitlines()
                            if l.startswith("MATRIX ")), "")
            n_sq = rec["size"] * rec["size"]
            got = (bits_to_matrix(hex_to_bits(matline[7:].strip(), n_sq),
                                  rec["size"]) if matline else None)
            if got != rec["matrix"] or mask != rec["mask"]:
                bad += 1
                check(f"builder V{v}-{gm.EC_NAME[ec]} len={n}", False,
                      f"mask {mask}/{rec['mask']}"
                      + ("" if got == rec["matrix"] else ", matrix mismatch"))
    check(f"builder sweep V1-40 ({len(seen)} configs)", bad == 0)


def test_pipeline(tmp, quick=False):
    print("== full pipeline (controller -> packer -> RS -> builder -> fb) ==")
    bins = {}
    for ec_name, ec in (("L", gm.EC_L), ("M", gm.EC_M),
                        ("Q", gm.EC_Q), ("H", gm.EC_H)):
        bins[ec] = compile_tb("sim/tb_qr_pipeline.v",
                              os.path.join(tmp, f"pipe_{ec_name}.out"),
                              extra=[f"-Ptb_qr_pipeline.EC={ec}"])

    def run_pipe(payload, ec, preload, timeout=1800):
        rec = gm.generate(payload, ec)
        golden = f"{int(matrix_to_bits(rec['matrix']), 2):x}"
        res = run(["vvp", bins[ec], "+PAYLOAD=" + payload.hex(),
                   f"+PLEN={len(payload)}", f"+GOLDEN={golden}"]
                  + (["+PRELOAD=1"] if preload else []), timeout=timeout)
        status = next((l for l in res.splitlines() if l.startswith("STATUS")),
                      "missing")
        ok = "STATUS PASS" in status
        mask = next((int(l.split()[1]) for l in res.splitlines()
                     if l.startswith("MASK ")), -1)
        size = next((int(l.split()[1]) for l in res.splitlines()
                     if l.startswith("SIZE ")), -1)
        good = ok and mask == rec["mask"] and size == rec["size"]
        check(f"pipeline V{rec['version']}-{rec['ec']} {rec['mode']} "
              f"len={len(payload)}", good,
              f"status={status} mask={mask}/{rec['mask']} "
              f"size={size}/{rec['size']}")

    for payload, ec in [(b"HELLO", gm.EC_M), (b"hi", gm.EC_M), (b"", gm.EC_M),
                        (b"12345678", gm.EC_M),
                        (b"ABCDEFGHIJKLMNOP", gm.EC_M),
                        (b"QVISION FPGA QR CODE V2 TEST", gm.EC_M),
                        (b"HELLO", gm.EC_H)]:
        run_pipe(payload, ec, preload=False)
        if quick:
            break

    if quick:
        return

    def version_fit(v, ec):
        cnt = gm.COUNT_BITS[v]["byte"]
        return (gm.DATA_CW[v][ec] * 8 - (4 + cnt)) // 8

    grid = []
    for v in range(1, 41):
        n = version_fit(v, gm.EC_M)
        grid.append(bytes((i * 13 + 5) % 251 for i in range(n)))
    for ec in (gm.EC_L, gm.EC_M, gm.EC_Q, gm.EC_H):
        n = version_fit(40, ec)
        grid.append(bytes((i * 29 + 11) % 251 for i in range(n)))
    grid += [
        b"1" * 41,                                   # V1-L, 1-bit terminator
        bytes(range(1, 100)),                        # byte, mixed control chars
        b"HELLO WORLD $%*+-./: 42",                  # alnum specials
        b"1234567890" * 140,                         # numeric, V10+ count width
        "日本語テスト".encode("shift_jis"),            # kanji
        ("漢字モードのテストです。" * 20).encode("shift_jis"),
        ("漢字" * 750).encode("shift_jis"),          # kanji overflow clamp
        bytes((i * 29 + 11) % 251 for i in range(2900)),   # clamp path at M
        b"x" * 4000,                                 # overflow clamp at M
    ]
    ecs = [gm.EC_M] * 40 + [gm.EC_L, gm.EC_M, gm.EC_Q, gm.EC_H] + \
          [gm.EC_L] + [gm.EC_M] * 7
    for payload, ec in zip(grid, ecs):
        run_pipe(payload, ec, preload=True)


def test_legacy(tmp):
    print("== unit testbenches ==")
    for tb, expect in (("sim/tb_qr_format_bch.v", "PASS"),
                       ("sim/tb_vga_timing.v", "PASS")):
        out = compile_tb(tb, os.path.join(tmp, os.path.basename(tb) + ".out"))
        res = run(["vvp", out], timeout=900)
        check(f"{os.path.basename(tb)}", expect in res, res.strip()[-200:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        test_golden_model()
        test_packer(tmp)
        if not args.quick:
            test_rs(tmp)
            test_matrix_builder(tmp)
        test_pipeline(tmp, quick=args.quick)
        if not args.quick:
            test_legacy(tmp)
    print()
    if failures:
        print(f"REGRESSION FAILED - {len(failures)} failure(s):")
        for f in failures:
            print("  " + f)
        sys.exit(1)
    print("REGRESSION PASSED - all checks green.")


if __name__ == "__main__":
    main()
