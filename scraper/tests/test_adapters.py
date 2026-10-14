"""Testi adapterjev na shranjenih vzorcih strani (tests/fixtures, zajeto 14. 10. 2026)."""

import json
from datetime import date

import pytest

from akcije.adapters import ADAPTERS, eurospin, hofer, lidl, mercator, obi, spar, tus
from akcije.models import Condition

from .conftest import fixture_text


def test_registry_has_all_chains():
    assert {a.chain for a in ADAPTERS} == {"mercator", "spar", "tus", "hofer", "lidl", "eurospin", "obi"}


# ---------------------------------------------------------------- Eurospin
def test_eurospin(today, now):
    offers = eurospin.parse(fixture_text("eurospin_akcije.html"), today, now)
    assert len(offers) == 342
    k = next(o for o in offers if o.name == "Kranjska klobasa")
    assert (k.price, k.regular_price, k.pack_size) == (4.49, 5.99, "460 g")
    assert k.unit == "kg" and k.unit_price == pytest.approx(9.77)
    assert (k.valid_from, k.valid_to) == (date(2026, 10, 8), date(2026, 10, 14))
    assert {o.valid_from for o in offers} == {date(2026, 10, 8), date(2026, 10, 15)}
    m = next(o for o in offers if o.name == "Mocarela")
    assert m.brand == "Land" and m.pack_size == "4 x 125 g"
    assert sum(1 for o in offers if o.regular_price) > 200


# ---------------------------------------------------------------- Tuš
def test_tus_listing():
    html = fixture_text("tus_katalog_p1.html")
    assert tus.max_page(html) == 15
    items = tus.parse_listing(html)
    assert len(items) == 36
    first = items[0]
    assert first["ean"] == "5411188141488"
    assert (first["price"], first["regular"], first["discount"]) == (2.09, 2.59, 19)
    assert first["tag"] == "akcija-3a" and first["cat"] == "Shramba"


def test_tus_klub_and_validity(today, now):
    items = tus.parse_listing(fixture_text("tus_klub_p1.html"))
    assert len(items) == 36 and all(i["tag"] == "akcija-1tk" for i in items)
    vf, vt = tus.parse_validity(fixture_text("tus_izdelek.html"), today)
    assert (vf, vt) == (date(2026, 10, 14), date(2026, 10, 27))
    o = tus.to_offer(items[0], Condition.LOYALTY_CARD, "Tuš klub", vf, vt, "x", now)
    assert o.condition == Condition.LOYALTY_CARD and o.pack_size == "130 g" and o.unit == "kg"


def test_tus_coupons(today):
    coupons = tus.parse_coupons(fixture_text("tus_kuponi.html"), today)
    assert len(coupons) == 4
    assert all(c.image_url and c.back_image_url for c in coupons)
    assert "1 kupon za 1 nakup" in coupons[0].conditions


# ---------------------------------------------------------------- Hofer
def test_hofer_index():
    dates, themes = hofer.parse_index(fixture_text("hofer_ponudba.html"))
    assert dates == ["2026-10-08", "2026-10-12", "2026-10-15", "2026-10-19"]
    assert "Shramba" in themes["2026-10-12"] and "Kuhinja" in themes["2026-10-15"]


def test_hofer_page(today, now):
    offers = hofer.parse_page(fixture_text("hofer_2026-10-12_shramba.html"), today, now, "Shramba")
    assert len(offers) == 3
    s = next(o for o in offers if o.name == "Jadranske sardine")
    assert (s.price, s.pack_size, s.brand) == (1.36, "108 g", "SIMPEX")
    assert s.unit_price == pytest.approx(12.59) and s.unit == "kg"
    assert s.valid_from == date(2026, 10, 12) and s.valid_to is None and s.regular_price is None
    assert len(hofer.parse_page(fixture_text("hofer_2026-10-15.html"), today, now, None)) == 54


