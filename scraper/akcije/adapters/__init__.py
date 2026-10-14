"""Register vseh adapterjev. Nova veriga = nova datoteka + vrstica tukaj."""

from .eurospin import EurospinAdapter
from .hofer import HoferAdapter
from .lidl import LidlAdapter
from .mercator import MercatorAdapter
from .obi import ObiAdapter
from .spar import SparAdapter
from .tus import TusAdapter

ADAPTERS = [
    MercatorAdapter,
    SparAdapter,
    TusAdapter,
    HoferAdapter,
    LidlAdapter,
    EurospinAdapter,
    ObiAdapter,
]

__all__ = ["ADAPTERS"]
