"""Pripravi manjši vzorec resničnih podatkov za demo način aplikacij (zaslonski posnetki, testi).

Uporaba: python tools/make_demo_data.py <mapa_z_zajemom> <ciljna_mapa> [<ciljna_mapa> ...]
"""

import json
import shutil
import sys
from collections import defaultdict
from pathlib import Path

PER_CATEGORY = 14


def main(src: Path, targets: list[Path]) -> None:
    offers = json.loads((src / "offers.json").read_text(encoding="utf-8"))
    items = offers["offers"]
    chosen: dict[str, dict] = {}
    for o in items:
        if o.get("bestUnitPrice"):
            chosen[o["id"]] = o
    by_cat = defaultdict(list)
    for o in items:
        by_cat[o.get("category")].append(o)
    for cat, lst in by_cat.items():
        lst.sort(key=lambda o: -(o.get("discountPct") or 0))
        for o in lst[:PER_CATEGORY]:
            chosen[o["id"]] = o
    by_chain = defaultdict(list)
    for o in items:
        by_chain[o["chain"]].append(o)
    for lst in by_chain.values():
        for o in lst[:10]:
            chosen[o["id"]] = o
    # primerljive ponudbe (ista vrsta) za prikaz primerjave
    kinds = {o.get("kind") for o in chosen.values() if o.get("kind")}
    for o in items:
        if o.get("kind") in kinds and len(chosen) < 900:
            chosen[o["id"]] = o
    demo = dict(offers, offers=sorted(chosen.values(), key=lambda o: (o.get("category") or "", o["name"])))
    hist = json.loads((src / "history.json").read_text(encoding="utf-8"))
    keys = {f'{o["productKey"]}|{o["condition"]["type"]}' for o in demo["offers"]}
    for t in targets:
        t.mkdir(parents=True, exist_ok=True)
        (t / "offers.json").write_text(json.dumps(demo, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        (t / "history.json").write_text(
            json.dumps({k: v for k, v in hist.items() if k in keys}, separators=(",", ":")), encoding="utf-8")
        for name in ("meta.json", "coupons.json", "guide.json"):
            if (src / name).exists():
                shutil.copy(src / name, t / name)
    print(f"demo: {len(demo['offers'])} ponudb -> {', '.join(map(str, targets))}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), [Path(p) for p in sys.argv[2:]])
