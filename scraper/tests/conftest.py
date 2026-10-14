import gzip
from datetime import date, datetime
from pathlib import Path

import pytest

from akcije.units import TZ

FIXTURES = Path(__file__).parent / "fixtures"


def fixture_text(name: str) -> str:
    return gzip.open(FIXTURES / f"{name}.gz", "rt", encoding="utf-8").read()


@pytest.fixture
def today() -> date:
    return date(2026, 10, 14)


@pytest.fixture
def now() -> datetime:
    return datetime(2026, 10, 14, 9, 0, tzinfo=TZ)
