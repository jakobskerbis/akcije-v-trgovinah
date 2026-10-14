"""OBI: akcijski izdelki za dom, vrt in DIY (obi.si/c/akcija).

Magento seznam s 20/48 izdelki na stran; stara in akcijska cena sta v
atributih data-price-amount. Veljavnost na seznamu ni navedena.
"""

from __future__ import annotations

import re
from datetime import datetime

from selectolax.lexbor import LexborHTMLParser

from ..models import Offer
from ..units import parse_unit_price_text
from .base import Adapter

BASE = "https://www.obi.si"
# robots.txt prepoveduje ?product_list_limit=, zato privzetih 20 na stran
LIST = BASE + "/c/akcija"
MAX_PAGES = 25


class ObiAdapter(Adapter):
    chain = "obi"
    source = "obi.si/c/akcija"
    url = BASE + "/c/akcija"
    default_section = "dom"

    def fetch(self) -> list[Offer]:
        first = self.client.text(LIST)
        pages = [first]
        for n in range(2, min(page_count(first), MAX_PAGES) + 1):
            pages.append(self.client.text(f"{LIST}?p={n}"))
        out: dict[str, Offer] = {}
        for html in pages:
            for o in parse_page(html, self.now):
                out.setdefault(o.source_id or o.name, o)
        return list(out.values())


def page_count(html: str) -> int:
    m = re.search(r"Stran\s*\d+\s*</strong>\s*od\s*(\d+)", html)
    return int(m.group(1)) if m else 1


def parse_page(html: str, now: datetime) -> list[Offer]:
    tree = LexborHTMLParser(html)
    out = []
    for item in tree.css("[data-product-sku]"):
        a = item.css_first("a[href]")
        title_node = item.css_first(".card-title")
        if a is None or title_node is None:
            continue
        name = " ".join(title_node.text(strip=True).split())
        fin = item.css_first('[data-price-type="finalPrice"]')
        old = item.css_first('[data-price-type="oldPrice"]')
        if fin is None:
            continue
        try:
            price = float(fin.attributes.get("data-price-amount"))
        except (TypeError, ValueError):
            continue
        regular = None
        if old is not None:
            try:
                regular = float(old.attributes.get("data-price-amount"))
            except (TypeError, ValueError):
                regular = None
        unit_node = item.css_first(".price-per-unit")
        unit = parse_unit_price_text(unit_node.text(strip=True)) if unit_node else None
        # pri izdelkih za dom so številke v imenu pogosto mere/nosilnost, zato
        # ceno na enoto vzamemo samo, če jo navede OBI
        pack = None
        img = item.css_first("img")
        brand = None
        m = re.match(r"^(OBI|Einhell|Bosch|Makita|Gardena|Kärcher|Radial|LUX|CMI|Toom)\b", name)
        if m:
            brand = m.group(1)
        out.append(
            Offer(
                chain="obi",
                name=name,
                brand=brand,
                price=price,
                regular_price=regular if regular and regular > price else None,
                pack_size=pack,
                unit_price=unit[0] if unit else None,
                unit=unit[1] if unit else None,
                source_url=a.attributes.get("href") or BASE,
                image_url=img.attributes.get("src") if img else None,
                source_id=item.attributes.get("data-product-sku"),
                fetched_at=now,
            )
        )
    return out
