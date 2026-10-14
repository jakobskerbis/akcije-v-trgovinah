"""Vljuden HTTP odjemalec: jasen User-Agent, robots.txt, razmik med zahtevki."""

from __future__ import annotations

import logging
import time
import urllib.robotparser
from urllib.parse import urlsplit

import httpx

log = logging.getLogger(__name__)

USER_AGENT = (
    "AkcijeSI/1.0 (osebna raba, ne-komercialno; "
    "+https://github.com/jakobskerbis/akcije-v-trgovinah)"
)


class RobotsDisallowed(Exception):
    pass


class PoliteClient:
    def __init__(self, delay: float = 1.5, timeout: float = 45.0, per_host_delay: dict[str, float] | None = None):
        self._client = httpx.Client(
            headers={
                "User-Agent": USER_AGENT,
                "Accept-Language": "sl-SI,sl;q=0.9,en;q=0.5",
            },
            timeout=timeout,
            follow_redirects=True,
        )
        self.delay = delay
        self.per_host_delay = per_host_delay or {}
        self._last: dict[str, float] = {}
        self._robots: dict[str, urllib.robotparser.RobotFileParser | None] = {}
        self.request_count = 0

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "PoliteClient":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def _robots_for(self, url: str) -> urllib.robotparser.RobotFileParser | None:
        parts = urlsplit(url)
        origin = f"{parts.scheme}://{parts.netloc}"
        if origin not in self._robots:
            rp = urllib.robotparser.RobotFileParser()
            try:
                r = self._client.get(origin + "/robots.txt")
                self.request_count += 1
                if r.status_code == 200:
                    rp.parse(r.text.splitlines())
                elif r.status_code in (401, 403):
                    rp.disallow_all = True
                else:
                    rp.allow_all = True
            except httpx.HTTPError as e:
                log.warning("robots.txt za %s ni dosegljiv: %s", origin, e)
                rp.allow_all = True
            self._robots[origin] = rp
        return self._robots[origin]

    def allowed(self, url: str) -> bool:
        rp = self._robots_for(url)
        return rp is None or rp.can_fetch(USER_AGENT, url)

    def _wait(self, host: str) -> None:
        delay = self.per_host_delay.get(host, self.delay)
        last = self._last.get(host)
        if last is not None:
            remaining = delay - (time.monotonic() - last)
            if remaining > 0:
                time.sleep(remaining)
        self._last[host] = time.monotonic()

    def get(self, url: str, *, headers: dict | None = None, retries: int = 2) -> httpx.Response:
        if not self.allowed(url):
            raise RobotsDisallowed(url)
        host = urlsplit(url).netloc
        for attempt in range(retries + 1):
            self._wait(host)
            try:
                r = self._client.get(url, headers=headers)
                self.request_count += 1
                if r.status_code >= 500 and attempt < retries:
                    log.info("%s -> %s, ponavljam", url, r.status_code)
                    time.sleep(3 * (attempt + 1))
                    continue
                r.raise_for_status()
                return r
            except (httpx.TransportError,) as e:
                if attempt >= retries:
                    raise
                log.info("%s: %s, ponavljam", url, e)
                time.sleep(3 * (attempt + 1))
        raise RuntimeError("unreachable")

    def text(self, url: str, **kw) -> str:
        return self.get(url, **kw).text

    def json(self, url: str, **kw):
        return self.get(url, **kw).json()