# ---------------------------------------------------------------- Mercator
def test_mercator_offers(today, now):
    data = json.loads(fixture_text("mercator_getproducts.json"))
    offers = [o for p in data["products"] for o in mercator.to_offers(p, today, now)]
    assert len(offers) >= 50
    maslo = next(o for o in offers if o.name.startswith("Ljutomersko maslo"))
    assert maslo.condition == Condition.LOYALTY_CARD and maslo.condition_text == "Pika kartica"
    assert (maslo.price, maslo.regular_price) == (3.19, 4.59)
    smetana = next(o for o in offers if o.name.startswith("Sladka smetana, Mu"))
    assert smetana.condition == Condition.MULTI_BUY and smetana.discount_pct == 20
    assert smetana.price == pytest.approx(1.99)
    kivi = next(o for o in offers if o.name == "Kivi")
    assert kivi.pack_size == "za kg" and kivi.unit == "kg" and kivi.valid_to == date(2026, 10, 23)
    assert all(o.ean is None or o.ean.isdigit() for o in offers)


def test_mercator_catalogs_and_promotions(today):
    cats = mercator.parse_catalogs(fixture_text("mercator_katalogi.html"), today)
    titles = [c["title"] for c in cats]
    assert "Redni katalog od 15. 10. do 21. 10. 2026" in titles
    assert any(c["url"].endswith("2026-10-15-Redni-katalog-200x275mm-web.pdf") for c in cats)
    promos = dict(mercator.parse_promotions(fixture_text("mercator_akcije.html")))
    assert "Hit dneva" in promos


# ---------------------------------------------------------------- Lidl
def test_lidl_pages():
    pages = lidl.offer_pages(fixture_text("lidl_home.html"))
    assert "/c/super-ponudba-od-cetrtka/a10104884" in pages
    assert "/c/lidl-plus-super-bonus/s10030494" in pages
    assert not any("s10019133" in p for p in pages)


def test_lidl_offers(today, now):
    offers = lidl.parse_page(fixture_text("lidl_super_ponudba_cetrtek.html"), "u", today, now)
    assert len(offers) >= 35
    kivi = next(o for o in offers if o.name == "Kivi zlati")
    assert kivi.condition == Condition.APP and kivi.condition_text == "Lidl Plus"
    assert (kivi.price, kivi.regular_price) == (0.49, 0.69)
    bedra = next(o for o in offers if o.name == "Piščančja bedra")
    assert bedra.brand == "Naše Nam Paše" and bedra.unit_price == pytest.approx(3.78)
    assert (bedra.valid_from, bedra.valid_to) == (date(2026, 10, 15), date(2026, 10, 21))


# ---------------------------------------------------------------- Spar
def test_spar(today, now):
    html = fixture_text("spar_iz_letaka_p1.html")
    assert spar.pagination(html) == (1, 12, 579)
    offers = spar.parse_page(html, today, now)
    assert len(offers) == 50
    c = next(o for o in offers if o.name.startswith("Cockta limeta"))
    assert c.name == "Cockta limeta, 1,5 l"
    assert (c.price, c.regular_price) == (1.2, 1.85)
    assert (c.valid_from, c.valid_to) == (date(2026, 10, 14), date(2026, 10, 20))
    r = next(o for o in offers if o.name.startswith("Čokoladna rezina"))
    assert r.condition_text == "Multipak" and r.unit == "kg"


def test_spar_mojibake():
    assert spar.fix_mojibake("TakojĹĄnji popust") == "Takojšnji popust"


# ---------------------------------------------------------------- OBI
def test_obi(now):
    html = fixture_text("obi_akcija.html")
    assert obi.page_count(html) == 15
    offers = obi.parse_page(html, now)
    assert len(offers) == 20
    v = next(o for o in offers if "vrtalni vijačnik" in o.name)
    assert (v.price, v.regular_price) == (49.99, 89.99)
    assert v.discount_pct is None  # izračuna se v finalize()
    v.finalize()
    assert v.discount_pct == 44
