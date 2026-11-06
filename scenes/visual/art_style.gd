extends RefCounted
## Pelin visuaalinen tyyli yhdessä paikassa: teemat (värit, valo, sumu, rekvisiitta)
## ja jaetut materiaalit (palikat, maasto, vesi, planeetat).
##
## Materiaalit luodaan kerran ja jaetaan, jotta draw calleja ja shader-käännöksiä on
## mahdollisimman vähän. Tämä tiedosto ei koske pelilogiikkaan.

const BLOCK_SOLID := preload("res://scenes/visual/shaders/block_solid.gdshader")
const BLOCK_ICE := preload("res://scenes/visual/shaders/block_ice.gdshader")
const TERRAIN := preload("res://scenes/visual/shaders/terrain.gdshader")
const WATER := preload("res://scenes/visual/shaders/water.gdshader")
const PLANET := preload("res://scenes/visual/shaders/planet.gdshader")
const FIELD := preload("res://scenes/visual/shaders/gravity_field.gdshader")
const SOFT := preload("res://scenes/visual/shaders/soft_toon.gdshader")
const LAVA := preload("res://scenes/visual/shaders/lava.gdshader")

# --- Palette -----------------------------------------------------------------

const WOOD := {"base": Color("d9944a"), "light": Color("f5c27a"), "dark": Color("6b3a17")}
const STONE := {"base": Color("9aa3b5"), "light": Color("c9d0dc"), "dark": Color("4a5163")}
const ICE := {"base": Color("8fd8ff"), "rim": Color("eefbff")}

