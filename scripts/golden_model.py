#!/usr/bin/env python3
"""
QVision golden model - exact behavioral mirror of the RTL in rtl/, for QR
versions 1-40, all four EC levels (multi-block layouts and interleaving
included) and the four encoding modes, with the same automatic mode/version
selection policy as the RTL.

Geometry tables are derived from the `qrcode` reference library at import
time, never hand-typed (the remainder-bit table is the one exception; it is
checked by the data-bit-count assertion in build_base).  Kanji packing
follows ISO/IEC 18004; the `qrcode` library cannot encode kanji, so kanji
matrices are validated by OpenCV decodes in scripts/regression.py.
"""
import argparse
import json
from itertools import groupby

import qrcode.base as _qrb
import qrcode.util as _qru

EC_L, EC_M, EC_Q, EC_H = 0, 1, 2, 3
EC_NAME = {EC_L: "L", EC_M: "M", EC_Q: "Q", EC_H: "H"}
EC_FORMAT = {EC_L: 0b01, EC_M: 0b00, EC_Q: 0b11, EC_H: 0b10}
_LIB_EC = {EC_L: 1, EC_M: 0, EC_Q: 3, EC_H: 2}

MODE_BYTE, MODE_NUM, MODE_ALNUM, MODE_KANJI = 0, 1, 2, 3
MODE_NIBBLE = {MODE_NUM: 0b0001, MODE_ALNUM: 0b0010, MODE_BYTE: 0b0100,
               MODE_KANJI: 0b1000}
MODE_NAME = {MODE_NUM: "numeric", MODE_ALNUM: "alphanumeric",
             MODE_BYTE: "byte", MODE_KANJI: "kanji"}
_LIB_MODE = {MODE_NUM: _qru.MODE_NUMBER, MODE_ALNUM: _qru.MODE_ALPHA_NUM,
             MODE_BYTE: _qru.MODE_8BIT_BYTE}

ALNUM_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"


def _block_groups(v, ec):
    """[(data, ecc, nblocks), ...] groups for (v, ec), in ISO order."""
    blocks = _qrb.rs_blocks(v, _LIB_EC[ec])
    groups = []
    for dc, grp in groupby(blocks, key=lambda b: b.data_count):
        grp = list(grp)
        groups.append((dc, grp[0].total_count - dc, len(grp)))
    return groups


_VERSIONS = range(1, 41)

BLOCKS = {v: {ec: _block_groups(v, ec) for ec in EC_NAME} for v in _VERSIONS}
DATA_CW = {v: {ec: sum(d * n for d, e, n in BLOCKS[v][ec]) for ec in EC_NAME}
           for v in _VERSIONS}
TOTAL_CW = {v: {ec: sum((d + e) * n for d, e, n in BLOCKS[v][ec])
                for ec in EC_NAME} for v in _VERSIONS}
SIZE = {v: 17 + 4 * v for v in _VERSIONS}
ALIGN_POS = {v: list(_qru.pattern_position(v)) for v in _VERSIONS}
REMAINDER_BITS = {}
for _v in _VERSIONS:
    REMAINDER_BITS[_v] = (0 if _v == 1 else
                          7 if _v <= 6 else
                          0 if _v <= 13 else
                          3 if _v <= 20 else
                          4 if _v <= 27 else
                          3 if _v <= 34 else 0)
_COUNT_MODE = {MODE_NUM: _qru.MODE_NUMBER, MODE_ALNUM: _qru.MODE_ALPHA_NUM,
               MODE_BYTE: _qru.MODE_8BIT_BYTE, MODE_KANJI: _qru.MODE_KANJI}
COUNT_BITS = {v: {MODE_NAME[m]: _qru.length_in_bits(_COUNT_MODE[m], v)
                  for m in MODE_NAME} for v in _VERSIONS}

MAX_PAYLOAD = max(DATA_CW[v][EC_L] for v in _VERSIONS)   # V40-L: 2956


def gf_mul(a, b):
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        a = ((a << 1) ^ 0x11D) & 0xFF if a & 0x80 else (a << 1) & 0xFF
        b >>= 1
    return p


