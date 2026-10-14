import pytest

from akcije.classify import CATEGORIES, classify, kind_for


@pytest.mark.parametrize(
    "name,hint,section,expected",
    [
        ("Čips Lorenz, X - cut, kisla smetana, 130 g", "Sladko in slano", None, "sladko"),
        ("Jogurt MU Athentikos, naravni, 430 g", None, None, "mlecni"),
        ("Mleta kava Classic, Barcaffe, 100 g", None, None, "pijace"),
        ("Čokoladno mleko", None, None, "pijace"),
        ("Sirni namaz Philadelphia", None, None, "sir"),
        ("Sirup bezeg", None, None, "pijace"),
        ("Sveža svinjska rebra", "Meso in perutnina/Svinjina", None, "meso"),
        ("Piščančja prsa Izbrana kakovost", None, None, "perutnina"),
        ("File lososa", None, None, "ribe"),
        ("Kozice olupljene 200 g", None, None, "ribe"),
        ("Kozica Kuham s srcem, črna, fi 14 cm, 1 l", "Dom", None, "kuhinja"),
        ("Zelena jabolka", "Sadje in zelenjava", None, "sadje"),
        ("Buče maslenke", None, None, "zelenjava"),
        ("Toaletni papir Exclusive, Paloma, 3-slojni, 10/1", "HIGIENA IN LEPOTA", None, "gospodinjstvo"),
        ("Detergent Nila, gel, 2,7 l", "Dom", None, "gospodinjstvo"),
        ("Premium milo za roke", "Hrana in bližnja hrana/Drogerija in nega/Nega", None, "drogerija"),
        ("Haložan", "Vino, pivo in žgane pijače/Vino/Belo vino", None, "pijace"),
        # Lidl včasih napačno uvrsti meso med pijače – koren zmaga znotraj živil
        ("Sveže goveje meso za juho", "Hrana in bližnja hrana/Pijače/brezalkoholne pijače", None, "meso"),
        ("ŽAR LEGENDE Goveji burger", "Hrana in bližnja hrana/Meso in perutnina/goveje meso", None, "meso"),
        ("Mleta paprika sladka", None, None, "ostalo"),
        ("Zložljiva pručka", None, "dom", "dom"),
        ("Slovenska krizantema", None, "dom", "vrt"),
        ("Einhell Akumulatorski vrtalni vijačnik", None, "dom", "orodje"),
        ("Vinilna tla hrast Lyon na klik 4 mm", None, "dom", "orodje"),
        ("Vrečke za zamrzovanje z dvojnim zapiralom", None, "dom", "gospodinjstvo"),
        ("Hrana za mačke Felix", None, None, "zivali"),
        ("Higiensko čistilo, Frosch", "ČISTILA/EKOLOŠKA ČISTILA", None, "drogerija"),
        ("Punčka Flower Hair", "VSE ZA OTROKA/IGRAČE/DOJENČKI IN PUNČKE", None, "prosti_cas"),
    ],
)
def test_classify(name, hint, section, expected):
    assert classify(name, None, hint, section).category == expected


def test_sections_are_consistent():
    ids = {c.id for c in CATEGORIES}
    assert {"meso", "perutnina", "ribe", "sir", "mlecni", "zelenjava", "sadje", "kruh", "testenine",
            "zamrznjeno", "pijace", "sladko", "ostalo"} <= ids
    assert all(c.section in ("zivila", "dom") for c in CATEGORIES)
    assert all(c.section == "zivila" for c in CATEGORIES if c.food)


def test_unknown_goes_to_report():
    r = classify("Neznan izdelek XY-42", None, None, None)
    assert r.category == "ostalo" and not r.certain


@pytest.mark.parametrize(
    "name,cat,kind",
    [
        ("Piščančje prsi brez kože", "perutnina", "piscancje-prsi"),
        ("Mleto mešano meso", "meso", "mleto-meso"),
        ("POMURSKO MLEKO 3,5% M.M., 6X1L", "mlecni", "mleko"),
        ("Čokoladno mleko", "mlecni", None),
        ("Slovenski krompir pakiran, 10 kg", "zelenjava", "krompir"),
        ("Mleta kava Classic, Barcaffe, 100 g", "pijace", "kava-mleta"),
    ],
)
def test_kinds(name, cat, kind):
    assert kind_for(name, cat) == kind