## Ympäristöteemat. Jokaisella kentällä on yksi teema (katso theme_for_level).
const THEMES := {
	"meadow": {
		"title": "Vihreät niityt",
		"sky_top": Color("4f9dff"), "sky_bottom": Color("bfe6ff"), "sun_scatter": Color("6a5a40"),
		"clouds": 0.45, "night": false,
		"sun_color": Color("fff1d6"), "sun_energy": 1.25, "sun_rot": Vector3(-48.0, 28.0, 0.0),
		"ambient": Color("b9d4ff"), "ambient_energy": 0.75,
		"fog": Color("cfe8ff"), "fog_density": 0.006,
		"terrain": [Color("5bbf3a"), Color("8ad84a"), Color("c98a52"), Color("a86b3c"), Color("5c3a24"), Color("e9c08a")],
		"water": [Color("1f7fd6"), Color("5fd0f2"), 0.0],
		"hills": [Color("7ccf55"), Color("9fd87a"), Color("b6d9c8")],
		"mountains": false,
		"props": "meadow", "particles": "pollen",
	},
	"forest": {
		"title": "Metsä",
		"sky_top": Color("3f8ce6"), "sky_bottom": Color("c4ecdb"), "sun_scatter": Color("60583e"),
		"clouds": 0.55, "night": false,
		"sun_color": Color("ffe9c2"), "sun_energy": 1.15, "sun_rot": Vector3(-42.0, 35.0, 0.0),
		"ambient": Color("a9d6b9"), "ambient_energy": 0.7,
		"fog": Color("bfe3cf"), "fog_density": 0.01,
		"terrain": [Color("3f9e3a"), Color("5fbb44"), Color("8c6142"), Color("6e4a31"), Color("3a281c"), Color("c7a37a")],
		"water": [Color("1d6e7a"), Color("4fb3a8"), 0.0],
		"hills": [Color("2f7f45"), Color("4d9a5c"), Color("8fbfa6")],
		"mountains": false,
		"props": "forest", "particles": "leaves",
	},
	"tropical": {
		"title": "Trooppiset saaret",
		"sky_top": Color("2f9bff"), "sky_bottom": Color("aef2ff"), "sun_scatter": Color("7a6040"),
		"clouds": 0.35, "night": false,
		"sun_color": Color("fff4dc"), "sun_energy": 1.35, "sun_rot": Vector3(-55.0, 20.0, 0.0),
		"ambient": Color("bfeaff"), "ambient_energy": 0.8,
		"fog": Color("c8f3ff"), "fog_density": 0.005,
		"terrain": [Color("6fcf4a"), Color("a4e05a"), Color("f2d49b"), Color("e3bd7d"), Color("a7814f"), Color("fff0c9")],
		"water": [Color("0a8fc9"), Color("3ff0e0"), 0.0],
		"hills": [Color("58c45a"), Color("7fd2a0"), Color("a9e3e8")],
		"mountains": false,
		"props": "tropical", "particles": "none",
	},
	"canyon": {
		"title": "Kanjoni",
		"sky_top": Color("4a8fe8"), "sky_bottom": Color("ffd9a8"), "sun_scatter": Color("8a6a40"),
		"clouds": 0.25, "night": false,
		"sun_color": Color("ffe2b0"), "sun_energy": 1.4, "sun_rot": Vector3(-38.0, 40.0, 0.0),
		"ambient": Color("ffd5b0"), "ambient_energy": 0.7,
		"fog": Color("ffe1bd"), "fog_density": 0.008,
		"terrain": [Color("e8b866"), Color("f3cd84"), Color("d0703f"), Color("b55a33"), Color("7a3a24"), Color("f6c891")],
		"water": [Color("2b7fb8"), Color("6ad0d8"), 0.0],
		"hills": [Color("d98b52"), Color("e0a774"), Color("f0c9a8")],
		"mountains": false,
		"props": "canyon", "particles": "dust",
	},
	"snow": {
		"title": "Jää ja lumi",
		"sky_top": Color("5d97e8"), "sky_bottom": Color("e3f1ff"), "sun_scatter": Color("505a70"),
		"clouds": 0.6, "night": false,
		"sun_color": Color("fff4e6"), "sun_energy": 0.95, "sun_rot": Vector3(-35.0, 30.0, 0.0),
		"ambient": Color("9fb8e8"), "ambient_energy": 0.6,
		"fog": Color("e2eeff"), "fog_density": 0.012,
		"terrain": [Color("dfeaf8"), Color("f2f7ff"), Color("8fa3c4"), Color("71839f"), Color("3e4a63"), Color("cfe0f5")],
		"water": [Color("8cc6f0"), Color("d6f1ff"), 1.0],
		"hills": [Color("a9c6e8"), Color("b7cbe8"), Color("c4d2ec")],
		"mountains": true,
		"props": "snow", "particles": "snow",
	},
	"glacier": {
		"title": "Jäätikkö",
		"sky_top": Color("4c6fc9"), "sky_bottom": Color("f0d9ef"), "sun_scatter": Color("6a5070"),
		"clouds": 0.4, "night": false,
		"sun_color": Color("ffe6f0"), "sun_energy": 0.95, "sun_rot": Vector3(-28.0, 45.0, 0.0),
		"ambient": Color("b0a2e8"), "ambient_energy": 0.6,
		"fog": Color("ead9f2"), "fog_density": 0.013,
		"terrain": [Color("dce9fa"), Color("eef5ff"), Color("7f9fd0"), Color("6684b8"), Color("37466e"), Color("c9e6ff")],
		"water": [Color("7fb8ec"), Color("cdeaff"), 1.0],
		"hills": [Color("a6bde6"), Color("b4c0e6"), Color("bfb4e2")],
		"mountains": true,
		"props": "glacier", "particles": "snow",
	},
	"space": {
		"title": "Avaruus",
		"sky_top": Color("120a2e"), "sky_bottom": Color("3b1f6b"), "sun_scatter": Color("2a1a40"),
		"clouds": 0.0, "night": true,
		"sun_color": Color("e8e0ff"), "sun_energy": 1.2, "sun_rot": Vector3(-35.0, 35.0, 0.0),
		"ambient": Color("8f7dff"), "ambient_energy": 0.8,
		"fog": Color("2a1650"), "fog_density": 0.004,
		"terrain": [Color("7a5cd6"), Color("9b7cf0"), Color("5a5470"), Color("47425c"), Color("231f33"), Color("b3a8d6")],
		"water": [Color("000000"), Color("000000"), 0.0],
		"hills": [Color("000000"), Color("000000"), Color("000000")],
		"mountains": false,
		"props": "space", "particles": "stardust",
		"nebula": [Color("ff5fa2"), Color("5fb8ff")],
	},
	"nebula": {
		"title": "Tähtisumu",
		"sky_top": Color("0a1a2e"), "sky_bottom": Color("164a5c"), "sun_scatter": Color("143040"),
		"clouds": 0.0, "night": true,
		"sun_color": Color("d8fff6"), "sun_energy": 1.2, "sun_rot": Vector3(-30.0, 40.0, 0.0),
		"ambient": Color("6fd8d0"), "ambient_energy": 0.8,
		"fog": Color("0f2f3f"), "fog_density": 0.004,
		"terrain": [Color("2fbfa0"), Color("6fe8c4"), Color("4e5d6e"), Color("3c4858"), Color("1a222c"), Color("9fd8e0")],
		"water": [Color("000000"), Color("000000"), 0.0],
		"hills": [Color("000000"), Color("000000"), Color("000000")],
		"mountains": false,
		"props": "space", "particles": "stardust",
		"nebula": [Color("ffb34f"), Color("4fffd2")],
	},
	"beach": {
		"title": "Hiekkaranta",
		"sky_top": Color("1f7fff"), "sky_bottom": Color("9fdcff"), "sun_scatter": Color("8a6a40"),
		"clouds": 0.3, "night": false,
		"sun_color": Color("fff2d8"), "sun_energy": 1.3, "sun_rot": Vector3(-52.0, 22.0, 0.0),
		"ambient": Color("b0d8ff"), "ambient_energy": 0.6,
		"fog": Color("a8dcff"), "fog_density": 0.004,
		"terrain": [Color("f2c46c"), Color("f8d68a"), Color("d9a45c"), Color("c48a4a"), Color("7a5530"), Color("fff0c8")],
		"water": [Color("0077c2"), Color("2fe3d8"), 0.0],
		"hills": [Color("7cc46a"), Color("8fd2b0"), Color("b4e1ec")],
		"mountains": false, "backdrop": "land",
		"props": "beach", "particles": "none",
	},
	"cave": {
		"title": "Kristalliluola",
		"sky_top": Color("0b0a14"), "sky_bottom": Color("1a1730"), "sun_scatter": Color("000000"),
		"clouds": 0.0, "night": true, "background": Color("0d0b1a"),
		"sun_color": Color("9fb6ff"), "sun_energy": 0.5, "sun_rot": Vector3(-60.0, 25.0, 0.0),
		"ambient": Color("6b5fa0"), "ambient_energy": 0.8,
		"fog": Color("1a1633"), "fog_density": 0.03,
		"terrain": [Color("4f5a6e"), Color("66728a"), Color("4a4256"), Color("3a3446"), Color("17141f"), Color("7d6fa0")],
		"water": [Color("06242e"), Color("1c7f86"), 0.0],
		"hills": [Color("2b2738"), Color("221f2e"), Color("1a1824")],
		"mountains": true, "backdrop": "cave",
		"props": "cave", "particles": "fireflies",
		"crystal": Color("6fe8ff"),
	},
	"volcano": {
		"title": "Tulivuori",
		"sky_top": Color("3a1220"), "sky_bottom": Color("ff7a3a"), "sun_scatter": Color("8a3010"),
		"clouds": 0.2, "night": false,
		"sun_color": Color("ffb27a"), "sun_energy": 1.0, "sun_rot": Vector3(-30.0, 40.0, 0.0),
		"ambient": Color("ff8a6a"), "ambient_energy": 0.55,
		"fog": Color("6a2a2a"), "fog_density": 0.012,
		"terrain": [Color("4a4044"), Color("5e5358"), Color("3a2c2e"), Color("2c2224"), Color("120c0c"), Color("ff6a2a")],
		"water": [Color("000000"), Color("000000"), 0.0],
		"hills": [Color("3a2a2e"), Color("4a3034"), Color("6a3a3a")],
		"mountains": true, "backdrop": "volcano",
		"props": "volcano", "particles": "embers",
	},
	"exoplanet": {
		"title": "Eksoplaneetta",
		"sky_top": Color("1e1a6e"), "sky_bottom": Color("e0609e"), "sun_scatter": Color("6a3a6a"),
		"clouds": 0.2, "night": false,
		"sun_color": Color("ffe0f4"), "sun_energy": 1.05, "sun_rot": Vector3(-40.0, 35.0, 0.0),
		"ambient": Color("9a7ae0"), "ambient_energy": 0.55,
		"fog": Color("9a5aa8"), "fog_density": 0.006,
		"terrain": [Color("8a3cc4"), Color("a85ce0"), Color("2f8f8a"), Color("247370"), Color("143a3a"), Color("8ff0e0")],
		"water": [Color("0c3f44"), Color("2fd29a"), 0.0],
		"hills": [Color("5a34a4"), Color("7a4ab8"), Color("9a6ac4")],
		"mountains": true, "backdrop": "land",
		"props": "exo", "particles": "spores",
		"crystal": Color("6affc8"),
	},
	"desert": {
		"title": "Aavikkomaa",
		"sky_top": Color("3a8ee0"), "sky_bottom": Color("ffd89a"), "sun_scatter": Color("a06020"),
		"clouds": 0.1, "night": false,
		"sun_color": Color("ffe0a0"), "sun_energy": 1.2, "sun_rot": Vector3(-50.0, 35.0, 0.0),
		"ambient": Color("c8b0ff"), "ambient_energy": 0.55,
		"fog": Color("f0c890"), "fog_density": 0.008,
		"terrain": [Color("f2b45d"), Color("f7cf86"), Color("d98a34"), Color("c06f2a"), Color("7a4218"), Color("ffe0a8")],
		"water": [Color("2a8fb0"), Color("7ad8d0"), 0.0],
		"hills": [Color("d98a44"), Color("e6a066"), Color("f0c090")],
		"mountains": false,
		"props": "desert", "particles": "dust",
	},
	"candy": {
		"title": "Karkkimaa",
		"sky_top": Color("ff8fdc"), "sky_bottom": Color("ffe0f6"), "sun_scatter": Color("a04880"),
		"clouds": 0.45, "night": false,
		"sun_color": Color("fff0e0"), "sun_energy": 1.25, "sun_rot": Vector3(-45.0, 30.0, 0.0),
		"ambient": Color("ffc0ec"), "ambient_energy": 0.75,
		"fog": Color("ffd0f0"), "fog_density": 0.006,
		"terrain": [Color("ef62d2"), Color("ff9ae6"), Color("8a4a2a"), Color("6a3420"), Color("3a1a10"), Color("ffe0a8")],
		"water": [Color("9a6aff"), Color("e0b0ff"), 0.0],
		"hills": [Color("f2a6dd"), Color("ffc4ea"), Color("ffe0f4")],
		"mountains": false,
		"props": "candy", "particles": "stardust",
	},
	"apocalypse": {
		"title": "Apokalypsi",
		"sky_top": Color("0a0416"), "sky_bottom": Color("3a1450"), "sun_scatter": Color("8a1e3a"),
		"clouds": 0.0, "night": true,
		"sun_color": Color("ffd0a0"), "sun_energy": 1.0, "sun_rot": Vector3(-35.0, 35.0, 0.0),
		"ambient": Color("8a6ad0"), "ambient_energy": 0.7,
		"fog": Color("2a1048"), "fog_density": 0.006,
		"cloud_sea": Color("5a3a7e"),
		"terrain": [Color("5a3a8e"), Color("7a5ab0"), Color("3e2670"), Color("2b1450"), Color("160a2a"), Color("ffd64a")],
		"water": [Color("000000"), Color("000000"), 0.0],
		"hills": [Color("000000"), Color("000000"), Color("000000")],
		"mountains": false, "backdrop": "sky",
		"props": "apocalypse", "particles": "embers",
		"crystal": Color("ffd64a"),
	},
	"skyislands": {
		"title": "Taivaansaaret",
		"sky_top": Color("2a6fe0"), "sky_bottom": Color("8cc8ff"), "sun_scatter": Color("504838"),
		"clouds": 0.4, "night": false,
		"sun_color": Color("fff4e0"), "sun_energy": 1.15, "sun_rot": Vector3(-45.0, 30.0, 0.0),
		"ambient": Color("a8c8f0"), "ambient_energy": 0.65,
		"fog": Color("9ccaf5"), "fog_density": 0.004,
		"terrain": [Color("63c740"), Color("8ad84a"), Color("9a7a5c"), Color("7d6048"), Color("4a3a2c"), Color("d9c09a")],
		"water": [Color("000000"), Color("000000"), 0.0],
		"hills": [Color("000000"), Color("000000"), Color("000000")],
		"mountains": false, "backdrop": "sky",
		"props": "sky", "particles": "pollen",
		"crystal": Color("ffe27a"),
	},
}

