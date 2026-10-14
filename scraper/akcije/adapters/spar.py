"""SPAR/INTERSPAR: kategorija "Iz letaka" v spletni trgovini online.spar.si.

www.spar.si je za Cloudflare izzivom, ki ga ne zaobidemo. online.spar.si je
Next.js aplikacija; podatki o izdelkih so v RSC toku (self.__next_f.push(...)),
ki ga razčlenimo in razrešimo reference "$id".
"""

from __future__ import annotations

import json
import re
from datetime import date, datetime

from ..models import Condition, Offer
from ..units import compute_unit_price, extract_pack, local_date_from_iso
from .base import Adapter

BASE = "https://online.spar.si"
LETAK = BASE + "/ca/aktualno/iz-letaka/S17/S17-1"
MAX_PAGES = 30

_PUSH = re.compile(r'self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)')
_ROW = re.compile(r"^([0-9a-f]+):(.*)$", re.S)
_REF = re.compile(r"\$[0-9a-f]+")


class SparAdapter(Adapter):
    chain = "spar"
    source = "online.spar.si – Iz letaka"
    url = LETAK

    def fetch(self) -> list[Offer]:
        first = self.client.text(LETAK)
        pages = [first]
        info = pagination(first)
        last = min(info[1] if info else 1, MAX_PAGES)
        for n in range(2, last + 1):
            pages.append(self.client.text(f"{LETAK}?currentPage={n}"))
        out: dict[str, Offer] = {}
        for html in pages:
            for o in parse_page(html, self.today, self.now):
                out.setdefault(f"{o.source_id}|{o.condition}", o)
        if info and len(out) < info[2] * 0.8:
            self.notes.append(f"prebranih {len(out)} od {info[2]} izdelkov")
        return list(out.values())


def flight_rows(html: str) -> dict[str, object]:
    data = "".join(json.loads(c) for c in _PUSH.findall(html))
    rows: dict[str, object] = {}
    for line in data.split("\n"):
        m = _ROW.match(line)
        if not m or m.group(2)[:1] not in "[{":
            continue
        try:
            rows[m.group(1)] = json.loads(m.group(2))
        except json.JSONDecodeError:
            continue
    return rows


def resolve(x, rows: dict, depth: int = 0):
    if depth > 10:
        return x
    if isinstance(x, str) and _REF.fullmatch(x):
        return resolve(rows.get(x[1:]), rows, depth + 1)
    if isinstance(x, list):
        return [resolve(i, rows, depth + 1) for i in x]
    if isinstance(x, dict):
        return {k: resolve(v, rows, depth + 1) for k, v in x.items()}
    return x


def pagination(html: str) -> tuple[int, int, int] | None:
    m = re.search(r'\\?"pagination\\?":\{\\?"page\\?":(\d+),\\?"pages\\?":(\d+),\\?"total\\?":\{\\?"value\\?":(\d+)', html)
    return tuple(int(g) for g in m.groups()) if m else None  # type: ignore[return-value]


def fix_mojibake(s: str | None) -> str | None:
    if not s:
        return s
    if any(ch in s for ch in "ĹÄĂ"):
        try:
            return s.encode("iso-8859-2").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            return s
    return s


def nice_name(s: str) -> str:
    """'ČOKOLADNA REZINA, SPAR,160G' -> 'Čokoladna rezina, Spar, 160 g'."""
    s = re.sub(r",(?=[^\s\d])", ", ", s.strip())
    s = re.sub(r"(?<=\D),(?=\d+\s*(?:g|kg|ml|l)\b)", ", ", s, flags=re.I)
    if s.isupper():
        s = s[:1] + s[1:].lower()
        s = re.sub(r"\bspar\b", "Spar", s)
    s = re.sub(r"(\d)\s*(g|kg|ml|l)\b", r"\1 \2", s, flags=re.I)
    return s


def parse_page(html: str, today: date, now: datetime) -> list[Offer]:
    rows = flight_rows(html)
    out: list[Offer] = []
    for raw in rows.values():
        if not (isinstance(raw, dict) and raw.get("__typename") == "CatalogProductModel"):
            continue
        p = resolve(raw, rows)
        name = p.get("name")
        price = p.get("price")
        if not name or price is None:
            continue
        promo = p.get("promotion") or {}
        promos = p.get("promotions") or []
        action, label, start, end = None, None, None, None
        if promo and promo.get("isActive"):
            conds = promo.get("conditions") or []
            if conds and conds[0].get("price") is not None:
                action = float(conds[0]["price"])
            label = fix_mojibake(promo.get("description"))
            start, end = promo.get("startDateTime"), promo.get("endDateTime")
        if action is None:
            for pr in promos:
                b = pr.get("benefit") or {}
                if pr.get("isActive") and b.get("type") == "unitPrice" and b.get("value") is not None:
                    action = float(b["value"])
                    label = fix_mojibake(pr.get("description") or b.get("label"))
                    start, end = pr.get("startDateTime"), pr.get("endDateTime")
                    break
        regular = float(price)
        if action is None or action >= regular:
            # brez aktivne akcije (v letaku je lahko tudi "nova cena")
            action, regular_out = regular, None
        else:
            regular_out = regular
        nm = nice_name(name)
        pack = extract_pack(nm)
        sub_unit = (p.get("subUnit") or "").lower()
        ppu = p.get("promotionPricePerSubUnit") if regular_out else p.get("pricePerSubUnit")
        unit = None
        if ppu and sub_unit in ("kg", "l", "kos"):
            unit = (float(ppu), sub_unit)
        elif (p.get("unit") or "").upper() == "KG":
            unit = (action, "kg")
            pack = pack or "za kg"
        else:
            unit = compute_unit_price(action, pack, nm)
        cats = p.get("categoriesData") or []
        hint = next(
            (c.get("categoryNamesPath") for c in sorted(cats, key=lambda c: -(c.get("level") or 0))
             if c.get("categoryNamesPath") and "AKTUALNO" not in c.get("categoryNamesPath")),
            None,
        )
        eans = p.get("ean") or []
        photos = p.get("photosUrl") or []
        cond_text = label if label and label.lower() not in ("takojšnji popust",) else None
        out.append(
            Offer(
                chain="spar",
                name=nm,
                brand=p.get("brand") if p.get("brand") not in (None, "Ostalo", "DS") else None,
                price=action,
                regular_price=regular_out,
                pack_size=pack,
                unit_price=unit[0] if unit else None,
                unit=unit[1] if unit else None,
                valid_from=local_date_from_iso(start),
                valid_to=local_date_from_iso(end),
                condition=Condition.NONE,
                condition_text=cond_text,
                source_url=f"{BASE}/p/{p.get('slug')}" if p.get("slug") else LETAK,
                image_url=photos[0] if photos else None,
                ean=next((e for e in eans if isinstance(e, str) and len(e) == 13 and not e.startswith("2")), None),
                source_id=str(p.get("sku") or ""),
                source_category=hint,
                fetched_at=now,
            )
        )
    return out
