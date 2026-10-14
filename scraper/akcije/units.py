"""Razčlenjevanje cen, pakiranj, cen na enoto in datumov v slovenskem zapisu."""

from __future__ import annotations

import re
from datetime import date, datetime
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Europe/Ljubljana")

_NUM = r"\d+(?:[.,]\d+)?"


def parse_number(s: str) -> float | None:
    """'1.234,56' -> 1234.56, '4,49' -> 4.49, '0.89' -> 0.89."""
    if s is None:
        return None
    s = s.strip().replace("\xa0", " ").replace("€", "").replace(" ", "")
    m = re.search(r"\d[\d.,]*", s)
    if not m:
        return None
    t = m.group(0).rstrip(".,")
    if "," in t and "." in t:
        t = t.replace(".", "").replace(",", ".")
    elif "," in t:
        t = t.replace(",", ".")
    elif t.count(".") > 1:
        t = t.replace(".", "")
    try:
        return float(t)
    except ValueError:
        return None


_UNIT_MAP = {
    "g": ("kg", 0.001),
    "gr": ("kg", 0.001),
    "dag": ("kg", 0.01),
    "kg": ("kg", 1.0),
    "ml": ("l", 0.001),
    "cl": ("l", 0.01),
    "dl": ("l", 0.1),
    "l": ("l", 1.0),
    "kos": ("kos", 1.0),
    "kosov": ("kos", 1.0),
    "kom": ("kos", 1.0),
}

_MULTI = re.compile(
    rf"(?P<n>\d+)\s*[x×]\s*(?P<q>{_NUM})?\s*(?P<u>kg|dag|gr|g|ml|cl|dl|l|kosov|kos)\b",
    re.I,
)
_SINGLE = re.compile(rf"(?P<q>{_NUM})(?:\s*/\s*{_NUM})?\s*(?P<u>kg|dag|gr|g|ml|cl|dl|l|kosov|kos|kom)\b", re.I)
_COUNT = re.compile(r"\b(?P<n>\d+)\s*/\s*1\b")
_PER_KG = re.compile(r"(cena\s+)?za\s+(1\s*)?kg|tehtan|/\s*kg\b|per\s+kg|na\s+kg", re.I)


def parse_quantity(text: str | None) -> tuple[float, str] | None:
    """Vrne (količina v osnovni enoti, enota) ali None.

    '460 g' -> (0.46, 'kg'); '6 x 37 g' -> (0.222, 'kg'); '2 x 684 ml' -> (1.368, 'l');
    '10/1' -> (10, 'kos'); '75 x kos' -> (75, 'kos'); '6X1L' -> (6, 'l').
    """
    if not text:
        return None
    t = text.replace("\xa0", " ")
    m = _MULTI.search(t)
    if m:
        unit, factor = _UNIT_MAP[m.group("u").lower()]
        q = parse_number(m.group("q")) if m.group("q") else 1.0
        return (int(m.group("n")) * q * factor, unit)
    matches = list(_SINGLE.finditer(t))
    if matches:
        m = matches[-1]
        unit, factor = _UNIT_MAP[m.group("u").lower()]
        q = parse_number(m.group("q"))
        if q:
            return (q * factor, unit)
    m = _COUNT.search(t)
    if m:
        return (float(m.group("n")), "kos")
    return None


def is_per_kg(text: str | None) -> bool:
    return bool(text and _PER_KG.search(text))


def extract_pack(name: str) -> str | None:
    """Poišče zapis pakiranja v imenu ('Čips Lorenz, 130 g' -> '130 g')."""
    t = name.replace("\xa0", " ")
    m = _MULTI.search(t)
    if m:
        return m.group(0).strip()
    matches = list(_SINGLE.finditer(t))
    if matches:
        return matches[-1].group(0).strip()
    m = _COUNT.search(t)
    if m:
        return m.group(0)
    return None


def compute_unit_price(price: float, pack: str | None, name: str = "") -> tuple[float, str] | None:
    """Cena na enoto (€/kg, €/l, €/kos) iz cene in pakiranja."""
    if is_per_kg(pack) or (not pack and is_per_kg(name)):
        return (price, "kg")
    q = parse_quantity(pack) or parse_quantity(name)
    if not q or q[0] <= 0:
        return None
    qty, unit = q
    return (price / qty, unit)