## Maailmat valikon kenttävalinnassa (kenttäindeksit 0-pohjaisia, loppu poissulkeva).
const WORLDS := [
	{"title": "VIHREÄT NIITYT", "subtitle": "Tasot 1–10", "from": 0, "to": 10, "color": Color("70d52f"), "edge": Color("3f9610"), "theme": "meadow", "boss": "NIITTYJÄTTI"},
	{"title": "JÄÄVUORET", "subtitle": "Tasot 11–20", "from": 10, "to": 20, "color": Color("66d0f1"), "edge": Color("1e8fbe"), "theme": "snow", "boss": "JÄÄAPINA"},
	{"title": "AAVIKKOMAA", "subtitle": "Tasot 21–30", "from": 20, "to": 30, "color": Color("f4a348"), "edge": Color("c86d1f"), "theme": "desert", "boss": "AAVIKON KUNINGAS"},
	{"title": "KARKKIMAA", "subtitle": "Tasot 31–40", "from": 30, "to": 40, "color": Color("ef62d2"), "edge": Color("b92f9f"), "theme": "candy", "boss": "KARKKIHIRVIÖ"},
	{"title": "TULIVUORET", "subtitle": "Tasot 41–50", "from": 40, "to": 50, "color": Color("ff6a3a"), "edge": Color("a02a10"), "theme": "volcano", "boss": "TULIVUOREN HERRA"},
	{"title": "APOKALYPSI", "subtitle": "Tasot 51–60", "from": 50, "to": 60, "color": Color("9b6bff"), "edge": Color("6a3bd6"), "theme": "apocalypse", "boss": "APINAKUNINGAS"},
	# Lisämaailmat (pelin alkuperäiset maailmat).
	{"title": "AVARUUS", "subtitle": "Tasot 61–70", "from": 60, "to": 70, "color": Color("9a6cff"), "edge": Color("4a2aa0"), "theme": "space", "boss": "AVARUUSAPINA"},
	{"title": "AURINKORANTA", "subtitle": "Tasot 71–80", "from": 70, "to": 80, "color": Color("ffc12e"), "edge": Color("c0700c"), "theme": "beach", "boss": "MERIROSVOAPINA"},
	{"title": "KRISTALLILUOLA", "subtitle": "Tasot 81–90", "from": 80, "to": 90, "color": Color("4fc6d8"), "edge": Color("1f6a7a"), "theme": "cave", "boss": "KRISTALLIAPINA"},
	{"title": "EKSOPLANEETTA", "subtitle": "Tasot 91–100", "from": 90, "to": 100, "color": Color("c27cf0"), "edge": Color("6a2aa0"), "theme": "exoplanet", "boss": "MUUKALAISAPINA"},
	{"title": "TAIVAANSAARET", "subtitle": "Tasot 101–110", "from": 100, "to": 1000, "color": Color("5fb3ff"), "edge": Color("2a5fa8"), "theme": "skyislands", "boss": "MYRSKYAPINA"},
]

