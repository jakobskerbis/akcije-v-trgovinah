"""Podatkovni model, skupen vsem adapterjem.

JSON izhod uporablja camelCase ključe, ker ga berejo Swift in Dart odjemalci.
"""

from __future__ import annotations

import hashlib
from dataclasses import asdict, dataclass, field
from datetime import date, datetime
from enum import StrEnum


class Condition(StrEnum):
    NONE = "none"
    LOYALTY_CARD = "loyaltyCard"
    APP = "app"
    COUPON = "coupon"
    # Količinski popust (npr. "ob nakupu 2 ali več"). Ni v prvotnem modelu,
    # a brez njega bi bila taka cena napačno prikazana kot brezpogojna.
    MULTI_BUY = "multiBuy"


class Redeem(StrEnum):
    APP = "app"
    CARD = "card"
    PRINTED = "printed"


@dataclass
class Offer:
    chain: str
    name: str
    price: float
    source_url: str
    fetched_at: datetime
    brand: str | None = None
    category: str | None = None
    pack_size: str | None = None
    regular_price: float | None = None
    discount_pct: int | None = None
    unit_price: float | None = None
    unit: str | None = None  # "kg" | "l" | "kos"
    valid_from: date | None = None
    valid_to: date | None = None
    condition: Condition = Condition.NONE
    condition_text: str | None = None
    image_url: str | None = None
    ean: str | None = None
    # Identiteta izdelka pri verigi (za zgodovino cen); ni odvisna od tedna.
    source_id: str | None = None
    # Namig iz kategorije vira (npr. "Meso, delikatesa in ribe"), pomaga razvrščanju.
    source_category: str | None = None
    kind: str | None = None
    best_unit_price: bool = False
    id: str = ""
    product_key: str = ""

    def finalize(self) -> None:
        if self.discount_pct is None and self.regular_price and self.regular_price > self.price:
            self.discount_pct = round((1 - self.price / self.regular_price) * 100)
        ident = self.source_id or self.ean or f"{_norm(self.name)}|{self.pack_size or ''}"
        self.product_key = f"{self.chain}:{ident}"
        raw = "|".join(
            [
                self.product_key,
                str(self.condition),
                self.valid_from.isoformat() if self.valid_from else "",
                f"{self.price:.2f}",
            ]
        )
        self.id = hashlib.sha1(raw.encode()).hexdigest()[:16]

    def to_json(self) -> dict:
        return {
            "id": self.id,
            "productKey": self.product_key,
            "chain": self.chain,
            "name": self.name,
            "brand": self.brand,
            "category": self.category,
            "kind": self.kind,
            "packSize": self.pack_size,
            "price": round(self.price, 2),
            "regularPrice": round(self.regular_price, 2) if self.regular_price else None,
            "discountPct": self.discount_pct,
            "unitPrice": round(self.unit_price, 2) if self.unit_price else None,
            "unit": self.unit,
            "bestUnitPrice": self.best_unit_price,
            "validFrom": self.valid_from.isoformat() if self.valid_from else None,
            "validTo": self.valid_to.isoformat() if self.valid_to else None,
            "condition": {"type": str(self.condition), "description": self.condition_text},
            "ean": self.ean,
            "sourceUrl": self.source_url,
            "imageUrl": self.image_url,
            "fetchedAt": self.fetched_at.isoformat(timespec="seconds"),
        }


@dataclass
class Coupon:
    chain: str
    title: str
    source_url: str
    how_to_redeem: Redeem
    discount: str | None = None
    conditions: str | None = None
    valid_from: date | None = None
    valid_to: date | None = None
    image_url: str | None = None
    back_image_url: str | None = None
    personal: bool | None = None
    needs_activation: bool | None = None
    id: str = ""

    def finalize(self) -> None:
        raw = f"{self.chain}|{self.title}|{self.image_url or ''}|{self.valid_from or ''}"
        self.id = hashlib.sha1(raw.encode()).hexdigest()[:16]

    def to_json(self) -> dict:
        return {
            "id": self.id,
            "chain": self.chain,
            "title": self.title,
            "discount": self.discount,
            "conditions": self.conditions,
            "validFrom": self.valid_from.isoformat() if self.valid_from else None,
            "validTo": self.valid_to.isoformat() if self.valid_to else None,
            "howToRedeem": str(self.how_to_redeem),
            "personal": self.personal,
            "needsActivation": self.needs_activation,
            "imageUrl": self.image_url,
            "backImageUrl": self.back_image_url,
            "sourceUrl": self.source_url,
        }


@dataclass
class SourceResult:
    chain: str
    source: str
    url: str
    status: str = "ok"  # ok | error | link
    count: int = 0
    error: str | None = None
    fetched_at: datetime | None = None
    duration_ms: int = 0
    notes: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        d = asdict(self)
        return {
            "chain": d["chain"],
            "source": d["source"],
            "url": d["url"],
            "status": d["status"],
            "count": d["count"],
            "error": d["error"],
            "fetchedAt": self.fetched_at.isoformat(timespec="seconds") if self.fetched_at else None,
            "durationMs": d["duration_ms"],
            "notes": d["notes"],
        }


def _norm(s: str) -> str:
    return " ".join(s.lower().split())