_UP_PATTERNS = [
    # "1 kg = 11,40", "1 l = 2,49", "100 g = 1,20"
    re.compile(rf"(?P<q>{_NUM})?\s*(?P<u>kg|g|l|ml|kos)\s*=\s*(?P<p>{_NUM})", re.I),
    # "(12,59 €/1 kg)", "(0,03 €/1 x kos)"
    re.compile(rf"(?P<p>{_NUM})\s*€\s*/\s*(?P<q>{_NUM})?\s*(?:x\s*)?(?P<u>kg|g|l|ml|kos)", re.I),
    # "za kg 9,77 €", "za l 1,20 €"
    re.compile(rf"za\s+(?P<q>{_NUM})?\s*(?P<u>kg|g|l|ml|kos)\s*(?P<p>{_NUM})", re.I),
]


def parse_unit_price_text(text: str | None) -> tuple[float, str] | None:
    if not text:
        return None
    t = text.replace("\xa0", " ")
    for pat in _UP_PATTERNS:
        m = pat.search(t)
        if m:
            p = parse_number(m.group("p"))
            q = parse_number(m.group("q")) if m.group("q") else 1.0
            u = m.group("u").lower()
            if p is None or not q:
                continue
            base, factor = _UNIT_MAP[u]
            return (p / (q * factor), base)
    return None


def infer_year(day: int, month: int, today: date) -> int:
    """Leto za datum brez letnice: najbližji datum glede na danes."""
    candidates = [date(today.year + d, month, day) for d in (-1, 0, 1) if _valid(today.year + d, month, day)]
    return min(candidates, key=lambda d: abs((d - today).days)).year


def _valid(y: int, m: int, d: int) -> bool:
    try:
        date(y, m, d)
        return True
    except ValueError:
        return False


_DATE_FULL = re.compile(r"(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})")
_DATE_DM = re.compile(r"(\d{1,2})\.\s*(\d{1,2})\.?")


def parse_date_range(text: str, today: date) -> tuple[date | None, date | None]:
    """Slovenski zapisi obdobij.

    '14.-27. 10. 2026', '30. 9.-6. 10. 2026', '8.10 - 14.10', 'Od 19.10. do 21.10.',
    '14. 10. 2026 - 3. 11. 2026', 'od 8. 10. do 14. 10. 2026'.
    """
    t = text.replace("\xa0", " ").replace("&hyphen;", "-").replace("‐", "-").replace("–", "-").replace("—", "-")
    t = re.sub(r"\s+", " ", t)
    year_m = re.search(r"\b(20\d{2})\b", t)
    year = int(year_m.group(1)) if year_m else None

    # 14.-27. 10. 2026  (isti mesec)
    m = re.search(r"(\d{1,2})\.\s*-\s*(\d{1,2})\.\s*(\d{1,2})\.?\s*(\d{4})?", t)
    if m and not re.search(r"(\d{1,2})\.\s*(\d{1,2})\.?\s*-", t[: m.end()]):
        d1, d2, mo = int(m.group(1)), int(m.group(2)), int(m.group(3))
        y = int(m.group(4)) if m.group(4) else (year or infer_year(d2, mo, today))
        if _valid(y, mo, d1) and _valid(y, mo, d2):
            return date(y, mo, d1), date(y, mo, d2)

    parts = [(int(a), int(b)) for a, b in _DATE_DM.findall(re.sub(r"\b20\d{2}\b", "", t))]
    parts = [(d, mo) for d, mo in parts if 1 <= d <= 31 and 1 <= mo <= 12]
    if not parts:
        return None, None
    if len(parts) == 1:
        d, mo = parts[0]
        y = year or infer_year(d, mo, today)
        return (date(y, mo, d) if _valid(y, mo, d) else None), None
    (d1, m1), (d2, m2) = parts[0], parts[1]
    y2 = year or infer_year(d2, m2, today)
    y1 = y2 - 1 if m1 > m2 else y2
    start = date(y1, m1, d1) if _valid(y1, m1, d1) else None
    end = date(y2, m2, d2) if _valid(y2, m2, d2) else None
    return start, end


def local_date_from_iso(s: str | None) -> date | None:
    if not s:
        return None
    dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=TZ)
    return dt.astimezone(TZ).date()


def local_date_from_epoch(ts: int | float | None) -> date | None:
    if not ts:
        return None
    return datetime.fromtimestamp(ts, TZ).date()
