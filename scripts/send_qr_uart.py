#!/usr/bin/env python3
"""Send an exact QR payload to QVision over a serial port (no CR/LF added)."""

import argparse
from pathlib import Path
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send bytes to QVision at 115200 8N1 without appending a newline."
    )
    parser.add_argument("--port", required=True, help="serial port, for example COM5")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--text", help="text payload to encode")
    source.add_argument("--file", type=Path, help="file whose bytes are sent unchanged")
    parser.add_argument(
        "--encoding",
        choices=("ascii", "utf-8", "shift_jis"),
        default="utf-8",
        help="encoding used with --text (default: utf-8; use shift_jis for QR Kanji mode)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        import serial
    except ImportError:
        print("pyserial is required: py -m pip install pyserial", file=sys.stderr)
        return 2

    try:
        payload = (
            args.file.read_bytes()
            if args.file is not None
            else args.text.encode(args.encoding)
        )
    except (OSError, UnicodeError) as exc:
        print(f"Cannot prepare payload: {exc}", file=sys.stderr)
        return 2

    if not payload:
        print("Payload is empty; nothing sent.", file=sys.stderr)
        return 2
    if len(payload) > 4096:
        print("Payload exceeds the 4096-byte hardware input buffer.", file=sys.stderr)
        return 2

    try:
        with serial.Serial(
            port=args.port,
            baudrate=115200,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1,
            write_timeout=5,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        ) as uart:
            written = uart.write(payload)
            uart.flush()
    except serial.SerialException as exc:
        print(f"Serial transfer failed: {exc}", file=sys.stderr)
        return 1

    if written != len(payload):
        print(f"Short write: sent {written} of {len(payload)} bytes.", file=sys.stderr)
        return 1

    print(f"Sent {written} bytes on {args.port} (no CR/LF added).")
    print("Press BTN0 once to commit and generate the QR code.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
