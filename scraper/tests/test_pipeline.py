import json
from datetime import date, datetime, timedelta

from akcije.models import Condition, Coupon, Offer, Redeem, SourceResult
from akcije.pipeline import RunResult, build, carry_over_failed, dedupe, mark_best_unit_prices, update_history
from akcije.units import TZ

NOW = datetime(2026, 10, 14, 9, 0, tzinfo=TZ)


def mk(chain, name, price, unit_price=None, kind=None, cond=Condition.NONE, sid=None, regular=None):
    o = Offer(chain=chain, name=name, price=price, source_url="u", fetched_at=NOW, unit_price=unit_price,
              unit="kg" if unit_price else None, condition=cond, source_id=sid or name, regular_price=regular,
              valid_from=date(2026, 10, 14), valid_to=date(2026, 10, 20), category="perutnina")
    o.kind = kind
    o.finalize()
    return o


def test_dedupe_keeps_cheapest():
    a = mk("lidl", "Piščančja bedra", 2.0, sid="1")
    b = mk("lidl", "Piščančja bedra", 1.8, sid="1")
    c = mk("lidl", "Piščančja bedra", 1.5, sid="1", cond=Condition.APP)
    out = dedupe([a, b, c])
    assert sorted(o.price for o in out) == [1.5, 1.8]


def test_best_unit_price_needs_two_chains():
    a = mk("lidl", "Piščančje prsi", 5.0, 4.99, "piscancje-prsi")
    b = mk("mercator", "Piščančja prsa", 6.0, 6.99, "piscancje-prsi")
    c = mk("tus", "Piščančje prsi", 6.0, 7.49, "piscancje-prsi")
    lone = mk("hofer", "Cel piščanec", 3.0, 3.0, "piscanec-cel")
    mark_best_unit_prices([a, b, c, lone], date(2026, 10, 14))
    assert a.best_unit_price and not b.best_unit_price and not c.best_unit_price
    assert not lone.best_unit_price


def test_discount_computed():
    o = mk("tus", "X", 1.19, regular=2.49)
    assert o.discount_pct == 52


def test_history_accumulates_and_trims():
    o = mk("lidl", "Kivi", 0.49, sid="9")
    hist = {f"{o.product_key}|none": [["2026-01-01", 0.9], ["2026-10-10", 0.69]]}
    hist = update_history(hist, [o], date(2026, 10, 14))
    assert hist[f"{o.product_key}|none"] == [["2026-10-10", 0.69], ["2026-10-14", 0.49]]


def test_carry_over_for_failed_source():
    prev = [
        {"chain": "spar", "name": "A", "validTo": "2026-10-20", "fetchedAt": (datetime.now(TZ) - timedelta(hours=6)).isoformat()},
        {"chain": "spar", "name": "staro", "validTo": "2026-10-01", "fetchedAt": datetime.now(TZ).isoformat()},
        {"chain": "lidl", "name": "B", "validTo": None, "fetchedAt": datetime.now(TZ).isoformat()},
    ]
    sources = [SourceResult("spar", "s", "u", status="error"), SourceResult("lidl", "l", "u")]
    kept = carry_over_failed(sources, [], prev, date(2026, 10, 14))
    assert [k["name"] for k in kept] == ["A"] and kept[0]["stale"]
    assert sources[0].notes


def test_build_writes_files(tmp_path):
    offers = [mk("lidl", "Piščančje prsi", 5.0, 4.99, "piscancje-prsi", regular=7.0)]
    coupons = [Coupon(chain="tus", title="Kupon", source_url="u", how_to_redeem=Redeem.CARD)]
    res = RunResult(offers, coupons, [SourceResult("lidl", "s", "u", count=1, fetched_at=NOW)], [], [])
    meta = build(res, tmp_path, now=NOW)
    data = json.loads((tmp_path / "offers.json").read_text())
    o = data["offers"][0]
    for key in ["id", "chain", "name", "brand", "category", "packSize", "price", "regularPrice", "discountPct",
                "unitPrice", "validFrom", "validTo", "condition", "sourceUrl", "imageUrl", "fetchedAt"]:
        assert key in o
    assert o["condition"] == {"type": "none", "description": None}
    assert meta["sources"][0]["status"] == "ok"
    assert {"offers.json", "coupons.json", "meta.json", "history.json", "unclassified.json", "report.md"} <= {
        p.name for p in tmp_path.iterdir()}
    m = json.loads((tmp_path / "meta.json").read_text())
    assert {s["id"] for s in m["sections"]} == {"zivila", "dom"}
