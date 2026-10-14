"""Izbere najnovejši iPhone in iPad Pro 13" med razpoložljivimi simulatorji (izpis: ime|udid)."""
import json
import re
import subprocess
import sys

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devices = []
for runtime, devs in data["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devs:
        devices.append((ver, d["name"], d["udid"]))


def iphone_rank(name):
    m = re.match(r"iPhone (\d+)(.*)", name)
    if not m:
        return None
    suffix = m.group(2).strip()
    order = {"Pro Max": 4, "Pro": 3, "Plus": 2, "": 1, "Air": 2}
    return (int(m.group(1)), order.get(suffix, 0))


def ipad_rank(name):
    if not re.match(r"iPad Pro 13", name):
        return None
    m = re.search(r"M(\d+)", name)
    return (int(m.group(1)) if m else 0,)


kind = sys.argv[1]
rank = iphone_rank if kind == "iphone" else ipad_rank
cands = [(rank(n), v, n, u) for v, n, u in devices if rank(n) is not None]
if not cands:
    sys.exit(f"ni simulatorja za {kind}")
best = max(cands, key=lambda c: (c[0], c[1]))
print(f"{best[2]}|{best[3]}")