## Tasojen nimet (pelin verkkosivun mukaan), indeksi = tason numero - 1.
const LEVEL_NAMES := [
	"Ensimmäinen pamaus", "Ritsakoulu", "Puinen torni", "Kukkakedon kätköt", "Kivisilta",
	"Kolme kaveria", "Nitisevä laituri", "Salaperäinen luola", "Viimeinen varoitus", "NIITTYJÄTTI",
	"Jäinen vastaanotto", "Liukas rinne", "Kapinoiva jääkuutio", "Jääpuikkoluola", "Kylmä kylä",
	"Kristalliloisto", "Hangensyöjä", "Jääkarhun jäljillä", "Sulava hetki", "JÄÄAPINA",
	"Kuuma hiekka", "Kaktuksen kosto", "Dyynien varjo", "Muinainen temppeli", "Kiehuva keidas",
	"Hiekka-aave", "Aurinkokivi", "Myrskyn silmä", "Viimeinen vesipisara", "AAVIKON KUNINGAS",
	"Sateenkaarisilta", "Karkkipuutarha", "Lakritsilinna", "Vaahtokarkkipilvi", "Karkkikauppa",
	"Sokerikristalliluola", "Purukumin pohja", "Suklaasuihku", "Karkkikuningattaren hovi", "KARKKIHIRVIÖ",
	"Savuava lähtö", "Laavavirta", "Obsidiaanitorni", "Tuliputous", "Tuhkakenttä",
	"Magmasydän", "Kuumat kivet", "Savuverho", "Viimeinen purkaus", "TULIVUOREN HERRA",
	"Halkeava taivas", "Myrskyn portti", "Varjojen metsä", "Kelluva linnake", "Tuhottu kylä",
	"Särkynyt kuu", "Viimeinen horisontti", "Kuninkaallinen vartija", "Valtaistuinsali", "APINAKUNINGAS",
	# Avaruus 61-70
	"Laukaisualusta", "Asteroidivyö", "Painovoimapyörre", "Kuun kääntöpuoli", "Tähtisilta",
	"Tähtisumun portti", "Mustan aukon reuna", "Kaksoisplaneetat", "Pyrstötähden kyyti", "AVARUUSAPINA",
	# Aurinkoranta 71-80
	"Hiekkalinna", "Palmujen varjossa", "Majakan juurella", "Laguuni", "Rantabileet",
	"Simpukkasaari", "Laskuvesi", "Kookoskukkula", "Myrskyvaroitus", "MERIROSVOAPINA",
	# Kristalliluola 81-90
	"Luolan suu", "Hehkusienet", "Tippukiviholvi", "Kristallikaivos", "Maanalainen järvi",
	"Kaikukammio", "Jalokivisuoni", "Pimeä kuilu", "Kristallisydän", "KRISTALLIAPINA",
	# Eksoplaneetta 91-100
	"Vieras maaperä", "Kaksi kuuta", "Itiöniitty", "Kristallitornit", "Painovoimakenttä",
	"Muukalaisten kylä", "Hehkuva viidakko", "Planeetan ydin", "Signaali avaruudesta", "MUUKALAISAPINA",
	# Taivaansaaret 101-110
	"Pilvien päällä", "Leijuvat saaret", "Tuulen tie", "Sateenkaaren pää", "Ukkospilvi",
	"Taivaan majakka", "Pudotus", "Pilvilinna", "Myrskyn silmä yllä", "MYRSKYAPINA",
]


