"""Mercator: akcijski izdelki iz mercatoronline.si (JSON) + seznam katalogov in ugodnosti.

Cene so iz Mercatorjeve spletne trgovine; akcije iz kataloga so tam praviloma enake.
PDF katalog je v aplikaciji na voljo kot povezava (razčlenjevanje večstolpčnega PDF-ja
bi bilo nezanesljivo).
"""

from __future__ import annotations

import re
from datetime import date, datetime, timedelta
from urllib.parse import urljoin

from selectolax.lexbor import LexborHTMLParser

from ..models import Condition, Coupon, Offer, Redeem
from ..units import compute_unit_price, extract_pack, parse_date_range
from .base import Adapter

SHOP = "https://mercatoronline.si"
DISCOUNTS = "1,2,3,4,5,6,10,11,15,16,18,100,103,109,113,114,115,126,101,108,110,111,104,105,106,112"
# offset je številka strani, from = offset * limit (tako kot v grid.min.js spletne trgovine)
API = SHOP + "/products/browseProducts/getProducts?limit={limit}&offset={page}&from={start}&filterData%5Bdiscounts%5D=" + DISCOUNTS
PAGE = 200
MAX_PAGES = 40
SITE = "https://www.mercator.si"

_MULTI = re.compile(r"ob nakupu (\d+) izdelkov ali več je vsak (\d+)\s*% ceneje", re.I)
_PIKA = re.compile(r"pika kartic", re.I)


class MercatorAdapter(Adapter):
    chain = "mercator"
    source = "mercatoronline.si (akcije)"
    url = SHOP + "/brskaj/akcije"

    def fetch(self) -> list[Offer]:
        offers: list[Offer] = []
        offset, total = 0, None
        seen: set[str] = set()
        for page in range(MAX_PAGES):
            data = self.client.json(
                API.format(limit=PAGE, page=page, start=page * PAGE), headers={"X-Requested-With": "XMLHttpRequest"}
            )
            products = data.get("products") or []
            fresh = [p for p in products if str(p.get("itemId")) not in seen]
            if not fresh:
                break
            seen.update(str(p.get("itemId")) for p in fresh)
            total = total or int(products[0].get("total") or 0)
            offers.extend(o for p in fresh for o in to_offers(p, self.today, self.now))
            offset += len(fresh)
            if total and offset >= total:
                break
        if total and offset < total:
            self.notes.append(f"prebranih {offset} od {total} izdelkov")
        return offers

    def coupons(self) -> list[Coupon]:
        html = self.client.text(SITE + "/akcije-in-ugodnosti/")
        out = []
        for title, href in parse_promotions(html):
            c = Coupon(
                chain="mercator",
                title=title,
                source_url=href,
                how_to_redeem=Redeem.CARD if "pik" in title.lower() else Redeem.CARD,
                conditions=None,
            )
            try:
                sub = LexborHTMLParser(self.client.text(href))
                body = sub.css_first("main") or sub.body
                text = " ".join(body.text(separator=" ").split()) if body else ""
                c.conditions = _summary(text, title)
                vf, vt = _dates_in(text, self.today)
                c.valid_from, c.valid_to = vf, vt
                c.personal = False
            except Exception as e:
                self.notes.append(f"ugodnost {href}: {e}")
            out.append(c)
        return out

    def catalogs(self) -> list[dict]:
        return parse_catalogs(self.client.text(SITE + "/katalogi/"), self.today)


def _mdate(s: str | None, start: bool) -> date | None:
    if not s or len(s) < 8:
        return None
    try:
        dt = datetime.strptime(s[:14].ljust(14, "0"), "%Y%m%d%H%M%S")
    except ValueError:
        return None
    d = dt.date()
    # Mercator zapiše začetek kot "dan pred ob 23:26"
    if start and dt.hour >= 20:
        d += timedelta(days=1)
    return d


def _ppu(value, base: str | None) -> tuple[float, str] | None:
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    if v <= 0 or not base:
        return None
    m = re.match(r"(\d+(?:[.,]\d+)?)?\s*(kg|g|l|ml|kos)", base.strip().lower())
    if not m:
        return None
    q = float(m.group(1).replace(",", ".")) if m.group(1) else 1.0
    unit = m.group(2)
    factor = {"kg": 1, "g": 0.001, "l": 1, "ml": 0.001, "kos": 1}[unit]
    return (v / (q * factor), {"g": "kg", "ml": "l"}.get(unit, unit))


