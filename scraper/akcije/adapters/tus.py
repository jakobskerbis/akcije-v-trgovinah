"""Tuš: akcije iz kataloga (brez kartice), Tuš klub -50 % (s kartico) in tedenski kuponi.

Seznami ne vsebujejo veljavnosti akcije; ta je samo na strani izdelka. Zato za
vsako akcijsko skupino (oznaka "product_tag_akcija-…") preberemo eno stran izdelka.
"""

from __future__ import annotations

import re
from datetime import date, datetime

from selectolax.lexbor import LexborHTMLParser

from ..models import Condition, Coupon, Offer, Redeem
from ..units import compute_unit_price, extract_pack, parse_date_range, parse_number
from .base import Adapter

BASE = "https://www.tus.si"
LISTINGS = [
    # (pot, pogoj, opis pogoja)
    ("/aktualno/akcijska-ponudba/aktualno-iz-kataloga/", Condition.NONE, None),
    ("/aktualno/akcijska-ponudba/tus-klub-50/", Condition.LOYALTY_CARD, "Tuš klub"),
]
COUPONS_URL = BASE + "/katalog/tedenski-kuponi/"
MAX_PAGES = 30
MAX_VALIDITY_FETCHES = 25

# Tuševe glavne kategorije -> berljiv namig za razvrščanje
CAT_HINT = {
    "alkoholne-pijace": "Alkoholne pijače",
    "brezalkoholne-pijace": "Brezalkoholne pijače",
    "cvetje-in-vrt": "Cvetje in vrt",
    "dojencki-in-otroci": "Dojenčki in otroci",
    "dom": "Dom",
    "hlajeni-in-mlecni-izdelki": "Hlajeni in mlečni izdelki",
    "kruh-in-pekovski-izdelki": "Kruh in pekovski izdelki",
    "male-zivali": "Male živali",
    "meso-delikatesa-in-ribe": "Meso, delikatesa in ribe",
    "osebna-nega": "Osebna nega",
    "sadje-in-zelenjava": "Sadje in zelenjava",
    "shramba": "Shramba",
    "sladko-in-slano": "Sladko in slano",
    "zamrznjeno": "Zamrznjeno",
}


class TusAdapter(Adapter):
    chain = "tus"
    source = "tus.si akcijska ponudba"
    url = BASE + LISTINGS[0][0]

    def fetch(self) -> list[Offer]:
        offers: list[Offer] = []
        validity_cache: dict[str, tuple[date | None, date | None]] = {}
        fetches = 0
        for path, cond, cond_text in LISTINGS:
            url = BASE + path
            first = self.client.text(url)
            pages = [first]
            last = min(max_page(first), MAX_PAGES)
            for n in range(2, last + 1):
                pages.append(self.client.text(f"{url}page/{n}/"))
            items = [it for html in pages for it in parse_listing(html)]
            for it in items:
                tag = it["tag"] or "?"
                if tag not in validity_cache and fetches < MAX_VALIDITY_FETCHES:
                    fetches += 1
                    try:
                        validity_cache[tag] = parse_validity(self.client.text(it["url"]), self.today)
                    except Exception as e:  # stran izdelka ni ključna
                        self.notes.append(f"veljavnost {tag}: {e}")
                        validity_cache[tag] = (None, None)
                vf, vt = validity_cache.get(tag, (None, None))
                offers.append(to_offer(it, cond, cond_text, vf, vt, url, self.now))
        return offers

    def coupons(self) -> list[Coupon]:
        html = self.client.text(COUPONS_URL)
        return parse_coupons(html, self.today)


def max_page(html: str) -> int:
    nums = [int(n) for n in re.findall(r"/page/(\d+)/", html)]
    return max(nums) if nums else 1