## Tason nimi (1-pohjainen numero) tai tyhjä.
static func level_name(number: int) -> String:
	if number >= 1 and number <= LEVEL_NAMES.size():
		return LEVEL_NAMES[number - 1]
	return ""


## True, jos taso on pomotaso (joka 10.).
static func is_boss_level(number: int) -> bool:
	return number > 0 and number % 10 == 0


## Teema kentälle sen järjestysnumeron (1..) ja maaston perusteella.
# --- Valaistus -------------------------------------------------------------------
## Jokaisella teemalla oma tyylitelty valaistus ("valokalusto"):
##   key   = pääaurinko (väri, voimakkuus, kulma), varjot
##   fill  = vastakkaiselta puolelta tuleva värillinen täyttövalo (ei varjoja)
##   rim   = takaa kameraa kohti paistava reunavalo, joka piirtää hahmoille ja palikoille
##           kirkkaan ääriviivan
##   under = (valinnainen) alhaalta tuleva hehku, esim. laava tai kristallit
##   grade = väriluokittelu: varjojen ja kirkkaiden kohtien sävy (split toning)
## Kulmat: Vector3(kallistus, kierto, 0) asteina. Kamera katsoo -Z-suuntaan, joten
## kierto ~180 tarkoittaa "takaa kohti kameraa".
const LIGHTING := {
	"meadow": {
		"mood": "Kultainen aamu",
		"key": [Color("ffe2ad"), 1.35, Vector3(-40.0, 35.0, 0.0)],
		"fill": [Color("8fc4ff"), 0.35, Vector3(-12.0, -130.0, 0.0)],
		"rim": [Color("ffd27a"), 0.9, Vector3(-22.0, 165.0, 0.0)],
		"exposure": 1.0, "saturation": 1.18, "contrast": 1.08,
		"glow": [0.5, 0.05, 1.2],
		"grade": [Color("1c3a5e"), Color("fff1d8")],
	},
	"forest": {
		"mood": "Smaragdinen siimes",
		"key": [Color("ffe7a3"), 1.1, Vector3(-48.0, 40.0, 0.0)],
		"fill": [Color("6fd99a"), 0.45, Vector3(-10.0, -120.0, 0.0)],
		"rim": [Color("d8ff8a"), 0.75, Vector3(-25.0, 170.0, 0.0)],
		"exposure": 0.98, "saturation": 1.15, "contrast": 1.1,
		"glow": [0.55, 0.06, 1.15],
		"grade": [Color("12382a"), Color("fff6d6")],
	},
	"tropical": {
		"mood": "Kirkas keskipäivä",
		"key": [Color("fff6e0"), 1.45, Vector3(-62.0, 20.0, 0.0)],
		"fill": [Color("7ff0ff"), 0.45, Vector3(-15.0, -140.0, 0.0)],
		"rim": [Color("e8fff8"), 0.6, Vector3(-30.0, 175.0, 0.0)],
		"exposure": 1.02, "saturation": 1.25, "contrast": 1.06,
		"glow": [0.5, 0.05, 1.25],
		"grade": [Color("0a3a55"), Color("fffbe8")],
	},
	"canyon": {
		"mood": "Kultainen tunti",
		"key": [Color("ffbe6e"), 1.55, Vector3(-20.0, 55.0, 0.0)],
		"fill": [Color("9a7aff"), 0.35, Vector3(-10.0, -110.0, 0.0)],
		"rim": [Color("ff8a3a"), 1.05, Vector3(-15.0, 160.0, 0.0)],
		"exposure": 1.0, "saturation": 1.2, "contrast": 1.12,
		"glow": [0.6, 0.07, 1.1],
		"grade": [Color("3a1d4a"), Color("ffe6c0")],
	},
	"snow": {
		"mood": "Pakkasaamu",
		"key": [Color("ffe0e6"), 1.0, Vector3(-25.0, 35.0, 0.0)],
		"fill": [Color("86b0ff"), 0.5, Vector3(-12.0, -125.0, 0.0)],
		"rim": [Color("ffb0d4"), 0.85, Vector3(-20.0, 168.0, 0.0)],
		"exposure": 1.05, "saturation": 1.06, "contrast": 1.05,
		"glow": [0.55, 0.06, 1.2],
		"grade": [Color("23305e"), Color("fff4f8")],
	},
	"glacier": {
		"mood": "Revontulihämärä",
		"key": [Color("ffd0ee"), 0.85, Vector3(-20.0, 45.0, 0.0)],
		"fill": [Color("5ff0d4"), 0.55, Vector3(-8.0, -120.0, 0.0)],
		"rim": [Color("c08aff"), 1.05, Vector3(-18.0, 165.0, 0.0)],
		"exposure": 1.02, "saturation": 1.15, "contrast": 1.08,
		"glow": [0.7, 0.08, 1.05],
		"grade": [Color("1a1450"), Color("f6ecff")],
	},
	"space": {
		"mood": "Neonavaruus",
		"key": [Color("e8e0ff"), 0.9, Vector3(-35.0, 35.0, 0.0)],
		"fill": [Color("ff5ad8"), 0.55, Vector3(-5.0, -100.0, 0.0)],
		"rim": [Color("4ff0ff"), 1.35, Vector3(-15.0, 170.0, 0.0)],
		"exposure": 1.05, "saturation": 1.2, "contrast": 1.15,
		"glow": [0.85, 0.1, 0.95],
		"grade": [Color("1a0838"), Color("f0f4ff")],
	},
	"nebula": {
		"mood": "Turkoosi tähtisumu",
		"key": [Color("d8fff6"), 1.0, Vector3(-30.0, 40.0, 0.0)],
		"fill": [Color("3fe0c0"), 0.5, Vector3(-5.0, -110.0, 0.0)],
		"rim": [Color("ff7ab8"), 1.15, Vector3(-15.0, 165.0, 0.0)],
		"exposure": 1.05, "saturation": 1.2, "contrast": 1.12,
		"glow": [0.85, 0.1, 0.95],
		"grade": [Color("062a36"), Color("fff0f6")],
	},
	"beach": {
		"mood": "Lämmin iltapäivä rannalla",
		"key": [Color("ffd49a"), 1.3, Vector3(-30.0, 50.0, 0.0)],
		"fill": [Color("ff8ab4"), 0.4, Vector3(-8.0, -115.0, 0.0)],
		"rim": [Color("ffd05a"), 1.1, Vector3(-12.0, 160.0, 0.0)],
		"exposure": 1.0, "saturation": 1.22, "contrast": 1.1,
		"glow": [0.65, 0.08, 1.05],
		"grade": [Color("3a1450"), Color("ffe8cc")],
	},
	"cave": {
		"mood": "Kristallien hehku",
		"key": [Color("7f9cff"), 0.4, Vector3(-60.0, 25.0, 0.0)],
		"fill": [Color("d070ff"), 0.45, Vector3(-10.0, -120.0, 0.0)],
		"rim": [Color("50e8ff"), 1.2, Vector3(-15.0, 170.0, 0.0)],
		"under": [Color("40d8ff"), 0.7, Vector3(40.0, 20.0, 0.0)],
		"exposure": 1.12, "saturation": 1.25, "contrast": 1.14,
		"glow": [1.0, 0.12, 0.85],
		"grade": [Color("0e0830"), Color("e8fbff")],
	},
	"volcano": {
		"mood": "Laavan loimu",
		"key": [Color("ffc8a0"), 0.75, Vector3(-28.0, 40.0, 0.0)],
		"fill": [Color("8a6aff"), 0.45, Vector3(-10.0, -120.0, 0.0)],
		"rim": [Color("ffd060"), 1.0, Vector3(-15.0, 165.0, 0.0)],
		"under": [Color("ff5a20"), 0.65, Vector3(38.0, 30.0, 0.0)],
		"exposure": 0.92, "saturation": 1.05, "contrast": 1.14,
		"glow": [0.8, 0.1, 1.0],
		"grade": [Color("3a0a14"), Color("fff0d8")],
	},
	"exoplanet": {
		"mood": "Vieras hämärä",
		"key": [Color("ffd0f0"), 1.0, Vector3(-30.0, 35.0, 0.0)],
		"fill": [Color("7a5aff"), 0.5, Vector3(-8.0, -115.0, 0.0)],
		"rim": [Color("a8ff60"), 1.05, Vector3(-15.0, 168.0, 0.0)],
		"exposure": 1.02, "saturation": 1.2, "contrast": 1.12,
		"glow": [0.75, 0.09, 1.0],
		"grade": [Color("1e0a40"), Color("fff0fa")],
	},
	"desert": {
		"mood": "Paahtava keskipäivä",
		"key": [Color("ffe2a0"), 1.2, Vector3(-55.0, 40.0, 0.0)],
		"fill": [Color("8a7aff"), 0.35, Vector3(-10.0, -120.0, 0.0)],
		"rim": [Color("ffd64a"), 0.95, Vector3(-20.0, 165.0, 0.0)],
		"exposure": 0.92, "saturation": 1.1, "contrast": 1.1,
		"glow": [0.5, 0.06, 1.2],
		"grade": [Color("4a2a10"), Color("fff0d0")],
	},
	"candy": {
		"mood": "Sokerinen unelma",
		"key": [Color("fff0f6"), 1.2, Vector3(-40.0, 30.0, 0.0)],
		"fill": [Color("c9a0ff"), 0.5, Vector3(-10.0, -125.0, 0.0)],
		"rim": [Color("ffd64a"), 1.0, Vector3(-20.0, 165.0, 0.0)],
		"exposure": 1.04, "saturation": 1.2, "contrast": 1.04,
		"glow": [0.7, 0.09, 1.05],
		"grade": [Color("4b1646"), Color("fff0fa")],
	},
	"apocalypse": {
		"mood": "Repeävä taivas",
		"key": [Color("ffc88a"), 0.95, Vector3(-30.0, 40.0, 0.0)],
		"fill": [Color("9a5aff"), 0.55, Vector3(-8.0, -115.0, 0.0)],
		"rim": [Color("ffd64a"), 1.25, Vector3(-15.0, 168.0, 0.0)],
		"exposure": 1.05, "saturation": 1.18, "contrast": 1.14,
		"glow": [0.9, 0.11, 0.95],
		"grade": [Color("1a0b2e"), Color("fff0d8")],
	},
	"skyislands": {
		"mood": "Pastellinen unelma",
		"key": [Color("fff0d8"), 1.2, Vector3(-38.0, 30.0, 0.0)],
		"fill": [Color("c0b0ff"), 0.45, Vector3(-10.0, -125.0, 0.0)],
		"rim": [Color("ffc8a0"), 0.95, Vector3(-20.0, 165.0, 0.0)],
		"exposure": 1.05, "saturation": 1.12, "contrast": 1.04,
		"glow": [0.65, 0.09, 1.1],
		"grade": [Color("2a2a66"), Color("fff6ec")],
	},
}


