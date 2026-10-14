"""Eurospin: strežniško generiran HTML z vsemi akcijami tekočega in naslednjega tedna."""

from __future__ import annotations

from datetime import date, datetime

from selectolax.lexbor import LexborHTMLParser

from ..models import Offer
from ..units import compute_unit_price, parse_date_range, parse_number, parse_unit_price_text
from .base import Adapter

URL = "https://www.eurospin.si/akcije/"


class EurospinAdapter(Adapter):
    chain = "eurospin"
    source = "eurospin.si/akcije"
    url = URL

    def fetch(self) -> list[Offer]:
        html = self.client.text(URL)
        return parse(html, self.today, self.now)


def parse(html: str, today: date, now: datetime) -> list[Offer]:
    tree = LexborHTMLParser(html)
    out: list[Offer] = []
    for item in tree.css("a.sn_promo_grid_item"):
        title = _text(item, ".i_title")
        if not title:
            continue
        brand = _text(item, ".i_brand") or None
        price_node = item.css_first(".i_price")
        action = parse_number(_text(price_node, "[itemprop=price]")) if price_node else None
        if action is None:
            continue
        # Redna cena je golo besedilo pred <meta>/<span> v .i_price
        regular = None
        if price_node is not None:
            direct = "".join(
                (n.text_content or "") for n in price_node.iter(include_text=True) if n.tag == "-text"
            )
            regular = parse_number(direct) if direct.strip() else None
            if regular is not None and regular <= action:
                regular = None
        info = _text(item, ".i_price_info")
        pack = info.split(" - ")[0].strip() if info else None
        if pack and pack.lower().startswith("za "):
            pack = None
        unit = parse_unit_price_text(info)
        if unit is None:
            unit = compute_unit_price(action, pack, title)
        dates = _text(item, ".date_current_promo")
        vf, vt = parse_date_range(dates, today) if dates else (None, None)
        img = item.css_first("img.i_image")
        desc = _text(item, ".i_descrizione")
        out.append(
            Offer(
                chain="eurospin",
                name=_title(title),
                brand=_title(brand) if brand else None,
                price=action,
                regular_price=regular,
                pack_size=pack,
                unit_price=unit[0] if unit else None,
                unit=unit[1] if unit else None,
                valid_from=vf,
                valid_to=vt,
                source_url=URL,
                image_url=img.attributes.get("src") if img else None,
                fetched_at=now,
                source_id=(img.attributes.get("src") or "").rsplit("/", 1)[-1].split(".")[0] or None if img else None,
                condition_text=desc or None,
            )
        )
    return out


def _text(node, sel: str) -> str:
    if node is None:
        return ""
    n = node.css_first(sel)
    return " ".join(n.text(strip=True).split()) if n else ""


def _title(s: str) -> str:
    """'KRANJSKA KLOBASA' -> 'Kranjska klobasa' (Eurospin piše vse z velikimi črkami)."""
    if s and s.isupper():
        return s[:1] + s[1:].lower()
    return s