def rs_generator(npar):
    """Generator polynomial coefficients, highest degree first, monic."""
    g = [1]
    for i in range(npar):
        a = 1
        for _ in range(i):
            a = gf_mul(a, 2)
        ng = [0] * (len(g) + 1)
        for j, c in enumerate(g):
            ng[j] ^= c                  # x * g
            ng[j + 1] ^= gf_mul(c, a)   # alpha^i * g
        g = ng
    return g


_GEN_CACHE = {}


def rs_parity(data, npar):
    if npar not in _GEN_CACHE:
        _GEN_CACHE[npar] = rs_generator(npar)
    g = _GEN_CACHE[npar]
    msg = list(data) + [0] * npar
    for i in range(len(data)):
        c = msg[i]
        if c:
            for j in range(1, npar + 1):
                msg[i + j] ^= gf_mul(g[j], c)
    return msg[len(data):]


def sjis_pair_value(b1, b2):
    """13-bit kanji value for a Shift-JIS double byte, or None if invalid.

    ISO/IEC 18004: row 1 is b1 in 0x81-0x9F with b2 in 0x40-0x7F or
    0x80-0xFC (0x7F excluded), row 2 is b1 in 0xE0-0xEB with b2 in
    0x40-0xBF.  In BOTH rows the value is (b1 - base) * 0xC0 + (b2 - 0x40)
    with base = 0x81 / 0xC1 - the second byte is never shifted by an extra
    1, only the validity range changes.  Max value 8191 (13 bits)."""
    if 0x81 <= b1 <= 0x9F:
        hi, lo_ok = b1 - 0x81, (0x40 <= b2 <= 0x7E) or (0x80 <= b2 <= 0xFC)
    elif 0xE0 <= b1 <= 0xEB:
        hi, lo_ok = b1 - 0xC1, 0x40 <= b2 <= 0xBF
    else:
        return None
    if not lo_ok:
        return None
    return hi * 0xC0 + (b2 - 0x40)


def classify(payload):
    if len(payload) >= 2 and len(payload) % 2 == 0 and all(
            sjis_pair_value(payload[i], payload[i + 1]) is not None
            for i in range(0, len(payload), 2)):
        return MODE_KANJI
    if all(0x30 <= b <= 0x39 for b in payload) and payload:
        return MODE_NUM
    if all(chr(b) in ALNUM_CHARS for b in payload):
        return MODE_ALNUM
    return MODE_BYTE