## Teeman valaistus (tai niittyjen, jos teemalle ei ole omaa).
static func lighting_for(theme: String) -> Dictionary:
	return LIGHTING.get(theme, LIGHTING["meadow"])


## Väriluokittelun käyrä: varjot kohti `shadow`-sävyä, kirkkaat kohdat kohti `highlight`-sävyä.
## HUOM: ei tällä hetkellä käytössä – Compatibility-renderöijässä tämä latisti taivaan
## värit. Jätetty tänne, jos väriluokittelua halutaan kokeilla myöhemmin.
static func grade_texture(shadow: Color, highlight: Color) -> GradientTexture1D:
	var key := "grade/%s/%s" % [shadow.to_html(), highlight.to_html()]
	if _cache.has(key):
		return _cache[key]
	var g := Gradient.new()
	# Hillitty: varjoihin vain vähän sävyä, keskisävyt lähes ennallaan.
	var low := Color(0.0, 0.0, 0.0).lerp(shadow, 0.55)
	var mid := Color(0.5, 0.5, 0.5).lerp((shadow + highlight) * 0.5, 0.12)
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([low, mid, highlight])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	_cache[key] = tex
	return tex


static func theme_for_level(number: int, _ground: String = "") -> String:
	var themes := [
		# Vihreät niityt 1-10
		"meadow", "meadow", "forest", "meadow", "tropical", "meadow", "tropical", "cave", "forest", "meadow",
		# Jäävuoret 11-20
		"snow", "snow", "glacier", "cave", "snow", "glacier", "snow", "snow", "glacier", "glacier",
		# Aavikkomaa 21-30
		"desert", "desert", "canyon", "desert", "canyon", "desert", "desert", "canyon", "desert", "desert",
	]
	if number >= 1 and number <= themes.size():
		return themes[number - 1]
	if number <= 40:
		return "candy"
	if number <= 50:
		return "volcano"
	if number <= 60:
		return "apocalypse"
	if number <= 70:
		return "space" if number <= 65 else "nebula"
	if number <= 80:
		return "tropical" if number % 3 == 0 else "beach"
	if number <= 90:
		return "cave"
	if number <= 100:
		return "exoplanet"
	return "skyislands"


