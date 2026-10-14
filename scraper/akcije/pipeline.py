"""Zažene vse adapterje, normalizira, razvrsti, odstrani dvojnike in zapiše JSON."""

from __future__ import annotations

import json
import logging
import time
import traceback
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path

from .adapters import ADAPTERS
from .adapters.base import Adapter
from .classify import CAT, categories_json, classify, kind_for
from .http import PoliteClient
from .models import Coupon, Offer, SourceResult
from .units import TZ

log = logging.getLogger(__name__)

SCHEMA_VERSION = 1
HISTORY_DAYS = 180
STALE_DAYS = 3

CHAINS = [
    {"id": "mercator", "name": "Mercator", "color": "#D7141A", "website": "https://www.mercator.si",
     "catalogUrl": "https://www.mercator.si/katalogi/", "section": "zivila"},
    {"id": "spar", "name": "SPAR / INTERSPAR", "color": "#00784A", "website": "https://www.spar.si",
     "catalogUrl": "https://online.spar.si/ca/aktualno/iz-letaka/S17/S17-1", "section": "zivila"},
    {"id": "tus", "name": "Tuš", "color": "#7DB928", "website": "https://www.tus.si",
     "catalogUrl": "https://www.tus.si/aktualno/katalogi-in-revije/", "section": "zivila"},
    {"id": "hofer", "name": "HOFER", "color": "#1A2D6D", "website": "https://www.hofer.si",
     "catalogUrl": "https://www.hofer.si/sl/ponudba.html", "section": "zivila"},
    {"id": "lidl", "name": "Lidl", "color": "#0050AA", "website": "https://www.lidl.si",
     "catalogUrl": "https://www.lidl.si/c/spletni-katalog/s10019133", "section": "zivila"},
    {"id": "eurospin", "name": "Eurospin", "color": "#E6A800", "website": "https://www.eurospin.si",
     "catalogUrl": "https://www.eurospin.si/akcije/", "section": "zivila"},
    {"id": "obi", "name": "OBI", "color": "#FF6A00", "website": "https://www.obi.si",
     "catalogUrl": "https://www.obi.si/katalog", "section": "dom"},
]


@dataclass
class RunResult:
    offers: list[Offer]
    coupons: list[Coupon]
    sources: list[SourceResult]
    catalogs: list[dict]
    unclassified: list[dict]


def run_adapters(client: PoliteClient, only: set[str] | None = None, now: datetime | None = None) -> RunResult:
    now = now or datetime.now(TZ)
    offers: list[Offer] = []
    coupons: list[Coupon] = []
    sources: list[SourceResult] = []
    catalogs: list[dict] = []
    unclassified: list[dict] = []

    for cls in ADAPTERS:
        if only and cls.chain not in only:
            continue
        adapter: Adapter = cls(client, now)
        res = SourceResult(chain=cls.chain, source=cls.source, url=cls.url)
        t0 = time.monotonic()
        try:
            got = adapter.fetch()
            for o in got:
                _enrich(o, adapter.default_section, unclassified)
            offers.extend(got)
            res.count = len(got)
            if not got:
                res.status = "error"
                res.error = "vir ni vrnil nobenega izdelka (morda se je spremenila struktura strani)"
        except Exception as e:  # napaka enega vira ne ustavi drugih
            res.status = "error"
            res.error = f"{type(e).__name__}: {e}"
            log.error("%s: %s\n%s", cls.chain, e, traceback.format_exc())
        # kuponi in katalogi niso ključni – napaka se zabeleži v opombe
        try:
            coupons.extend(adapter.coupons())
        except Exception as e:
            adapter.notes.append(f"kuponi: {type(e).__name__}: {e}")
        if hasattr(adapter, "catalogs"):
            try:
                catalogs.extend(adapter.catalogs())
            except Exception as e:
                adapter.notes.append(f"katalogi: {type(e).__name__}: {e}")
        res.duration_ms = int((time.monotonic() - t0) * 1000)
        res.fetched_at = now
        res.notes = adapter.notes
        sources.append(res)
        log.info("%s: %s, %d izdelkov, %d ms", cls.chain, res.status, res.count, res.duration_ms)
    return RunResult(offers, coupons, sources, catalogs, unclassified)


def _enrich(o: Offer, default_section: str, unclassified: list[dict]) -> None:
    r = classify(o.name, o.brand, o.source_category, default_section)
    o.category = r.category
    o.kind = kind_for(o.name, r.category)
    o.finalize()
    if not r.certain:
        unclassified.append({
            "chain": o.chain,
            "name": o.name,
            "brand": o.brand,
            "sourceCategory": o.source_category,
            "assigned": r.category,
            "rule": r.rule,
        })


def dedupe(offers: list[Offer]) -> list[Offer]:
    best: dict[tuple, Offer] = {}
    for o in offers:
        key = (o.product_key, str(o.condition), o.valid_from)
        cur = best.get(key)
        if cur is None or o.price < cur.price:
            best[key] = o
    return list(best.values())


def mark_best_unit_prices(offers: list[Offer], today: date) -> None:
    groups: dict[tuple[str, str], list[Offer]] = defaultdict(list)
    for o in offers:
        if not o.kind or not o.unit_price or not o.unit:
            continue
        if o.valid_to and o.valid_to < today:
            continue
        groups[(o.kind, o.unit)].append(o)
    for items in groups.values():
        if len({o.chain for o in items}) < 2:
            continue
        low = min(o.unit_price for o in items)
        for o in items:
            o.best_unit_price = abs(o.unit_price - low) < 0.005


