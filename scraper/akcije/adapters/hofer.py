"""HOFER: posebna ponudba po datumih (/posebna-ponudba/LLLL-MM-DD).

Prikazana je samo akcijska cena (brez redne), zato popusta ne moremo izračunati.
Teme (?theme=Shramba, Kuhinja …) uporabimo kot namig za razvrščanje.
Pozor: tema "Kuhinja" so kuhinjski pripomočki, ne hrana.
Sveža ponudba (letaki.hofer.si) je samo v slikah in je ne zajemamo.
"""

from __future__ import annotations

import re
from datetime import date, datetime
from urllib.parse import parse_qs, urljoin, urlsplit

from selectolax.lexbor import LexborHTMLParser

from ..models import Offer
from ..units import compute_unit_price, parse_date_range, parse_number, parse_unit_price_text
from .base import Adapter

BASE = "https://www.hofer.si"
INDEX = BASE + "/sl/ponudba.html"


class HoferAdapter(Adapter):
    chain = "hofer"
    source = "hofer.si posebna ponudba"
    url = INDEX
    default_section = "dom"

    def fetch(self) -> list[Offer]:
        index = self.client.text(INDEX)
        dates, themes = parse_index(index)
        offers: dict[str, Offer] = {}
        for d in dates:
            # najprej teme (namig), nato celotna stran za datum (izdelki brez teme)
            for theme in themes.get(d, []):
                url = f"{BASE}/posebna-ponudba/{d}?theme={theme}"
                for o in parse_page(self.client.text(url), self.today, self.now, theme):
                    offers.setdefault(o.source_id or o.name, o)
            url = f"{BASE}/posebna-ponudba/{d}"
            for o in parse_page(self.client.text(url), self.today, self.now, None):
                offers.setdefault(o.source_id or o.name, o)
        return list(offers.values())


def parse_index(html: str) -> tuple[list[str], dict[str, list[str]]]:
    dates: list[str] = []
    themes: dict[str, list[str]] = {}
    for href in re.findall(r'href="([^"]*/posebna-ponudba/\d{4}-\d{2}-\d{2}[^"]*)"', html):
        href = href.replace("&amp;", "&")
        parts = urlsplit(href)
        d = parts.path.rsplit("/", 1)[-1]
        if d not in dates:
            dates.append(d)
        q = parse_qs(parts.query).get("theme")
        if q and q[0] not in themes.setdefault(d, []):
            themes[d].append(q[0])
    return sorted(dates), themes


def parse_page(html: str, today: date, now: datetime, theme: str | None) -> list[Offer]:
    tree = LexborHTMLParser(html)
    out = []
    for tile in tree.css('[data-test="product-tile"]'):
        name = _t(tile, '[data-test="product-tile__name"]')
        price = parse_number(_t(tile, '[data-test="product-tile__price"] .base-price__regular'))
        if not name or price is None:
            continue
        brand = _t(tile, '[data-test="product-tile__brandname"]') or None
        pack = _t(tile, '[data-test="product-tile__unit-of-measurement"]') or None
        comp = _t(tile, '[data-test="product-tile__comparison-price"]')
        unit = parse_unit_price_text(comp) or compute_unit_price(price, pack, name)
        label = _t(tile, '[data-test="product-tile__on-sale-label"]')
        vf, _ = parse_date_range(label, today) if label else (None, None)
        a = tile.css_first("a")
        href = urljoin(BASE, a.attributes.get("href")) if a else BASE
        img = tile.css_first("img")
        sid = re.search(r"(\d{6,})$", href)
        out.append(
            Offer(
                chain="hofer",
                name=name,
                brand=brand if brand and brand.upper() != "NO BRAND" else None,
                price=price,
                pack_size=pack,
                unit_price=unit[0] if unit else None,
                unit=unit[1] if unit else None,
                valid_from=vf,
                valid_to=None,  # "do razprodaje zalog"
                source_url=href,
                image_url=img.attributes.get("src") if img else None,
                source_id=sid.group(1).lstrip("0") if sid else href,
                source_category=theme,
                fetched_at=now,
            )
        )
    return out


def _t(node, sel: str) -> str:
    n = node.css_first(sel)
    return " ".join(n.text(strip=True).split()) if n else ""