def payload_bits(n, mode):
    if mode == MODE_NUM:
        k, r = divmod(n, 3)
        return 10 * k + (0 if r == 0 else (4 if r == 1 else 7))
    if mode == MODE_ALNUM:
        k, r = divmod(n, 2)
        return 11 * k + (6 if r else 0)
    if mode == MODE_KANJI:
        return 13 * (n // 2)
    return 8 * n


def select_version(n, mode, ec):
    """Smallest version whose capacity fits the payload; None if none does.
    The count-field width depends on the candidate version, so each version
    must be checked with its own width (not one global width)."""
    for v in _VERSIONS:
        need = 4 + COUNT_BITS[v][MODE_NAME[mode]] + payload_bits(n, mode)
        if DATA_CW[v][ec] * 8 >= need:
            return v
    return None


def select(payload, ec):
    mode = classify(payload)
    n = len(payload)
    v = select_version(n, mode, ec)
    too_long = v is None
    if too_long:
        step = 2 if mode == MODE_KANJI else 1
        start = min(n, MAX_PAYLOAD)
        if mode == MODE_KANJI:
            start -= start % 2
        for n_try in range(start, -1, -step):
            v = select_version(n_try, mode, ec)
            if v is not None:
                payload = payload[:n_try]
                n = n_try
                break
    return mode, v, n, too_long


def pack_data(payload, mode, v, ec):
    """Returns the data codewords for ALL blocks (block-contiguous)."""
    cap = DATA_CW[v][ec] * 8
    bits = []
    mb = MODE_NIBBLE[mode]
    bits += [(mb >> (3 - i)) & 1 for i in range(4)]
    w = COUNT_BITS[v][MODE_NAME[mode]]
    n = len(payload)
    count_val = n // 2 if mode == MODE_KANJI else n
    bits += [(count_val >> (w - 1 - i)) & 1 for i in range(w)]

    if mode == MODE_NUM:
        for i in range(0, n, 3):
            grp = payload[i:i + 3]
            val = int(grp.decode())
            width = 10 if len(grp) == 3 else (7 if len(grp) == 2 else 4)
            bits += [(val >> (width - 1 - j)) & 1 for j in range(width)]
    elif mode == MODE_ALNUM:
        for i in range(0, n, 2):
            grp = payload[i:i + 2]
            if len(grp) == 2:
                val = (ALNUM_CHARS.index(chr(grp[0])) * 45 +
                       ALNUM_CHARS.index(chr(grp[1])))
                bits += [(val >> (10 - j)) & 1 for j in range(11)]
            else:
                val = ALNUM_CHARS.index(chr(grp[0]))
                bits += [(val >> (5 - j)) & 1 for j in range(6)]
    elif mode == MODE_KANJI:
        for i in range(0, n, 2):
            val = sjis_pair_value(payload[i], payload[i + 1])
            assert val is not None, "invalid Shift-JIS pair in kanji payload"
            bits += [(val >> (12 - j)) & 1 for j in range(13)]
    else:
        for byte in payload:
            bits += [(byte >> (7 - i)) & 1 for i in range(8)]

    used = len(bits)
    rem = cap - used
    assert rem >= 0, "payload does not fit selected version"
    t = min(4, rem)
    bits += [0] * t
    while len(bits) % 8:
        bits.append(0)
    first_pad = (used + t + 7) // 8
    while len(bits) < cap:
        idx = len(bits) // 8
        byte = 0xEC if (idx - first_pad) % 2 == 0 else 0x11
        bits += [(byte >> (7 - i)) & 1 for i in range(8)]
    codewords = []
    for i in range(0, cap, 8):
        v8 = 0
        for b in bits[i:i + 8]:
            v8 = (v8 << 1) | b
        codewords.append(v8)
    assert len(codewords) == DATA_CW[v][ec]
    return codewords


def interleave(data_cw_all, groups):
    """ISO interleaving.  groups = [(d, e, n), ...]; shorter blocks simply
    contribute fewer data codewords in the data phase, parity is uniform."""
    blocks = []
    parities = []
    off = 0
    for d, e, n in groups:
        for _ in range(n):
            blk = data_cw_all[off:off + d]
            off += d
            blocks.append(blk)
            parities.append(rs_parity(blk, e))
    assert off == len(data_cw_all)
    out = []
    for i in range(max(d for d, e, n in groups)):
        for b in blocks:
            if i < len(b):
                out.append(b[i])
    for i in range(max(e for d, e, n in groups)):
        for p in parities:
            out.append(p[i])
    return out


def function_map(size, aligns, version):
    occ = [[False] * size for _ in range(size)]

    def mark(r0, c0, h, w):
        for r in range(r0, r0 + h):
            for c in range(c0, c0 + w):
                occ[r][c] = True

    mark(0, 0, 9, 9)
    mark(0, size - 8, 9, 8)
    mark(size - 8, 0, 8, 9)
    for i in range(size):
        occ[6][i] = True
        occ[i][6] = True
    occ[size - 8][8] = True                       # dark module
    for r in aligns:
        for c in aligns:
            if (r == 6 and c == 6) or (r == 6 and c == size - 7) or \
               (r == size - 7 and c == 6):
                continue
            mark(r - 2, c - 2, 5, 5)
    if version >= 7:                              # version information
        mark(0, size - 11, 6, 3)
        mark(size - 11, 0, 3, 6)
    for c in range(size - 8, size):
        occ[8][c] = True                          # format, copy 2
    for r in range(size - 7, size):
        occ[r][8] = True
    return occ


def zigzag_cells(size):
    cells = []
    right = size - 1
    upward = True
    while right > 0:
        if right == 6:
            right = 5
        rows = range(size - 1, -1, -1) if upward else range(size)
        for r in rows:
            for c in (right, right - 1):
                yield (r, c)
        upward = not upward
        right -= 2


def draw_function_patterns(mat, size, aligns, version):
    def put(r, c, v):
        mat[r][c] = v

    for (r0, c0) in ((0, 0), (0, size - 7), (size - 7, 0)):
        for dr in range(7):
            for dc in range(7):
                edge = dr in (0, 6) or dc in (0, 6)
                core = 2 <= dr <= 4 and 2 <= dc <= 4
                put(r0 + dr, c0 + dc, 1 if (edge or core) else 0)
    for i in range(8, size - 8):
        put(6, i, 1 if i % 2 == 0 else 0)
        put(i, 6, 1 if i % 2 == 0 else 0)
    for r in aligns:
        for c in aligns:
            if (r == 6 and c == 6) or (r == 6 and c == size - 7) or \
               (r == size - 7 and c == 6):
                continue
            for dr in range(-2, 3):
                for dc in range(-2, 3):
                    dark = (dr in (-2, 2) or dc in (-2, 2) or
                            (dr == 0 and dc == 0))
                    put(r + dr, c + dc, 1 if dark else 0)
    put(size - 8, 8, 1)
    if version >= 7:
        bits = bch_version(version)
        for i in range(18):
            b = (bits >> i) & 1
            put(i // 3, size - 11 + i % 3, b)          # below top-right finder
            put(size - 11 + i % 3, i // 3, b)          # left of bottom-left finder
    return mat


def bch_format(ec_level, mask_id):
    data = (EC_FORMAT[ec_level] << 3) | mask_id
    rem = data << 10
    for i in range(4, -1, -1):
        if rem & (1 << (i + 10)):
            rem ^= 0x537 << i
    return ((data << 10) | rem) ^ 0x5412


def bch_version(version):
    """18-bit version information (6 data + 12 BCH, G18 = 0x1F25, no mask)."""
    assert 7 <= version <= 40
    d = version << 12
    while d.bit_length() >= 13:
        d ^= 0x1F25 << (d.bit_length() - 13)
    return (version << 12) | d


def format_cells(size):
    """(row, col, bit index) for all 30 format modules, bit 0 = LSB."""
    cells = []
    for r in range(0, 6):
        cells.append((r, 8, r))
    cells.append((7, 8, 6))
    cells.append((8, 8, 7))
    cells.append((8, 7, 8))
    for c in range(5, -1, -1):
        cells.append((8, c, 14 - c))
    for c in range(size - 1, size - 9, -1):
        cells.append((8, c, size - 1 - c))
    for r in range(size - 7, size):
        cells.append((r, 8, r - size + 15))
    assert len(cells) == 30
    return cells


def mask_bit(mask, r, c):
    if mask == 0:
        return (r + c) % 2 == 0
    if mask == 1:
        return r % 2 == 0
    if mask == 2:
        return c % 3 == 0
    if mask == 3:
        return (r + c) % 3 == 0
    if mask == 4:
        return (r // 2 + c // 3) % 2 == 0
    if mask == 5:
        return (r * c) % 2 + (r * c) % 3 == 0
    if mask == 6:
        return ((r * c) % 2 + (r * c) % 3) % 2 == 0
    if mask == 7:
        return ((r * c) % 3 + (r + c) % 2) % 2 == 0
    raise ValueError(mask)


def build_base(payload, mode, v, ec):
    data_cw_all = pack_data(payload, mode, v, ec)
    codewords = interleave(data_cw_all, BLOCKS[v][ec])
    size = SIZE[v]
    aligns = ALIGN_POS[v]
    occ = function_map(size, aligns, v)
    mat = [[0] * size for _ in range(size)]
    dmap = [[0] * size for _ in range(size)]
    draw_function_patterns(mat, size, aligns, v)
    bits = []
    for cw in codewords:
        bits += [(cw >> (7 - i)) & 1 for i in range(8)]
    total_data_bits = sum(1 for r in range(size) for c in range(size)
                          if not occ[r][c])
    assert total_data_bits == len(codewords) * 8 + REMAINDER_BITS[v], \
        (v, size, total_data_bits, len(codewords) * 8)
    bit_idx = 0
    for (r, c) in zigzag_cells(size):
        if not occ[r][c]:
            bit = bits[bit_idx] if bit_idx < len(bits) else 0   # remainder = 0
            mat[r][c] = bit
            dmap[r][c] = 1
            bit_idx += 1
    return mat, dmap, codewords, occ


def penalty(mat, dmap, mask, size, ec_level):
    fb = bch_format(ec_level, mask)
    fmt_lookup = {(r, c): (fb >> i) & 1 for (r, c, i) in format_cells(size)}
    cell = [[fmt_lookup[(r, c)] if (r, c) in fmt_lookup
             else (mat[r][c] ^ (dmap[r][c] & (1 if mask_bit(mask, r, c) else 0)))
             for c in range(size)] for r in range(size)]

    p = 0
    for r in range(size):
        run_len, run_col = 1, cell[r][0]
        window = 0
        for c in range(size):
            v = cell[r][c]
            if c > 0:
                if v == run_col:
                    run_len += 1
                else:
                    if run_len >= 5:
                        p += run_len - 2
                    run_len, run_col = 1, v
            window = ((window << 1) | v) & 0x7FF
            if c >= 10:
                if window == 0b00001011101 or window == 0b10111010000:
                    p += 40
        if run_len >= 5:
            p += run_len - 2
    for c in range(size):
        run_len, run_col = 1, cell[0][c]
        window = 0
        for r in range(size):
            v = cell[r][c]
            if r > 0:
                if v == run_col:
                    run_len += 1
                else:
                    if run_len >= 5:
                        p += run_len - 2
                    run_len, run_col = 1, v
            window = ((window << 1) | v) & 0x7FF
            if r >= 10:
                if window == 0b00001011101 or window == 0b10111010000:
                    p += 40
        if run_len >= 5:
            p += run_len - 2
    for r in range(size - 1):
        for c in range(size - 1):
            v = cell[r][c]
            if cell[r][c + 1] == v and cell[r + 1][c] == v and cell[r + 1][c + 1] == v:
                p += 3
    total = size * size
    dark = sum(map(sum, cell))
    p += 10 * (abs(dark * 100 - 50 * total) // (5 * total))
    return p


def best_mask(mat, dmap, size, ec_level):
    pens = [penalty(mat, dmap, m, size, ec_level) for m in range(8)]
    best = 0
    for m in range(1, 8):
        if pens[m] < pens[best]:
            best = m
    return best, pens


def finalize(mat, dmap, mask, size, ec_level):
    out = [row[:] for row in mat]
    for r in range(size):
        for c in range(size):
            if dmap[r][c] and mask_bit(mask, r, c):
                out[r][c] ^= 1
    fb = bch_format(ec_level, mask)
    for (r, c, i) in format_cells(size):
        out[r][c] = (fb >> i) & 1
    return out


def generate(payload, ec=EC_M):
    if isinstance(payload, str):
        payload = payload.encode("latin-1")
    mode, v, n, too_long = select(payload, ec)
    payload = payload[:n]
    mat, dmap, codewords, occ = build_base(payload, mode, v, ec)
    size = SIZE[v]
    mask, pens = best_mask(mat, dmap, size, ec)
    final = finalize(mat, dmap, mask, size, ec)
    return {
        "payload": payload.decode("latin-1"),
        "mode": MODE_NAME[mode],
        "version": v,
        "ec": EC_NAME[ec],
        "codewords": codewords,
        "too_long": too_long,
        "mask": mask,
        "penalties": pens,
        "matrix": final,
        "size": size,
    }


def matrix_str(mat):
    return "\n".join("".join(str(v) for v in row) for row in mat)


def matrix_bits(mat):
    return "".join(str(v) for row in mat for v in row)


def main():
    ap = argparse.ArgumentParser(description="QVision golden model")
    ap.add_argument("payload", nargs="?", default="HELLO")
    ap.add_argument("--ec", default="M", choices=["L", "M", "Q", "H"])
    ap.add_argument("--codewords", action="store_true")
    ap.add_argument("--penalties", action="store_true")
    ap.add_argument("--json", help="write full record to a JSON file")
    args = ap.parse_args()
    ec = {"L": EC_L, "M": EC_M, "Q": EC_Q, "H": EC_H}[args.ec]
    rec = generate(args.payload.encode("latin-1"), ec)
    print(f"version V{rec['version']}-{rec['ec']} mode={rec['mode']} "
          f"mask={rec['mask']} bytes={len(rec['payload'].encode('latin-1'))}")
    if args.codewords:
        print(" ".join(f"{b:02X}" for b in rec["codewords"]))
    if args.penalties:
        print("penalties:", rec["penalties"])
    print(matrix_str(rec["matrix"]))
    if args.json:
        with open(args.json, "w") as f:
            json.dump(rec, f)


if __name__ == "__main__":
    main()