def update_history(history: dict, offers: list[Offer], today: date) -> dict:
    cutoff = (today - timedelta(days=HISTORY_DAYS)).isoformat()
    day = today.isoformat()
    for o in offers:
        key = f"{o.product_key}|{o.condition}"
        pts = [p for p in history.get(key, []) if p[0] >= cutoff and p[0] != day]
        same_day = [p for p in history.get(key, []) if p[0] == day]
        price = min([o.price] + [p[1] for p in same_day])
        pts.append([day, round(price, 2)])
        history[key] = sorted(pts)
    for key in list(history):
        history[key] = [p for p in history[key] if p[0] >= cutoff]
        if not history[key]:
            del history[key]
    return history


def carry_over_failed(sources: list[SourceResult], offers: list[Offer], previous: list[dict], today: date) -> list[dict]:
    """Za vire z napako obdrži prejšnje (še veljavne) ponudbe, da aplikacija ne ostane prazna."""
    failed = {s.chain for s in sources if s.status == "error"}
    if not failed or not previous:
        return []
    kept = []
    min_fetch = (datetime.now(TZ) - timedelta(days=STALE_DAYS)).isoformat()
    for p in previous:
        if p.get("chain") not in failed:
            continue
        vt = p.get("validTo")
        if vt and vt < today.isoformat():
            continue
        if (p.get("fetchedAt") or "") < min_fetch:
            continue
        p = dict(p)
        p["stale"] = True
        kept.append(p)
    for s in sources:
        if s.chain in failed:
            n = sum(1 for p in kept if p["chain"] == s.chain)
            if n:
                s.notes.append(f"prikazanih {n} ponudb iz prejšnjega uspešnega zajema")
    return kept


def build(result: RunResult, out_dir: Path, data_dir: Path | None = None, guide: Path | None = None,
          now: datetime | None = None) -> dict:
    now = now or datetime.now(TZ)
    today = now.date()
    data_dir = data_dir or out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    offers = dedupe(result.offers)
    mark_best_unit_prices(offers, today)
    offers.sort(key=lambda o: (CAT[o.category].section if o.category in CAT else "", o.category or "", o.chain, o.name))

    previous = _load(data_dir / "offers.json", {}).get("offers", [])
    stale = carry_over_failed(result.sources, offers, previous, today)

    history = update_history(_load(data_dir / "history.json", {}), offers, today)

    for c in result.coupons:
        c.finalize()
    coupons = list({c.id: c for c in result.coupons}.values())

    gen = now.isoformat(timespec="seconds")
    offers_json = {"schemaVersion": SCHEMA_VERSION, "generatedAt": gen,
                   "offers": [o.to_json() for o in offers] + stale}
    stats_by_cat: dict[str, int] = defaultdict(int)
    for o in offers_json["offers"]:
        stats_by_cat[o.get("category") or "?"] += 1
    meta = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": gen,
        "discountThresholdDefault": 30,
        "sources": [s.to_json() for s in result.sources],
        "chains": CHAINS,
        "catalogs": result.catalogs,
        **categories_json(),
        "stats": {
            "offers": len(offers_json["offers"]),
            "coupons": len(coupons),
            "unclassified": len(result.unclassified),
            "byCategory": dict(sorted(stats_by_cat.items())),
            "bestUnitPrice": sum(1 for o in offers if o.best_unit_price),
        },
    }
    _dump(out_dir / "offers.json", offers_json)
    _dump(out_dir / "coupons.json", {"schemaVersion": SCHEMA_VERSION, "generatedAt": gen,
                                     "coupons": [c.to_json() for c in coupons]})
    _dump(out_dir / "meta.json", meta, compact=False)
    _dump(out_dir / "history.json", history, compact=True)
    _dump(out_dir / "unclassified.json", {"generatedAt": gen, "items": result.unclassified})
    if guide and guide.exists():
        (out_dir / "guide.json").write_text(guide.read_text(encoding="utf-8"), encoding="utf-8")
    (out_dir / "report.md").write_text(report_md(meta, result.unclassified), encoding="utf-8")
    return meta


def report_md(meta: dict, unclassified: list[dict]) -> str:
    lines = [f"# Zajem akcij – {meta['generatedAt']}", "", "| Veriga | Vir | Stanje | Izdelkov | Čas | Opombe |",
             "|---|---|---|---:|---:|---|"]
    for s in meta["sources"]:
        note = "; ".join(([s["error"]] if s.get("error") else []) + s.get("notes", []))
        lines.append(f"| {s['chain']} | {s['source']} | {'✅' if s['status'] == 'ok' else '❌'} {s['status']} | "
                     f"{s['count']} | {s['durationMs'] / 1000:.1f} s | {note} |")
    st = meta["stats"]
    lines += ["", f"Skupaj ponudb: **{st['offers']}**, kuponov: {st['coupons']}, "
                  f"najnižja cena na enoto: {st['bestUnitPrice']}, neuvrščenih: {st['unclassified']}", ""]
    lines += ["## Po kategorijah", ""] + [f"- {k}: {v}" for k, v in st["byCategory"].items()]
    if unclassified:
        lines += ["", "## Neuvrščeni izdelki (dopolni pravila v `scraper/akcije/classify.py`)", "",
                  "| Veriga | Ime | Kategorija vira | Dodeljeno |", "|---|---|---|---|"]
        for u in unclassified[:300]:
            lines.append(f"| {u['chain']} | {u['name']} | {u.get('sourceCategory') or ''} | {u['assigned']} |")
        if len(unclassified) > 300:
            lines.append(f"| … | še {len(unclassified) - 300} | | |")
    return "\n".join(lines) + "\n"


def _load(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def _dump(path: Path, data, compact: bool = True) -> None:
    if compact:
        text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    else:
        text = json.dumps(data, ensure_ascii=False, indent=1)
    path.write_text(text + "\n", encoding="utf-8")
