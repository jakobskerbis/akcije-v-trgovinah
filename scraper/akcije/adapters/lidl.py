"""Lidl: strani "Super ponudba od …" in "Lidl Plus super bonus".

Vsak izdelek ima v HTML atributu data-grid-data celoten JSON (cena, stara cena,
% popusta, cena na enoto, cena z Lidl Plus, datumi v trgovini).
"""

from __future__ import annotations

import html as htmlmod
import json
import re
from datetime import date, datetime
from urllib.parse import urljoin

from ..models import Condition, Offer
from ..units import (
    compute_unit_price,
    local_date_from_epoch,
    local_date_from_iso,
    parse_date_range,
    parse_unit_price_text,
)
from .base import Adapter

BASE = "https://www.lidl.si"
_PAGE_LINK = re.compile(r'href="((?:https://www\.lidl\.si)?/c/(?:[a-z0-9-]*ponudba[a-z0-9-]*|lidl-plus[a-z0-9-]*)/[as]\d+)"')
FALLBACK_PAGES = ["/c/lidl-plus-super-bonus/s10030494"]
REGION = "1"


class LidlAdapter(Adapter):
    chain = "lidl"
    source = "lidl.si super ponudba"
    url = BASE

    def fetch(self) -> list[Offer]:
        home = self.client.text(BASE + "/")
        pages = offer_pages(home) or FALLBACK_PAGES
        out: dict[str, Offer] = {}
        for path in pages:
            url = urljoin(BASE, path)
            try:
                page = self.client.text(url)
            except Exception as e:
                self.notes.append(f"{path}: {e}")
                continue
            for o in parse_page(page, url, self.today, self.now):
                out.setdefault(f"{o.source_id}|{o.condition}|{o.valid_from}", o)
        return list(out.values())


def offer_pages(home_html: str) -> list[str]:
    seen: list[str] = []
    for href in _PAGE_LINK.findall(home_html):
        path = href.replace(BASE, "")
        if path not in seen and "/s10019133" not in path:  # spletni katalog (listanje), brez izdelkov
            seen.append(path)
    return seen


def grid_items(page_html: str) -> list[dict]:
    items = []
    for raw in re.findall(r'data-grid-data="([^"]*)"', page_html):
        try:
            items.append(json.loads(htmlmod.unescape(raw)))
        except json.JSONDecodeError:
            continue
    return items


_BRAND_PREFIX = re.compile(r"^((?:[A-ZČŠŽĆĐÄÖÜ0-9&'.\-]{2,}\s+)+)(?=[A-ZČŠŽĆĐ][a-zčšžćđ])")


def split_brand(title: str, brand: str | None) -> tuple[str, str | None]:
    t = title.strip().lstrip("- ").strip()
    if brand and t.upper().startswith(brand.upper() + " "):
        return t[len(brand):].strip(), brand
    m = _BRAND_PREFIX.match(t)
    if m:
        return t[m.end():].strip(), m.group(1).strip()
    return t, brand


def parse_page(page_html: str, url: str, today: date, now: datetime) -> list[Offer]:
    out = []
    for d in grid_items(page_html):
        title = d.get("fullTitle") or d.get("title")
        if not title:
            continue
        brand_obj = d.get("brand") or {}
        bname = brand_obj.get("name") if isinstance(brand_obj, dict) else None
        name, brand = split_brand(title, bname if bname and bname.strip("- ") else None)
        start = local_date_from_epoch(d.get("storeStartDate"))
        end = local_date_from_epoch(d.get("storeEndDate"))
        if not start:
            badges = ((d.get("stockAvailability") or {}).get("badgeInfo") or {}).get("badges") or []
            if badges:
                start, end = parse_date_range(badges[0].get("text", ""), today)
        hint = ((d.get("keyfacts") or {}).get("wonCategoryPrimary")) or d.get("category")
        common = dict(
            chain="lidl",
            name=name,
            brand=brand.title() if brand and brand.isupper() else brand,
            valid_from=start,
            valid_to=end,
            source_url=urljoin(BASE, d.get("canonicalUrl") or ""),
            image_url=d.get("image"),
            source_id=str(d.get("productId") or d.get("erpNumber") or ""),
            source_category=hint,
            fetched_at=now,
        )
        p = d.get("price") or {}
        normal_price = p.get("price")
        if normal_price:
            out.append(_offer(p, common, Condition.NONE, None))
        lp = _lidl_plus(d)
        if lp and lp.get("price") and (not normal_price or lp["price"] < normal_price):
            lp_common = dict(common)
            if lp.get("endDate"):
                lp_common["valid_to"] = local_date_from_iso(lp["endDate"]) or common["valid_to"]
            out.append(_offer(lp, lp_common, Condition.APP, "Lidl Plus", fallback_regular=normal_price))
    return out


def _lidl_plus(d: dict) -> dict | None:
    region = (d.get("regionsPrices") or {}).get(REGION) or {}
    cur = (region.get("currentLidlPlusPrice") or {}).get("price")
    if cur:
        return cur
    lst = d.get("lidlPlus") or []
    return (lst[0] or {}).get("price") if lst else None


def _offer(p: dict, common: dict, cond: Condition, cond_text: str | None, fallback_regular: float | None = None) -> Offer:
    price = float(p["price"])
    disc = p.get("discount") or {}
    regular = p.get("oldPrice") or disc.get("deletedPrice") or fallback_regular
    regular = float(regular) if regular and float(regular) > price else None
    pack = (p.get("packaging") or {}).get("text")
    base_txt = (p.get("basePrice") or {}).get("text")
    unit = parse_unit_price_text(base_txt) or compute_unit_price(price, pack, common["name"])
    return Offer(
        price=price,
        regular_price=regular,
        discount_pct=disc.get("percentageDiscount") if regular else None,
        pack_size=pack if pack and pack.lower() not in ("za kg",) else ("za kg" if pack else None),
        unit_price=unit[0] if unit else None,
        unit=unit[1] if unit else None,
        condition=cond,
        condition_text=cond_text,
        **common,
    )
