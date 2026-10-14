"""Razvrščanje izdelkov v kategorije s slovenskimi koreni besed.

Aplikacija ima dve sekciji:
  * "zivila" – živila in vsakdanje potrebščine iz supermarketov (drogerija, čistila, živali)
  * "dom"    – dom, vrt in DIY (OBI, neživilska posebna ponudba Hoferja, Lidla …)

Postopek za vsak izdelek:
  1. izjeme (IZJEME) – fraze, ki bi jih koreni napačno uvrstili;
  2. namig iz kategorije vira (npr. Mercatorjeva "ČISTILA") omeji, ali gre za
     živilo ali ne, in da privzeto kategorijo;
  3. med vsemi pravili zmaga tisti koren, ki se v imenu pojavi NAJPREJ
     ("Čips ..., kisla smetana" -> čips, "Jogurt z jagodami" -> jogurt);
  4. če nič ne ustreza, se uporabi privzeta kategorija namiga, izdelek pa
     se zapiše v poročilo neuvrščenih, da lahko pravila dopolniš.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# --------------------------------------------------------------------------
# Kategorije
# --------------------------------------------------------------------------

SECTIONS = {
    "zivila": "Živila in vsakdanje potrebščine",
    "dom": "Dom, vrt in DIY",
}


@dataclass(frozen=True)
class Category:
    id: str
    label: str
    section: str
    food: bool
    icon: str  # SF Symbol ime; Flutter ima svojo preslikavo


CATEGORIES: list[Category] = [
    Category("meso", "Meso", "zivila", True, "fork.knife"),
    Category("perutnina", "Perutnina", "zivila", True, "bird"),
    Category("ribe", "Ribe in morski sadeži", "zivila", True, "fish"),
    Category("sir", "Sir", "zivila", True, "triangle.lefthalf.filled"),
    Category("mlecni", "Mlečni izdelki in jajca", "zivila", True, "carton"),
    Category("zelenjava", "Zelenjava", "zivila", True, "carrot"),
    Category("sadje", "Sadje", "zivila", True, "apple.logo"),
    Category("kruh", "Kruh in pekovsko", "zivila", True, "birthday.cake"),
    Category("testenine", "Testenine, riž in moka", "zivila", True, "takeoutbag.and.cup.and.straw"),
    Category("zamrznjeno", "Zamrznjeno", "zivila", True, "snowflake"),
    Category("pijace", "Pijače", "zivila", True, "waterbottle"),
    Category("sladko", "Sladko in prigrizki", "zivila", True, "popcorn"),
    Category("ostalo", "Ostala živila", "zivila", True, "basket"),
    Category("drogerija", "Drogerija in nega", "zivila", False, "drop"),
    Category("gospodinjstvo", "Čistila in gospodinjstvo", "zivila", False, "bubbles.and.sparkles"),
    Category("zivali", "Za živali", "zivila", False, "pawprint"),
    Category("dom", "Dom in dekoracija", "dom", False, "sofa"),
    Category("kuhinja", "Kuhinja in posoda", "dom", False, "frying.pan"),
    Category("vrt", "Vrt in rastline", "dom", False, "leaf"),
    Category("orodje", "Orodje, gradnja in DIY", "dom", False, "hammer"),
    Category("tehnika", "Tehnika in aparati", "dom", False, "powerplug"),
    Category("oblacila", "Oblačila in obutev", "dom", False, "tshirt"),
    Category("prosti_cas", "Prosti čas in igrače", "dom", False, "figure.play"),
    Category("avto", "Avto-moto", "dom", False, "car"),
    Category("ostalo_dom", "Ostalo za dom", "dom", False, "shippingbox"),
]
CAT = {c.id: c for c in CATEGORIES}
FOOD = {c.id for c in CATEGORIES if c.food}

# --------------------------------------------------------------------------
# Izjeme: preverjene najprej, prva zadeta zmaga.
# --------------------------------------------------------------------------

IZJEME: list[tuple[str, str]] = [
    (r"čokoladn\w* mlek|čokoladn\w* napit|kakav\w* napit", "pijace"),
    (r"sirni namaz|namaz iz sira|topljen\w* sir|sirn\w* namaz", "sir"),
    (r"\bsirup", "pijace"),
    (r"\bsirotk", "mlecni"),
    (r"kokosov\w* mlek", "ostalo"),
    (r"(sojin|ovsen|rižev|mandljev|rastlinsk)\w* (napit|mlek)|barista", "pijace"),
    (r"mlet\w* kav", "pijace"),
    (r"mlet\w* (paprik|poper|mak|orehi|orehe|lešnik|mandlj|cimet|začimb)", "ostalo"),
    (r"mlek\w* za (telo|sončenje|čiščenje|po sončenju)|mlek\w* za odstranjevanje", "drogerija"),
    (r"mlečn\w* čokolad", "sladko"),
    (r"\bribez", "sadje"),
    (r"rum ploščic|rum kroglic", "sladko"),
    (r"motorn\w* olj|olje za motor|olje za verig", "avto"),
    (r"\bkozic\w*\b.*\b(fi|cm)\b", "kuhinja"),
    (r"hran\w* za (pse|mačke|ptice|živali|ribe|ribice|glodalce)|\bza (pse|mačke)\b|pasj\w* hran|mačj\w* hran|posip za mač|pasje|za mucke", "zivali"),
    (r"papir za peko|vrečk\w* za (zamrzovanje|smeti|sendvič|odpadke|peko|shranjevanje)|alu\w*[ -]?folij|prozorn\w* folij|folij\w* za živila", "gospodinjstvo"),
    (r"(tablet|kapsul|gel|prašek|sredstv)\w* za (pomivaln|pranje|strojno)|pralni prašek|\bdetergent|mehčalec", "gospodinjstvo"),
    (r"sladoled|zamrznjen|smrznjen|globoko zamrz|ribje palčke|pomfri", "zamrznjeno"),
    (r"^juh|jušn\w* kock|kock\w* za juho|instant juh|\bjuha\b", "ostalo"),
    (r"jabolčn\w* kis|\bkis\b|vinsk\w* kis", "ostalo"),
    (r"paradižnikov\w* (mezg|omak|pire|koncentrat|sok)|\bpelat|pasirani paradižnik", "ostalo"),
    (r"otroš\w* (hrana|kašic)|\bkašic", "ostalo"),
    (r"svečk\w* za tort", "ostalo"),
    (r"semen\w* (za setev|zelenjav|rož)|sadik", "vrt"),
    (r"lesn\w* pelet|\bpelet|briket\w* za kurj|\bdrva\b|podpalj", "dom"),
    (r"posod\w* za barv|valjč\w* za barv|lepil\w* za ploščic", "orodje"),
    (r"nagrobn", "dom"),
    (r"(mešanic|zemlj|substrat)\w* za (presajevanje|sajenje|rože|vrt|lončnic)", "vrt"),
    (r"zeliščn\w* čaj|sadn\w* čaj|\bčaj\b", "pijace"),
]
_IZJEME = [(re.compile(p, re.I), c) for p, c in IZJEME]

# --------------------------------------------------------------------------
# Koreni po kategorijah. Vsak vzorec se začne na začetku besede (\b).
# --------------------------------------------------------------------------

STEMS: dict[str, list[str]] = {
    "perutnina": [r"pišč", r"pisc", r"puran", r"purić", r"\brac[ae]\b", r"račj", r"gos[ji]\b", r"perutnin", r"chicken"],
    "ribe": [
        r"losos", r"oslič", r"tun[aeio]\b", r"tunin", r"sardin", r"skuš", r"orad", r"brancin", r"kozic", r"lignj",
        r"škamp", r"školjk", r"klapavic", r"hobotnic", r"sipa\b", r"sipe\b", r"rib[aei]\b", r"ribj", r"ribic", r"postrv",
        r"krap", r"som\b", r"file ribe", r"surimi", r"inćun", r"sardel", r"bakalar", r"polenovk", r"suši", r"morsk\w* sadež",
        r"slanik", r"pangasius", r"aljašk",
    ],
    "meso": [
        r"svinj", r"gov[eij]", r"goved", r"telet", r"telič", r"jagnj", r"ovčj", r"mlet", r"zrez", r"klobas", r"salam",
        r"pršut", r"šunk", r"slanin", r"hrenovk", r"čevap", r"pleskavic", r"burger", r"narezek", r"pašte", r"krač",
        r"kare\b", r"vrat\b", r"rebr", r"meso\b", r"mesn", r"pečenk", r"zaseka", r"ocvirk", r"panceta", r"kebab", r"tlačenk",
        r"jetr", r"bržol", r"steak", r"ramstek", r"ramsteak", r"pastrami", r"kulen",
        r"mortadel", r"prekajen", r"suho meso", r"buđol", r"budjol",
    ],
    "sir": [
        r"sir(?!up|otk|ov)", r"mocarel", r"mozzarel", r"parmez", r"parmigian", r"grana padano", r"gavd", r"gauda", r"edam",
        r"ementaler", r"emmental", r"trapist", r"tilzit", r"tilsit", r"feta\b", r"rikot", r"ricott", r"maskarpon",
        r"mascarpon", r"camembert", r"brie\b", r"gorgonzol", r"čedar", r"cheddar", r"halloumi", r"burrat", r"pecorino",
        r"jošt", r"tolminc", r"nanoški",
    ],
    "mlecni": [
        r"jogurt", r"skyr", r"kefir", r"skut", r"mlek[oa]\b", r"mleko,", r"smetan", r"\bmasl[oa]\b", r"jajc", r"puding",
        r"pinjen", r"margarin", r"kislo mleko", r"lassi", r"ajran", r"protein\w* napitek",
    ],
    "kruh": [
        r"kruh", r"štruc", r"žemlj", r"rogljič", r"kroasan", r"croissant", r"bagel", r"toast", r"burek", r"kifelj",
        r"bombet", r"baget", r"tortilj", r"krof", r"pecivo", r"pogač", r"potic", r"pletenic", r"francoski", r"ciabatt",
        r"focacc", r"mlinc", r"prepečen", r"hrustljav\w* kruh", r"pekovsk", r"pita\b", r"pizza štru", r"sendvič",
    ],
    "testenine": [
        r"testenin", r"špaget", r"spaghet", r"makaron", r"penne", r"fusilli", r"fuži", r"njok", r"lazanj", r"rezanc",
        r"polžk", r"peresnik", r"svedrc", r"metuljčk", r"tortelin", r"tortellin", r"ravioli", r"riž\b", r"rižot", r"basmati",
        r"\bmok[aei]\b", r"zdrob", r"polent", r"kus[ -]?kus", r"kvinoj", r"ajdov\w* kaš", r"ješpren", r"proso", r"bulgur",
        r"tagliatel", r"farfalle", r"gnocchi",
    ],
    "pijace": [
        r"sok\b", r"sokov", r"nektar", r"voda\b", r"vode\b", r"mineraln", r"pivo", r"piva\b", r"lager", r"radler",
        r"vin[oa]\b", r"vinsk", r"penin", r"prosecco", r"šampanj", r"cava\b", r"muškat", r"rebul", r"malvazij", r"refošk",
        r"teran", r"cviček", r"merlot", r"cabernet", r"chardonnay", r"sauvignon", r"rizling", r"haložan", r"modra frankinj",
        r"cockta", r"cola\b", r"kola\b", r"pepsi", r"fanta", r"sprite", r"schweppes", r"tonik", r"ledeni čaj", r"napitek",
        r"napit", r"energijsk", r"red bull", r"žganj", r"liker", r"viski", r"whisk", r"vodk", r"\bgin\b", r"\brum\b",
        r"brinjevec", r"slivovk", r"pelinkovec", r"jägermeister", r"aperol", r"kava\b", r"kave\b", r"espresso", r"kapsul\w* kav",
        r"cappuccino", r"kakav", r"čaj", r"smoothie", r"limonad", r"cedevit", r"oranžad", r"isotonic", r"izotonič",
    ],
    "sladko": [
        r"čokolad", r"bonbon", r"keks", r"piškot", r"napolitank", r"čips", r"smoki", r"flips", r"prest", r"kreker",
        r"oreš", r"arašid", r"mandlj", r"lešnik", r"orehi", r"pistacij", r"indijsk", r"desert", r"tort[ae]\b", r"rezin",
        r"žvečil", r"gumi", r"lizik", r"marmelad", r"džem", r"\bmed\b", r"medu\b", r"nutell", r"namaz", r"corny", r"ploščic",
        r"mafin", r"muffin", r"vafelj", r"vafl", r"waffel", r"kokic", r"pralin", r"bombonier", r"mars\b", r"snickers", r"twix",
        r"milka", r"kinder", r"oreo", r"rafael", r"sladic", r"čokolino", r"krem\w* (kakav|lešnik)", r"palačink", r"krof",
        r"kremšnit", r"štrudelj", r"zavitek", r"sladoled",
    ],
    "zelenjava": [
        r"krompir", r"čebul", r"česen", r"paradižnik", r"paprik", r"kumar", r"solat", r"zelje\b", r"zelj[ae]\b", r"korenj",
        r"bučk", r"buč[ae]\b", r"maslenk", r"brokol", r"cvetač", r"špinač", r"radič", r"motovilec", r"rukol", r"\bpor\b",
        r"gob[ae]\b", r"gobe", r"šampinjon", r"jajčev", r"grah\b", r"stročj", r"koleraba", r"pesa\b", r"rdeča pesa",
        r"blitva", r"ohrovt", r"kolerab", r"redkev", r"redkvic", r"artičok", r"šparg", r"koruz[ae]\b", r"ingver",
        r"sladki krompir", r"batat", r"fižol", r"leča", r"čičeriko", r"čičerik", r"zelenjav", r"peteršilj", r"drobnjak",
        r"bazilik", r"avokad",
    ],
    "sadje": [
        r"jabolk", r"hrušk", r"banan", r"pomaranč", r"mandarin", r"klementin", r"limon", r"limet", r"grozdj", r"kivi",
        r"jagod", r"borovnic", r"malin", r"robid", r"ananas", r"mango", r"kaki\b", r"breskev", r"breskv", r"nektarin",
        r"marelic", r"sliv", r"češnj", r"višnj", r"lubenic", r"melon", r"granat", r"fig[ae]\b", r"datlj", r"grenivk",
        r"pomelo", r"kostanj", r"kokos", r"papaj", r"marakuj", r"physalis", r"brusnic", r"sadj", r"rozin", r"suh\w* sadj",
    ],
    "ostalo": [
        r"olj[ea]\b", r"oljčn", r"olivn", r"kis\b", r"sol\b", r"sladkor", r"začimb", r"poper", r"vegeta", r"omak", r"pesto",
        r"kečap", r"ketchup", r"majonez", r"gorčic", r"hren\b", r"konzerv", r"pašteta", r"kosmič", r"musli", r"müsli",
        r"granol", r"žitar", r"cornflakes", r"humus", r"hummus", r"tofu", r"seitan", r"kvas", r"pecilni", r"vanilijev",
        r"jušn", r"buljon", r"pripravljen\w* jed", r"gotov\w* jed", r"solatn\w* preliv", r"ajvar", r"kisle kumar",
        r"vložen", r"olive\b", r"oliv[ae]\b", r"kapr", r"semen", r"bučn\w* olj", r"chia", r"lanen", r"sezam", r"proteinsk",
        r"timijan", r"klinčk", r"kurkum", r"cimet", r"lovor", r"janež", r"kumin", r"majaron", r"origano", r"rožmarin", r"čili",
        r"muškatn\w* oreš", r"curry", r"kari\b", r"paprika mlet", r"želatin", r"kvas", r"puding v prahu", r"zmes za", r"sarm",
        r"čuft", r"vamp", r"golaž", r"ričet", r"jota", r"pasulj", r"lino lada", r"kašic",
    ],
    "drogerija": [
        r"šampon", r"gel za tuš", r"tuš gel", r"gel za prh", r"milo\b", r"mila\b", r"tekoče milo", r"zobn", r"ustn\w* vod",
        r"deodorant", r"dezodorant", r"antiperspirant", r"krem[ae]\b", r"krema za", r"losjon", r"balzam", r"plenic", r"vložk",
        r"tampon", r"britvic", r"brivnik", r"za britje", r"robčk", r"vlažiln\w* robč", r"kozmet", r"ličil", r"maskar",
        r"šmink", r"lak za (nohte|lase)", r"barva za lase", r"sprej za lase", r"pena za lase", r"vatiran", r"vata\b",
        r"palčk\w* za ušes", r"higiensk", r"intimn", r"parfum", r"toaletn\w* vod", r"nivea", r"dove\b", r"gliss", r"syoss",
        r"schauma", r"fa\b", r"colgate", r"parodontax", r"corega", r"pampers", r"nega\b", r"serum", r"maska za",
        r"zobna ščetka", r"zobna pasta", r"vitamin", r"prehransk\w* dopol", r"obliž", r"kontracep", r"kondom",
    ],
    "gospodinjstvo": [
        r"pralni", r"za pranje", r"mehčal", r"čistil", r"čistiln", r"pomivaln", r"somat", r"finish\b", r"persil", r"ariel",
        r"perwoll", r"silan", r"lenor", r"toaletn\w* papir", r"papirnat", r"kuhinjsk\w* (papir|brisač)", r"brisač\w* (iz papirja|papirnat)",
        r"vrečk\w* za", r"folij", r"gobic", r"krp\w* za čiščenje", r"osvežilec", r"wc\b", r"wc ", r"odstranjeval", r"belil",
        r"vodni kamen", r"vžigalic", r"insekticid", r"zewa", r"paloma", r"tissue", r"servet", r"prtički", r"filtr\w* za kav",
        r"vileda", r"metl", r"smetišnic", r"vedro", r"rokavic\w* za (čiščenje|gospodinj)", r"sredstvo za",
    ],
    "zivali": [r"briketi", r"granule za", r"vitakraft", r"felix", r"whiskas", r"pedigree", r"friskies", r"purina", r"ptičj", r"za muce", r"za kužk", r"mačk", r"pse\b", r"psa\b", r"kužk"],
    "kuhinja": [
        r"posod[ae]\b", r"lon[ec]\w*\b(?! za rože)", r"ponev", r"džezv", r"pekač", r"krožnik", r"skodelic", r"kozar[ec]", r"nož\b",
        r"noži\b", r"deska za rez", r"rezaln\w* desk", r"kuhinjsk\w* (pripom|krp|tehtn|nož)", r"termovk", r"steklenic\w* za",
        r"shranjeval", r"sekljal", r"jedilni pribor", r"pribor", r"pladenj", r"model za", r"lopatk", r"zajemalk", r"cedil",
        r"skled", r"kuham s srcem", r"lonček za", r"vrč", r"servirn",
    ],
    "vrt": [
        r"rastlin", r"cvet[je]", r"rož[ae]\b", r"orhide", r"krizantem", r"zemlj\w* za", r"substrat", r"gnojil", r"vrtn",
        r"kosilnic", r"cvetličn", r"travn", r"trata", r"lonček za rože", r"kaktus", r"pesek za", r"zalivalk", r"cev za zaliv",
        r"semena", r"čebulic", r"grm", r"drevesc", r"hortenzij", r"vres", r"mačeh", r"biorast", r"presajevanj", r"sajenj",
        r"multiflora", r"vrtni", r"lončnic",
    ],
    "orodje": [
        r"orodj", r"vrtalnik", r"akumulator", r"vijačnik", r"žag[ae]\b", r"žaga", r"kladiv", r"izvijač", r"klešč", r"brusil",
        r"lepil", r"silikon", r"barv[ae]\b za (stene|les|kovino)", r"zidn\w* barv", r"lak za les", r"čopič", r"valjček", r"lestev",
        r"meter\b", r"delovn\w* rokavic", r"vijak", r"vijaki", r"žebelj", r"sveder", r"svedr", r"podaljšek", r"razdelilec",
        r"stikal", r"ključavnic", r"tesnil", r"mavec", r"kit\b", r"izolac", r"diy", r"parkside", r"power force", r"lopata",
        r"samokolnic", r"varilni", r"kompresor", r"merilnik", r"libela", r"ključ\b", r"ključi\b",
        r"vinil", r"laminat", r"talna oblog", r"talne oblog", r"tla\b", r"ploščic", r"porcelanogres", r"keramičn",
        r"akustičn", r"stensk\w* oblog", r"oblog", r"mavčn", r"plošč[ae]\b", r"polnil\w* za fug", r"fug", r"podlog\w* za",
        r"gradnj", r"gradben", r"cement", r"malt[ae]\b", r"fasad", r"izolacij", r"stiropor", r"opeke?\b", r"profil",
        r"lak\b", r"emajl", r"temeljn\w* barv", r"impregnac", r"knauf", r"ceresit", r"lux-tools", r"wolfcraft",
        r"notranj\w* barv", r"dekorativn\w* barv", r"barva\b", r"stopnic", r"odtok", r"drenažn", r"\bcev\b", r"cevi\b",
        r"premazoval", r"jub\b", r"helios", r"bitumen", r"kanalet", r"žleb", r"ograj", r"stebr", r"tlakovc", r"robnik",
        r"armaturn", r"mrež[ae]\b", r"vodovod", r"sifon", r"ventil", r"spojk", r"silikon",
    ],
    "tehnika": [
        r"televizor", r"\btv\b", r"slušalk", r"polnilec", r"polnilnik", r"baterij", r"žarnic", r"svetilk", r"svetil",
        r"led[- ]?(trak|lučk|sveč|svetil)", r"sesalnik", r"kuhaln", r"cvrtnik", r"mešalnik", r"sokovnik", r"aparat",
        r"grelnik", r"ventilator", r"radiator", r"likalnik", r"sušilnik las", r"tehtnic", r"mikroval", r"kabel", r"usb",
        r"zvočnik", r"telefon", r"tablic", r"računalnik", r"miška", r"tipkovnic", r"kamera", r"ura\b", r"pametn",
        r"električn", r"robot", r"opekač", r"kuhaln\w* plošč", r"kavni aparat", r"brivnik", r"stroj za", r"termometer",
        r"čistilnik", r"visokotlačn", r"pometal",
    ],
    "oblacila": [
        r"majic", r"hlač", r"jakn", r"nogavic", r"copat", r"čevlj", r"superg", r"pulover", r"jopic", r"spodnj\w* peril",
        r"perilo\b", r"pižam", r"bund", r"\bkap[ae]\b", r"šal\b", r"obutev", r"škorenj", r"škornj", r"trenirk", r"pajkic",
        r"modrc", r"boksaric", r"oblek", r"krilo", r"srajc", r"bluz", r"puhovk", r"dežnik", r"torbic", r"nahrbtnik",
        r"rokavic(?!\w* za)", r"otroške? oblačil", r"oblačil", r"esmara", r"livergy", r"lupilu", r"pepperts",
    ],
    "prosti_cas": [
        r"igrač", r"sestavljank", r"lego", r"žog[ae]\b", r"kolo\b", r"kolesa\b", r"šotor", r"spaln\w* vreč", r"fitnes",
        r"jog[ae]\b", r"plišast", r"knjig", r"pobarvank", r"puzzle", r"kostum", r"čarovnic", r"sankanj", r"smučar",
        r"kopalk", r"plavaln", r"ribišk", r"kamping", r"žar\b", r"igr[ae]\b", r"družabn", r"igral", r"zvezek", r"šolsk",
        r"pisal", r"barvic", r"flomaster", r"crivit", r"playtive", r"ustvarjan", r"vroče lepljenj", r"peresnic",
        r"punčk", r"metalec", r"nerf", r"squishmallow", r"kovček", r"set za izdelavo",
    ],
    "avto": [r"avto", r"pnevmat", r"brisalc", r"vetrobran", r"motorn", r"avtomobil", r"za avto", r"jeklenk"],
    "dom": [
        r"dekoraci", r"okrasn", r"okrask", r"sveč[ae]\b", r"svečk", r"blazin", r"odej[ae]", r"posteljnin", r"rjuh",
        r"brisač[ae]\b", r"preprog", r"zaves", r"okvir", r"vaz[ae]\b", r"košar", r"pručk", r"stol\b", r"stoli\b", r"miz[ae]\b",
        r"mizic", r"omar", r"polic[ae]\b", r"predal", r"obešal", r"likaln\w* desk", r"sušilnik za peril", r"božič", r"jaslic",
        r"adventn", r"venč", r"dišeč", r"difuzor", r"ogledal", r"kopalniš", r"tuš zaves", r"predpražnik", r"home creation",
        r"livarno", r"vzmetnic", r"vzglavnik", r"kurjav", r"peč\b", r"kamin", r"regal", r"pohištv", r"komod",
        r"garderob", r"čevljarn", r"vrata\b", r"okn[oa]\b", r"rolet", r"senčil", r"tuš kabin", r"umivaln", r"pip[ae]\b",
        r"armatur", r"wc školjk", r"kopalnišk", r"kad\b", r"kadi\b", r"stena za kad", r"zaboj", r"škatl", r"prt\b",
        r"prti\b", r"nadprt", r"pregrinjal", r"kopaln\w* plašč", r"tekač\b", r"jelk", r"vršičk", r"smrečic", r"novoletn",
    ],
}

_STEM_RES: list[tuple[str, re.Pattern]] = []
for _cat, _stems in STEMS.items():
    for _s in _stems:
        pat = _s if _s.startswith(r"\b") else r"\b" + _s
        _STEM_RES.append((_cat, re.compile(pat, re.I)))

# Vrstni red pri izenačenju (ista pozicija): bolj specifične kategorije prej.
_PRIORITY = {c: i for i, c in enumerate([
    "zivali", "zamrznjeno", "perutnina", "ribe", "sir", "mlecni", "kruh", "testenine", "pijace", "sladko",
    "sadje", "zelenjava", "meso", "ostalo", "drogerija", "gospodinjstvo", "kuhinja", "vrt", "orodje", "tehnika",
    "oblacila", "prosti_cas", "avto", "dom", "ostalo_dom",
])}

# --------------------------------------------------------------------------
# Namigi iz kategorij virov (Mercator, Tuš, Spar, Lidl, Hofer, OBI)
# Vzorec -> privzeta kategorija. Preverja se od najglobljega segmenta poti.
# --------------------------------------------------------------------------

# (vzorec, kategorija, zanesljivo). "zanesljivo=False" pomeni, da je namig preširok
# (npr. "Sadje in zelenjava"), zato izdelek brez ujemajočega korena gre v poročilo.
HINTS: list[tuple[str, str, bool]] = [
    (r"male živali|male domače živali|za male živali|zivali|hišni ljubljen|pasj|mačj", "zivali", True),
    (r"zamrznjen", "zamrznjeno", True),
    (r"perutnin", "perutnina", True),
    (r"ribe in morski|^\s*ribe\b|morski sadež|ribji", "ribe", True),
    (r"meso|mesni|delikates|klobase in narezki|salame|mesnine", "meso", False),
    (r"\bsir\b|siri\b", "sir", True),
    (r"jajca\b|mleko in|smetan|jogurt|maslo|mlečn|mleko, jajca|hlajen", "mlecni", False),
    (r"sadje in zelenjava|f\+v", "zelenjava", False),
    (r"zelenjav", "zelenjava", True),
    (r"\bsadje\b|sveže sadje|suho sadje", "sadje", True),
    (r"kruh|pekarn|pekovsk|pecivo|toast", "kruh", True),
    (r"testenin|\briž\b|moka|juhe, riž|zakuh", "testenine", True),
    (r"pijač|vin[ao]\b|vina\b|pivo|piva\b|žgan|kava|čaj|sokovi|vode\b|cognac|brandy", "pijace", True),
    (r"sladk|slan\w* prigrizk|čokolad|prigrizk|sladkarij|bonbon|piškot|grisin", "sladko", True),
    (r"igrač|punčk|prosti čas|otroci in igrače|šola|šolo|pisarn|pisal|noč čarovnic|darilni program", "prosti_cas", True),
    (r"prehransk\w* dopol|vitamin|lekarn|prva pomoč|osebna nega|higiena|lepota|drogerij|nega\b|lasje|telo\b|dojenčki|vse za otroka|pripomočki za otroka", "drogerija", True),
    (r"čistila|čistil|detergent|insekticid|pripomočki za čiščenje|papirna|pvc|folije", "gospodinjstvo", True),
    (r"kuhinjska posoda|posoda|stekleni izdelki|pribor|kuhinja|pekač|modeli", "kuhinja", True),
    (r"tekstil|posteljnin|kopalnišk|dekoracij|božič|novoletn|nagrobn|galanterij|izdelki za dom in dekoracija|kopalnica|sezonsko|svečk|sveče", "dom", True),
    (r"cvetje in vrt|vrt|rastline", "vrt", True),
    (r"avto", "avto", True),
    (r"diy|naredi sam|orodje", "orodje", True),
    (r"gospodinjski aparati|elektronika|tehnika|aparati", "tehnika", True),
    (r"moda|oblačila|obutev|dodatki", "oblacila", True),
    (r"izdelki za dom|gospodinjstvo|vse za dom in gospodinjstvo|\bdom\b", "gospodinjstvo", False),
    (r"začimb|dišav|pripravljen\w* hran|pripravljene jedi|otroška prehrana|otroške kašice|vse za peko|omake|juhe", "ostalo", True),
    (r"shramba|osnovna živila|konzervir|zajtrk|hrana tujih|dietet|ekološk|bio in|zaloga hrane|hrana", "ostalo", False),
]
_HINT_RES = [(re.compile(p, re.I), c, ok) for p, c, ok in HINTS]

FOOD_HINT_CATS = FOOD


def _norm(s: str) -> str:
    s = s.replace("\xa0", " ").replace("´", "'").replace("’", "'")
    return " ".join(s.lower().split())


def hint_lookup(hint: str | None) -> tuple[str, bool] | None:
    """Kategorija iz poti kategorij vira; najprej najgloblji segment."""
    if not hint:
        return None
    segments = [s for s in re.split(r"[/>|]", hint) if s.strip()]
    for seg in reversed(segments):
        for rx, cat, ok in _HINT_RES:
            if rx.search(seg):
                return cat, ok
    return None


def hint_category(hint: str | None) -> str | None:
    h = hint_lookup(hint)
    return h[0] if h else None


@dataclass
class Result:
    category: str
    section: str
    certain: bool
    rule: str


def classify(name: str, brand: str | None = None, hint: str | None = None, default_section: str | None = None) -> Result:
    text = _norm(name)
    if brand:
        b = _norm(brand)
        if b and text.startswith(b + " ") and len(text) > len(b) + 3:
            text = text[len(b) + 1:]

    for rx, cat in _IZJEME:
        if rx.search(text):
            return Result(cat, CAT[cat].section, True, f"izjema:{rx.pattern}")

    looked = hint_lookup(hint)
    hint_cat, hint_ok = looked if looked else (None, False)
    allowed: set[str] | None = None
    if hint_cat is not None:
        if hint_cat in FOOD:
            allowed = set(FOOD)
        elif CAT[hint_cat].section == "zivila":
            # drogerija/gospodinjstvo/živali: brez omejitve (otroška hrana pri "vse za otroka",
            # džezva pri Tuševem "Dom" ...); namig je le privzeta kategorija.
            allowed = None
        else:
            allowed = {c.id for c in CATEGORIES if not c.food}
    elif default_section == "dom":
        allowed = {c.id for c in CATEGORIES if c.section == "dom"} | {"drogerija", "gospodinjstvo", "zivali"}

    best: tuple[int, int, str, str] | None = None
    for cat, rx in _STEM_RES:
        if allowed is not None and cat not in allowed:
            continue
        m = rx.search(text)
        if m:
            key = (m.start(), _PRIORITY.get(cat, 99), cat, rx.pattern)
            if best is None or key < best:
                best = key
    if best is not None:
        cat = best[2]
        return Result(cat, CAT[cat].section, True, f"koren:{best[3]}")

    if hint_cat is not None:
        return Result(hint_cat, CAT[hint_cat].section, hint_ok, f"namig:{hint}")
    if default_section == "dom":
        return Result("ostalo_dom", "dom", False, "privzeto:dom")
    return Result("ostalo", "zivila", False, "privzeto")


# --------------------------------------------------------------------------
# Vrste živil za primerjavo cene na enoto med verigami
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Kind:
    id: str
    label: str
    pattern: str
    categories: tuple[str, ...]
    exclude: str | None = None


KINDS: list[Kind] = [
    Kind("piscancje-prsi", "Piščančje prsi / file", r"pišč\w* (prsi|file|fileji)|prsi\w* pišč", ("perutnina",), r"narezek|panir|pečen|dimljen|šunk"),
    Kind("piscancja-bedra", "Piščančja bedra / krače", r"pišč\w* (bedr|krač|stegn|bedrc)", ("perutnina",), r"panir|pečen"),
    Kind("piscanec-cel", "Cel piščanec", r"cel\w* pišč|piščanec,? cel|pišč\w* cel", ("perutnina",)),
    Kind("puranje-prsi", "Puranje prsi / file", r"puran\w* (prsi|file|zrezk)", ("perutnina",), r"narezek|šunk|salam"),
    Kind("mleto-meso", "Mleto meso", r"mlet\w* (meso|mešan|govej|svinj|goved)|^mleto\b", ("meso",)),
    Kind("svinjski-vrat", "Svinjski vrat", r"svinjsk\w* vrat", ("meso",), r"dimljen|prekajen|narezek"),
    Kind("svinjska-rebra", "Svinjska rebra", r"svinjsk\w* rebr|rebra\w* svinj", ("meso",), r"dimljen|prekajen|pečen"),
    Kind("svinjski-zrezki", "Svinjski zrezki / kare / file", r"svinjsk\w* (zrezk|file|kare|ribic|stegn)|svinjski kare", ("meso",), r"dimljen|prekajen|panir"),
    Kind("govedina-juha", "Govedina za juho", r"(govej|goved)\w* (meso )?za juho|juho\w* govej", ("meso",)),
    Kind("goveji-zrezki", "Goveji zrezki / steak", r"govej\w* (zrezk|steak|file|stegn)|ramste[ai]k|rib[- ]?eye|t-bone", ("meso",)),
    Kind("hrenovke", "Hrenovke", r"hrenovk", ("meso", "perutnina")),
    Kind("kranjska", "Kranjska klobasa", r"kranjsk\w* klobas", ("meso",)),
    Kind("prsut", "Pršut", r"pršut", ("meso",)),
    Kind("sunka", "Šunka", r"šunk", ("meso", "perutnina")),
    Kind("slanina", "Slanina", r"slanin", ("meso",)),
    Kind("losos", "Losos", r"losos", ("ribe",), r"pašte|namaz"),
    Kind("tuna", "Tuna", r"\btun[aeio]\b|tunin", ("ribe",), r"pašte|namaz|solat"),
    Kind("oslic", "Oslič", r"oslič", ("ribe",)),
    Kind("orada-brancin", "Orada / brancin", r"orad|brancin", ("ribe",)),
    Kind("kozice", "Kozice", r"kozic", ("ribe",)),
    Kind("mocarela", "Mocarela", r"mocarel|mozzarel", ("sir",)),
    Kind("trdi-sir", "Trdi sir (gavda, edamec, ementaler …)", r"gavd|gauda|edam|ementaler|emmental|trapist|tilzit|tilsit|jošt", ("sir",), r"narezan\w* .*\b\d{2,3} ?g\b"),
    Kind("parmezan", "Parmezan / Grana Padano", r"parmez|grana padano|parmigian", ("sir",)),
    Kind("feta", "Feta / beli sir", r"\bfeta\b|beli sir", ("sir",)),
    Kind("mleko", "Mleko", r"(^|\b)mlek[oa]\b", ("mlecni",), r"čokolad|kokos|soj|ovs|riž|mandelj|prah|kisl|kondenz|kozj"),
    Kind("jogurt", "Jogurt (navadni)", r"jogurt", ("mlecni",), r"sadn|jagod|borovn|vanilij|čokolad|piti|napitek"),
    Kind("skuta", "Skuta", r"skut", ("mlecni",), r"burek|pecivo|zavitek"),
    Kind("maslo", "Maslo", r"\bmasl[oa]\b", ("mlecni",), r"piškot|keks|rogljič"),
    Kind("smetana-kuhanje", "Smetana za kuhanje", r"smetan\w* za kuhanje|kuhinjsk\w* smetan", ("mlecni",)),
    Kind("sladka-smetana", "Sladka smetana", r"sladk\w* smetan|smetan\w* za stepanje", ("mlecni",)),
    Kind("jajca", "Jajca", r"jajc", ("mlecni",), r"testenin|liker|čokolad"),
    Kind("krompir", "Krompir", r"krompir", ("zelenjava",), r"sladk|čips|pomfri|pire|njok"),
    Kind("cebula", "Čebula", r"čebul", ("zelenjava",), r"čips|vložen"),
    Kind("cesen", "Česen", r"česen", ("zelenjava",)),
    Kind("paradiznik", "Paradižnik", r"paradižnik", ("zelenjava",), r"mezg|omak|pire|pelat|sušen|koncentrat|sok"),
    Kind("paprika", "Paprika", r"paprik", ("zelenjava",), r"čips|mlet|sladk\w* paprik.*g\b"),
    Kind("kumare", "Kumare", r"kumar", ("zelenjava",), r"kisl|vložen"),
    Kind("solata", "Solata", r"solat", ("zelenjava",), r"tun|preliv|piščan|testenin|krompirjev"),
    Kind("zelje", "Zelje", r"zelj", ("zelenjava",), r"kisl"),
    Kind("korenje", "Korenje", r"korenj", ("zelenjava",)),
    Kind("jabolka", "Jabolka", r"jabolk", ("sadje",), r"sok|čips|suš|kis"),
    Kind("hruske", "Hruške", r"hrušk", ("sadje",)),
    Kind("banane", "Banane", r"banan", ("sadje",), r"čips|suš"),
    Kind("pomarance", "Pomaranče", r"pomaranč", ("sadje",), r"sok"),
    Kind("mandarine", "Mandarine / klementine", r"mandarin|klementin", ("sadje",), r"sok"),
    Kind("limone", "Limone", r"limon", ("sadje",), r"sok|limonad"),
    Kind("grozdje", "Grozdje", r"grozdj", ("sadje",), r"sok"),
    Kind("kivi", "Kivi", r"kivi", ("sadje",)),
    Kind("kaki", "Kaki", r"\bkaki\b", ("sadje",)),
    Kind("kruh", "Kruh", r"kruh|štruc", ("kruh",), r"drobtin|prepečen|hrustljav"),
    Kind("toast", "Toast", r"toast", ("kruh",)),
    Kind("testenine", "Testenine", r"testenin|špaget|spaghet|penne|fusilli|makaron|polžk|peresnik|svedrc|metuljčk|farfalle|tagliatel", ("testenine",), r"polnjen|tortelin|ravioli|sveže"),
    Kind("riz", "Riž", r"\briž\b|riž,|basmati|jasmin", ("testenine",), r"napit|mlek|vaflj|kreker|rižot"),
    Kind("moka", "Moka", r"\bmok[ae]\b", ("testenine",)),
    Kind("sladkor", "Sladkor", r"sladkor\b", ("ostalo",), r"brez sladkorja|sladkorn"),
    Kind("olje", "Sončnično / jedilno olje", r"(sončničn|jediln|repičn|rastlinsk)\w* olj|^olje\b", ("ostalo",)),
    Kind("olivno-olje", "Olivno olje", r"olivn\w* olj|oljčn\w* olj|ekstra deviško", ("ostalo",)),
    Kind("kava-mleta", "Kava (mleta / zrna)", r"kav[ae]\b|espresso", ("pijace",), r"instant|kapsul|ledena|napitek|frapp|3 ?v ?1|cappuccino|latte"),
    Kind("kava-kapsule", "Kava v kapsulah", r"kapsul\w* kav|kav\w* .*kapsul", ("pijace",)),
    Kind("voda", "Voda", r"mineraln|naravn\w* vod|\bvoda\b", ("pijace",), r"okus|aroma"),
    Kind("pivo", "Pivo", r"\bpiv[oa]\b|lager|radler", ("pijace",), r"brezalkohol"),
    Kind("sok", "Sok", r"\bsok\b|nektar", ("pijace",)),
    Kind("cokolada", "Čokolada", r"čokolad", ("sladko",), r"napit|mlek|namaz|keks|piškot|bonbon|praline|ploščic"),
    Kind("cips", "Čips", r"čips", ("sladko",)),
    Kind("toaletni-papir", "Toaletni papir", r"toaletn\w* papir", ("gospodinjstvo", "drogerija"), r"vlažn"),
    Kind("kuhinjske-brisace", "Kuhinjske brisače", r"kuhinjsk\w* brisač|papirnat\w* brisač", ("gospodinjstvo",)),
    Kind("detergent", "Pralno sredstvo", r"pralni|detergent|za pranje peril|gel za pranje", ("gospodinjstvo",), r"posod|pomival|sijaj|za roke"),
    Kind("pomivalni-stroj", "Tablete za pomivalni stroj", r"(tablet|kapsul)\w* za (pomivaln|strojno)|all in one|vse v 1", ("gospodinjstvo",), r"sijaj|\bsol\b|čistil|osvežil"),
]
_KIND_RES = [(k, re.compile(k.pattern, re.I), re.compile(k.exclude, re.I) if k.exclude else None) for k in KINDS]


def kind_for(name: str, category: str) -> str | None:
    """Vrsta živila; ujemanje mora biti med prvimi tremi besedami imena
    ("Pasulj Natureta, s slanino" ni slanina)."""
    text = _norm(name)
    head_end = _head_end(text, 3)
    for k, rx, ex in _KIND_RES:
        if category not in k.categories:
            continue
        m = rx.search(text)
        if m and m.start() <= head_end and not (ex and ex.search(text)):
            return k.id
    return None


def _head_end(text: str, words: int) -> int:
    pos = 0
    for _ in range(words):
        nxt = re.search(r"\s+", text[pos:])
        if not nxt:
            return len(text)
        pos += nxt.end()
    return pos


def categories_json() -> dict:
    return {
        "sections": [{"id": k, "label": v} for k, v in SECTIONS.items()],
        "categories": [
            {"id": c.id, "label": c.label, "section": c.section, "food": c.food, "icon": c.icon} for c in CATEGORIES
        ],
        "kinds": [{"id": k.id, "label": k.label, "categories": list(k.categories)} for k in KINDS],
    }
