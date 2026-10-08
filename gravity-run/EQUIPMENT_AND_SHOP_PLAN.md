# Utrustning och shop – idéplan (2026-10-08)

Allt här ska provas. Vi behåller det som är roligt efter speltest. Grafiken hålls enkel: ikoner och små effekter ritade i kod räcker.

## Beslut
- **Multiplayer:** värden väljer en toggle i lobbyn, *Utrustning på/av*. På betyder att allas prylar gäller, så den som har grindat fram snabba skor får använda dem mot kompisarna. Av betyder att alla kör utan prylar.
- **Seed-utmaningar och topplistor:** en körning sparas med flaggan `modified`. Topplistan visar då *Ren* eller *Med utrustning*.
- **Skydd laddas om över tid.** Ett skydd används, är "tomt" en stund och blir sedan redo igen. Ikonen i HUD:en fylls upp medan det laddas. Skydd gäller alla dödliga hinder, inte en enda sorts hinder.
- **Stjärnkompass behövs inte.** HUD:ens förloppsmätare visar redan var stjärnorna ligger.

## Platser
| Plats | Roll |
|---|---|
| Hjälm | Skydd som laddas om |
| Skor | Rörelse (flip, landning, luft) |
| Ryggsäck | Ekonomi och upplockning, plus en aktiv förmåga |
| Spår | Kosmetiskt, efterbild vid flip |
| Följeslagare | Plockar mynt du missar, kosmetisk karaktär |

## Prylar att prova
**Hjälmar (skydd som laddas om)**
- *Bubbelhjälm:* tål en träff och laddar om på 20 s. Nivå 2–3 ger kortare tid.
- *Studshjälm:* en träff kastar dig till andra sidan i stället för att döda. Laddar om på 25 s.
- *Spikplåt:* immun mot spikar i 1 s efter varje flip. Har ingen laddtid men gäller bara spikar.

**Skor (rörelse)**
- *Gravitationsstövlar:* flipcooldown −15 %, men landningen blir hårdare med en kort skärmskakning.
- *Fjäderskor:* en studs när du landar, alltså en extra chans att byta sida.
- *Ångerskor (mittflip):* du kan vända tillbaka mitt i en flip. Det här är Adams idé.
- *Halkskydd:* längre "coyote time" vid kanter och hål.

**Ryggsäck (aktiv förmåga + ekonomi)**
- *Gravitationsankare:* lås dig mitt i luften och glid längs mitten av banan i 1 s. Laddar om på 15 s.
- *Svävkappa:* håll inne för att hänga kvar en kort stund i luften.
- *Myntmagnet:* radien växer med nivån.
- *Turamulett:* fler riskrader med mynt.
- *Ekolod:* varning för stenar och spöken kommer 0,3 s tidigare och syns utanför skärmen.

**Biomnycklar** (bara i sin egen värld)
- *Isdubbar* för Grottan, *värmesköld* för Vulkanen, *lykta* för Spökskogen. Varje nyckel tar udden av världens farligaste hinder.

**Förbannade prylar** (stor fördel, tydlig nackdel)
- *Blyskor:* +50 % mynt men tyngre flip.
- *Mörkerhjälm:* dubbla poäng men du ser bara halva skärmen framåt.
- *Spegelglasögon:* banan spegelvänds, dubbla mynt.

**Engångssaker** (köps före en runda)
- *Extraliv* i endless (körningen räknas som modifierad).
- *Startraket:* de första 1 000 px körs automatiskt.
- *Dubbla mynt* i en runda.

**Kosmetika**
- Spår vid flip: regnbåge, eld, löv och pixeldamm.
- Följeslagare.
- Spöke av ditt personbästa.

## Shop
- **Mynt** köper vanliga prylar och engångssaker.
- **Gravitationsstjärnor** låser upp sällsynta saker (figurer, spår, bossprylar) och går inte att köpa.
- **Nivåer:** varje pryl har 1–3 nivåer och ser synligt finare ut för varje nivå.
- **Set-bonus:** tre delar ur samma tema ger en liten extra bonus.
- **Bossdelar:** Rullarens kugghjul smids till en unik pryl.
- **Dagens erbjudande:** en roterande pryl i shoppen.
- **Provkörning:** testa en pryl en runda innan du köper.

## Teknik (redan på plats / behövs)
- **Finns redan:** `InventoryService`, `RunLoadoutSnapshot` och `EquipmentStats` med `run_speed_percent` och `flip_cooldown_percent`, plus platserna hjälm och skor.
- **Prylar i kod:** varje pryl blir en `ItemDefinition` med effekt-id. En `RunEffects`-modul i `main.gd` och `player.gd` hanterar laddtider och skydd.
- **HUD:** en ikonrad med laddmätare.
- **Multiplayer:** en lobbyflagga plus att utrustningen följer med i positionspaketen. Värden validerar att den tillåts.
- **Backend:** ägda prylar och nivåer på servern (RPC drar mynt), samt flaggan `modified` på inskickade körningar.

## Förslag på ordning
1. Bubbelhjälm, spikplåt och myntmagnet. De går att bygga i dagens system.
2. Ångerskor och gravitationsankare, eftersom de är nya rörelser och behöver mest speltest.
3. Lobbytoggle och `modified`-flaggan.
4. Biomnycklar tillsammans med fas 3 i kampanjen.