static func world_for_level(index: int) -> Dictionary:
	for world in WORLDS:
		if index >= int(world["from"]) and index < int(world["to"]):
			return world
	return WORLDS[0]


# --- Materials ---------------------------------------------------------------

static var _cache: Dictionary = {}


## Palikan materiaali tyypin ja koon mukaan (sama koko = sama materiaali).
static func block_material(kind: String, size: Vector3) -> ShaderMaterial:
	var key := "block/%s/%.2f/%.2f/%.2f" % [kind, size.x, size.y, size.z]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	var seed := float(hash(key) % 997) * 0.37
	match kind:
		"ice":
			material.shader = BLOCK_ICE
			material.set_shader_parameter("base_color", ICE["base"])
			material.set_shader_parameter("rim_color", ICE["rim"])
		"stone":
			material.shader = BLOCK_SOLID
			material.set_shader_parameter("kind", 1)
			material.set_shader_parameter("base_color", STONE["base"])
			material.set_shader_parameter("light_color", STONE["light"])
			material.set_shader_parameter("dark_color", STONE["dark"])
		_:
			material.shader = BLOCK_SOLID
			material.set_shader_parameter("kind", 0)
			material.set_shader_parameter("base_color", WOOD["base"])
			material.set_shader_parameter("light_color", WOOD["light"])
			material.set_shader_parameter("dark_color", WOOD["dark"])
	material.set_shader_parameter("box_size", size)
	material.set_shader_parameter("seed", seed)
	material.set_shader_parameter("bevel", clampf(minf(size.x, minf(size.y, size.z)) * 0.12, 0.04, 0.1))
	_cache[key] = material
	return material


