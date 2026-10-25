#!/usr/bin/env python3
"""Iskalnik najema stanovanj in sob v Ljubljani z okolico (Bolha, osrednjeslovenska regija).

Zažene se z `python3 stanovanja/iskalnik.py [--max 400]` in zapiše stanovanja/index.html,
samostojno stran z vgrajenimi oglasi, ki jo odpreš v brskalniku.
"""
import argparse
import datetime
import html
import json
import pathlib
import urllib.request

BASE = "https://www.bolha.com"
KATEGORIJE = {"stanovanje": "oddaja-stanovanja", "soba": "oddaja-sobe"}
REGIJA = "osrednjeslovenska"
DIR = pathlib.Path(__file__).parent


def nalozi(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    h = urllib.request.urlopen(req, timeout=30).read().decode()
    i = h.index("window.__INITIAL_STATE__=") + len("window.__INITIAL_STATE__=")
    return json.JSONDecoder().raw_decode(h[i:])[0]["browseListingsStore"]["pageData"]


def oglasi(vrsta, max_cena):
    url = f"{BASE}/{KATEGORIJE[vrsta]}/{REGIJA}?price%5Bmax%5D={max_cena}"
    stran = nalozi(url)
    vsi = list(stran["regularListings"])
    for n in range(2, stran["totalPageCount"] + 1):
        vsi += nalozi(f"{url}&page={n}")["regularListings"]
    for o in vsi:
        cena = int("".join(c for c in o["priceFormatted"] if c.isdigit()) or 0)
        yield {
            "id": o["id"],
            "vrsta": vrsta,
            "naslov": o["title"],
            "cena": cena,
            # Bolha pri »cena po dogovoru« vrne simbolične zneske (1 €, 10 €), ki niso najemnina.
            "dogovor": bool(o["isPriceOnRequest"]) or cena < 50,
            "lokacija": o.get("location") or "",
            "m2": next((h["value"] for h in o.get("highlights", []) if h["id"] == "livingArea"), ""),
            "opis": [a["value"] for a in o.get("abstracts", []) if not a.get("caption")],
            "slika": o.get("image") or "",
            "datum": o["createdAt"][:10],
            "url": f"{BASE}/{o['categorySlug']}/{o['titleSlug']}-oglas-{o['id']}",
        }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=400, help="največja mesečna najemnina v €")
    a = ap.parse_args()
    seznam = {}
    for vrsta in KATEGORIJE:
        for o in oglasi(vrsta, a.max):
            seznam[o["id"]] = o
    seznam = sorted(seznam.values(), key=lambda o: o["datum"], reverse=True)
    podatki = {"max": a.max, "zajeto": datetime.datetime.now().strftime("%d. %m. %Y %H:%M"), "oglasi": seznam}
    predloga = (DIR / "predloga.html").read_text(encoding="utf-8")
    json_ = json.dumps(podatki, ensure_ascii=False).replace("</", "<\\/")
    (DIR / "index.html").write_text(predloga.replace("/*PODATKI*/null", json_), encoding="utf-8")
    print(f"{len(seznam)} oglasov → {DIR / 'index.html'}")


if __name__ == "__main__":
    main()
