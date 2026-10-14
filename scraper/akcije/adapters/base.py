"""Enoten vmesnik adapterjev: fetch() -> list[Offer]."""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import date, datetime

from ..http import PoliteClient
from ..models import Coupon, Offer
from ..units import TZ


class Adapter(ABC):
    #: kratek id verige ("mercator", "spar", ...)
    chain: str = ""
    #: opis vira za meta.json
    source: str = ""
    #: glavni URL vira
    url: str = ""
    #: "zivila" ali "dom" – privzeta sekcija, ko ni drugega namiga
    default_section: str = "zivila"

    def __init__(self, client: PoliteClient, now: datetime | None = None):
        self.client = client
        self.now = now or datetime.now(TZ)
        self.notes: list[str] = []

    @property
    def today(self) -> date:
        return self.now.date()

    @abstractmethod
    def fetch(self) -> list[Offer]:
        ...

    def coupons(self) -> list[Coupon]:
        return []

    def offer(self, **kw) -> Offer:
        kw.setdefault("chain", self.chain)
        kw.setdefault("fetched_at", self.now)
        return Offer(**kw)