def parse_listing(html: str) -> list[dict]:
    tree = LexborHTMLParser(html)
    items = []
    for li in tree.css("ul.products > li.product"):
        card = li.css_first(".card-product")
        if card is None:
            continue
        a = card.css_first("h3 a")
        if a is None:
            continue
        classes = li.attributes.get("class") or ""
        cat = re.search(r"product_cat_m-([a-z0-9-]+)", classes)
        tag = re.search(r"product_tag_(akcija-[a-z0-9-]+)", classes)
        brand = re.search(r"pa_znamka-([a-z0-9-]+)", classes)
        price = _num(card, "span.price")
        regular = None
        reg = card.css_first(".price-regular-mobile s") or card.css_first(".price-regular label")
        if reg is not None:
            regular = parse_number(reg.text())
        disc = card.css_first("span.discount span")
        img = card.css_first("noscript img") or card.css_first("img")
        img_url = None
        if img is not None:
            img_url = img.attributes.get("src")
            if not img_url or img_url.startswith("data:"):
                img_url = img.attributes.get("data-src")
        if price is None:
            continue
        items.append(
            {
                "name": " ".join(a.text(strip=True).split()),
                "url": a.attributes.get("href"),
                "ean": card.attributes.get("data-product-ean") or None,
                "price": price,
                "regular": regular,
                "discount": int(disc.text(strip=True)) if disc and disc.text(strip=True).isdigit() else None,
                "image": img_url,
                "cat": CAT_HINT.get(cat.group(1), cat.group(1)) if cat else None,
                "tag": tag.group(1) if tag else None,
                "brand": brand.group(1).replace("-", " ").upper() if brand else None,
            }
        )
    return items


def parse_validity(html: str, today: date) -> tuple[date | None, date | None]:
    m = re.search(r"Veljavnost akcije:\s*</b>\s*([^<]+)", html)
    if not m:
        return None, None
    return parse_date_range(m.group(1), today)


def to_offer(it: dict, cond: Condition, cond_text: str | None, vf, vt, listing_url: str, now: datetime) -> Offer:
    name = it["name"]
    pack = extract_pack(name)
    unit = compute_unit_price(it["price"], pack, name)
    return Offer(
        chain="tus",
        name=name,
        brand=it["brand"],
        price=it["price"],
        regular_price=it["regular"] if it["regular"] and it["regular"] > it["price"] else None,
        discount_pct=it["discount"],
        pack_size=pack,
        unit_price=unit[0] if unit else None,
        unit=unit[1] if unit else None,
        valid_from=vf,
        valid_to=vt,
        condition=cond,
        condition_text=cond_text,
        source_url=it["url"] or listing_url,
        image_url=it["image"],
        ean=it["ean"],
        source_id=it["ean"] or it["url"],
        source_category=it["cat"],
        fetched_at=now,
    )


def parse_coupons(html: str, today: date) -> list[Coupon]:
    tree = LexborHTMLParser(html)
    text = " ".join(tree.body.text(separator=" ").split()) if tree.body else ""
    cond = None
    m = re.search(r"(Unovčite lahko 1 kupon.*?Kupon ni unovčljiv v spletnem supermarketu[^.]*\.)", text)
    if m:
        cond = m.group(1)
    coupons: list[Coupon] = []
    seen = set()
    for img in tree.css("img"):
        src = img.attributes.get("src") or ""
        if "/api/images/coupon/" not in src or "front-" not in src or src in seen:
            continue
        seen.add(src)
        key = src.rsplit("front-", 1)[-1]
        back = next(
            (
                i.attributes.get("src")
                for i in tree.css("img")
                if key in (i.attributes.get("src") or "") and "back-" in (i.attributes.get("src") or "")
            ),
            None,
        )
        c = Coupon(
            chain="tus",
            title=f"Tedenski kupon Tuš klub #{len(coupons) + 1}",
            source_url=COUPONS_URL,
            how_to_redeem=Redeem.CARD,
            discount=None,
            conditions=cond,
            image_url=src,
            personal=False,
        )
        c.back_image_url = back
        coupons.append(c)
    return coupons


def _num(node, sel: str) -> float | None:
    n = node.css_first(sel)
    return parse_number(n.text()) if n else None
