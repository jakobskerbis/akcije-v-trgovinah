from datetime import date

import pytest

from akcije.units import (
    compute_unit_price,
    extract_pack,
    parse_date_range,
    parse_number,
    parse_quantity,
    parse_unit_price_text,
)

T = date(2026, 10, 14)


@pytest.mark.parametrize("s,expected", [("4,49 €", 4.49), ("1.234,56", 1234.56), ("0.89", 0.89), ("5,99\xa0", 5.99)])
def test_parse_number(s, expected):
    assert parse_number(s) == pytest.approx(expected)


@pytest.mark.parametrize(
    "s,qty,unit",
    [
        ("460 g", 0.46, "kg"),
        ("6 x 37 g", 0.222, "kg"),
        ("2 x 684 ml", 1.368, "l"),
        ("Kapsule Somat, 85/1", 85, "kos"),
        ("POMURSKO MLEKO 3,5% M.M., 6X1L", 6, "l"),
        ("0,2 l", 0.2, "l"),
        ("190/200 g", 0.19, "kg"),
        ("125G", 0.125, "kg"),
    ],
)
def test_parse_quantity(s, qty, unit):
    q = parse_quantity(s)
    assert q is not None and q[1] == unit and q[0] == pytest.approx(qty)


def test_extract_pack_and_unit_price():
    name = "Čips Lorenz, X - cut, kisla smetana, 130 g"
    assert extract_pack(name) == "130 g"
    up = compute_unit_price(1.19, "130 g", name)
    assert up[1] == "kg" and up[0] == pytest.approx(9.1538, rel=1e-3)
    assert compute_unit_price(2.69, "za kg") == (2.69, "kg")


@pytest.mark.parametrize(
    "s,expected",
    [
        ("1 kg = 11,40", (11.40, "kg")),
        ("(12,59 €/1 kg)", (12.59, "kg")),
        ("(0,03 €/1 x kos)", (0.03, "kos")),
        ("460 g - za kg 9,77 €", (9.77, "kg")),
        ("1 kos = 0,49", (0.49, "kos")),
    ],
)
def test_unit_price_text(s, expected):
    got = parse_unit_price_text(s)
    assert got[1] == expected[1] and got[0] == pytest.approx(expected[0])


@pytest.mark.parametrize(
    "s,start,end",
    [
        ("14.&hyphen;27. 10. 2026", date(2026, 10, 14), date(2026, 10, 27)),
        ("30. 9.-6. 10. 2026", date(2026, 9, 30), date(2026, 10, 6)),
        ("8.10 - 14.10", date(2026, 10, 8), date(2026, 10, 14)),
        ("Od 19.10. do 21.10.", date(2026, 10, 19), date(2026, 10, 21)),
        ("14. 10. 2026 - 3. 11. 2026", date(2026, 10, 14), date(2026, 11, 3)),
        ("Na voljo od 15. 10. 2026", date(2026, 10, 15), None),
        ("28.12 - 3.1", date(2026, 12, 28), date(2027, 1, 3)),
    ],
)
def test_date_ranges(s, start, end):
    assert parse_date_range(s, T) == (start, end)