def to_offers(p: dict, today: date, now: datetime) -> list[Offer]:
    d = p.get("data") or {}
    name = (d.get("name") or "").strip()
    if not name:
        return []
    try:
        current = float(d.get("current_price") or 0)
        normal = float(d.get("normal_price") or 0)
    except ValueError:
        return []
    if current <= 0:
        return []
    discounts = d.get("discounts") or []
    texts = [x.get("hover_text") or "" for x in discounts]
    pika = any(x.get("group_type") == "pika_discount" or _PIKA.search(x.get("hover_text") or "") for x in discounts)
    multi = next((m for m in (_MULTI.search(t) for t in texts) if m), None)
    vfs = [_mdate(x.get("valid_from"), True) for x in discounts if x.get("valid_from")]
    vts = [_mdate(x.get("valid_to"), False) for x in discounts if x.get("valid_to")]
    vf = max([v for v in vfs if v], default=None)
    vt = min([v for v in vts if v and v >= today], default=None)
    if vt is None:
        vf = None if (vf and vf > today + timedelta(days=60)) else vf

    pack = extract_pack(name)
    if re.search(r"cena za kg", name, re.I):
        pack = "za kg"
    unit = _ppu(d.get("price_per_unit"), d.get("price_per_unit_base")) or compute_unit_price(current, pack, name)
    gtins = d.get("gtins") or []
    base = dict(
        chain="mercator",
        name=re.sub(r",\s*cena za kg$", "", name, flags=re.I),
        brand=(d.get("brand_name") or "").title() or None,
        pack_size=pack,
        valid_from=vf,
        valid_to=vt,
        source_url=urljoin(SHOP, p.get("url") or ""),
        image_url=p.get("mainImageSrc"),
        ean=gtins[0].get("gtin") if gtins else None,
        source_id=str(d.get("cinv") or d.get("code") or ""),
        source_category="/".join(x for x in (d.get("category1"), d.get("category2"), d.get("category3")) if x),
        fetched_at=now,
    )
    out: list[Offer] = []
    if normal > current:
        cond, ctext = (Condition.LOYALTY_CARD, "Pika kartica") if pika else (Condition.NONE, None)
        label = next((t for t in texts if t and not _MULTI.search(t)), None)
        out.append(
            Offer(
                price=current,
                regular_price=normal,
                unit_price=unit[0] if unit else None,
                unit=unit[1] if unit else None,
                condition=cond,
                condition_text=ctext if cond != Condition.NONE else (label if label not in (None, "Ugodno") else None),
                **base,
            )
        )
    if multi:
        qty, pct = int(multi.group(1)), int(multi.group(2))
        price = round(current * (1 - pct / 100), 2)
        out.append(
            Offer(
                price=price,
                regular_price=current,
                discount_pct=pct,
                unit_price=unit[0] * (1 - pct / 100) if unit else None,
                unit=unit[1] if unit else None,
                condition=Condition.MULTI_BUY,
                condition_text=f"ob nakupu {qty} ali več kosov",
                **base,
            )
        )
    return out


def parse_promotions(html: str) -> list[tuple[str, str]]:
    tree = LexborHTMLParser(html)
    seen: dict[str, str] = {}
    for a in tree.css('a[href*="akcije-in-ugodnosti/"]'):
        href = urljoin(SITE, a.attributes.get("href") or "")
        if href.rstrip("/").endswith("akcije-in-ugodnosti"):
            continue
        txt = " ".join(a.text(separator=" ", strip=True).split())
        if txt and txt.lower() not in ("več", "nakupujte") and href not in seen:
            seen[href] = txt[:1] + txt[1:].lower() if txt.isupper() else txt
    return [(t, h) for h, t in seen.items()]


def parse_catalogs(html: str, today: date) -> list[dict]:
    tree = LexborHTMLParser(html)
    out = []
    seen = set()
    for a in tree.css('a[href*="/katalogi/"]'):
        href = urljoin(SITE, a.attributes.get("href") or "")
        title = " ".join(a.text(separator=" ", strip=True).split())
        if not title or title.lower().startswith("oglej") or title == "Katalogi" or href in seen:
            continue
        seen.add(href)
        vf, vt = parse_date_range(title, today)
        out.append({"chain": "mercator", "title": title, "url": href,
                    "validFrom": vf.isoformat() if vf else None, "validTo": vt.isoformat() if vt else None})
    for a in tree.css('a[href$=".pdf"]'):
        href = urljoin(SITE, a.attributes.get("href") or "")
        m = re.search(r"(\d{4}-\d{2}-\d{2})-Redni-katalog", href)
        if m and href not in seen:
            seen.add(href)
            out.append({"chain": "mercator", "title": f"Redni katalog (PDF) od {m.group(1)}", "url": href,
                        "validFrom": m.group(1), "validTo": None})
    return out


def _summary(text: str, title: str, limit: int = 400) -> str | None:
    i = text.lower().find(title.lower()[:20])
    chunk = text[i: i + limit] if i >= 0 else text[:limit]
    return chunk.strip() or None


def _dates_in(text: str, today: date) -> tuple[date | None, date | None]:
    m = re.search(r"(od\s+)?\d{1,2}\.\s*\d{1,2}\.(\s*\d{4})?\s*(do|-|–)\s*\d{1,2}\.\s*\d{1,2}\.(\s*\d{4})?", text)
    return parse_date_range(m.group(0), today) if m else (None, None)
