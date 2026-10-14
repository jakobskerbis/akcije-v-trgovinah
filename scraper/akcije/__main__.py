"""Uporaba:  python -m akcije --out ../public [--data ../public] [--only lidl,tus]"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .http import PoliteClient
from .pipeline import build, run_adapters


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="akcije", description="Zajem akcij slovenskih trgovcev")
    ap.add_argument("--out", type=Path, required=True, help="mapa za offers.json, coupons.json, meta.json …")
    ap.add_argument("--data", type=Path, help="mapa s prejšnjim zajemom (zgodovina cen); privzeto --out")
    ap.add_argument("--guide", type=Path, default=Path(__file__).resolve().parents[2] / "data" / "guide.json")
    ap.add_argument("--only", help="samo te verige, ločene z vejico")
    ap.add_argument("--delay", type=float, default=1.5, help="sekunde med zahtevki na isti strežnik")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    only = set(args.only.split(",")) if args.only else None
    with PoliteClient(delay=args.delay) as client:
        result = run_adapters(client, only)
        meta = build(result, args.out, args.data, args.guide)
        logging.info("zahtevkov: %d", client.request_count)
    ok = sum(1 for s in meta["sources"] if s["status"] == "ok")
    print(f"Viri ok: {ok}/{len(meta['sources'])}, ponudb: {meta['stats']['offers']}, "
          f"neuvrščenih: {meta['stats']['unclassified']}")
    # izhodna koda 0, dokler deluje vsaj en vir (posamezne napake so v meta.json)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