## Maastomateriaali teemalle. `world_top_y` maalaa reunan yläosan nurmeksi/lumeksi.
static func terrain_material(theme: String, world_top_y: float = -1000.0, lip: float = 0.06, key_suffix: String = "") -> ShaderMaterial:
	var key := "terrain/%s/%.2f/%.2f/%s" % [theme, world_top_y, lip, key_suffix]
	if _cache.has(key):
		return _cache[key]
	var t: Array = THEMES[theme]["terrain"]
	var material := ShaderMaterial.new()
	material.shader = TERRAIN
	material.set_shader_parameter("top_a", t[0])
	material.set_shader_parameter("top_b", t[1])
	material.set_shader_parameter("side_a", t[2])
	material.set_shader_parameter("side_b", t[3])
	material.set_shader_parameter("deep_color", t[4])
	material.set_shader_parameter("speck_color", t[5])
	material.set_shader_parameter("top_local_y", 100000.0)
	material.set_shader_parameter("world_top_y", world_top_y)
	material.set_shader_parameter("lip", lip)
	_cache[key] = material
	return material


static func water_material(theme: String) -> ShaderMaterial:
	var key := "water/" + theme
	if _cache.has(key):
		return _cache[key]
	var w: Array = THEMES[theme]["water"]
	var material := ShaderMaterial.new()
	material.shader = WATER
	material.set_shader_parameter("deep_color", w[0])
	material.set_shader_parameter("shallow_color", w[1])
	material.set_shader_parameter("frozen", w[2])
	_cache[key] = material
	return material


static func lava_material() -> ShaderMaterial:
	if _cache.has("lava"):
		return _cache["lava"]
	var material := ShaderMaterial.new()
	material.shader = LAVA
	_cache["lava"] = material
	return material


static func planet_material(color: Color, seed: float, glow: float = 0.35) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PLANET
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("rim", color.lightened(0.55))
	material.set_shader_parameter("seed", seed)
	material.set_shader_parameter("glow", glow)
	return material


static func field_material(color: Color, pulling: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FIELD
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("direction", 1.0 if pulling else -1.0)
	return material


## Pehmeä kaksisävyinen materiaali taustarekvisiitalle.
static func soft_material(color: Color, top_tint: Color = Color.WHITE, use_vertex_color: bool = false, tint_height: float = 10.0, tint_base: float = 0.0, emission: float = 0.0) -> ShaderMaterial:
	var key := "soft/%s/%s/%s/%.1f/%.1f/%.2f" % [color.to_html(), top_tint.to_html(), use_vertex_color, tint_height, tint_base, emission]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = SOFT
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("top_tint", top_tint)
	material.set_shader_parameter("use_vertex_color", 1.0 if use_vertex_color else 0.0)
	material.set_shader_parameter("tint_height", tint_height)
	material.set_shader_parameter("tint_base", tint_base)
	material.set_shader_parameter("emission_amount", emission)
	_cache[key] = material
	return material


## Yksinkertainen standardimateriaali (värillinen, valinnainen hehku).
static func flat_material(color: Color, roughness: float = 0.8, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "flat/%s/%.2f/%.2f/%s" % [color.to_html(), roughness, emission, unshaded]
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = material
	return material


## Palikan materiaalityyppi solmun nimen tai sirujen värin perusteella.
static func block_kind(block: Node) -> String:
	var lower := String(block.name).to_lower()
	for kind in ["wood", "stone", "ice", "glass"]:
		if lower.begins_with(kind):
			return "ice" if kind == "glass" else kind
	var c: Variant = block.get("debris_color")
	if c is Color:
		var color := c as Color
		if color.b > color.r + 0.15:
			return "ice"
		if absf(color.r - color.b) < 0.12:
			return "stone"
	return "wood"
