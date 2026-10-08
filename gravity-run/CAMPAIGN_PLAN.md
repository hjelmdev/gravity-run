# Gravity Run – kampanjläge (plan, 2026-10-08)

Planen beskriver ett kampanjläge med fasta banor som blir svårare steg för steg, en
världskarta, guldföremål och hemligheter, bossar och achievements. Den är skriven så att
den kan implementeras i faser. Varje fas är spelbar för sig.

Mockup av kartan: `docs/campaign_map_mockup.png` (en skiss, inte slutlig grafik).

---

## 1. Grundidé

- **Fyra världar**, en per biom: Ängen (classic), Grottan (cave), Spökskogen (haunted)
  och Vulkanen (lava).
- **Sex banor plus en boss per värld**, totalt 24 banor och 4 bossar.
  - Bana 1–5 introducerar och kombinerar hinder.
  - Bana 6 är världens examen.
  - Bossen låser upp nästa värld.
- **Biomet byts aldrig inom en kampanjbana.** I dag byter banan biom var 4 800 px. I
  kampanjen låses biomet (se 4.2).
- **Banorna är alltid identiska.** Varje bana har en permanent seed, ett regelverk och en
  generatorversion, eller en "frusen" händelselista (se 4.1). Samma bana ger samma
  hinder, mynt och guld varje gång och för alla spelare.
- **Banorna har ett mål.** En målflagga efter en fast längd ersätter dagens ändlösa
  löpning. Längden är 30–75 sekunder vid 500 px/s, vilket blir 15 000–37 500 px.

## 2. Spelarens loop

1. Kartan visar världens sju noder, förbundna med en stig. Avataren (vald karaktär och
   utseende) står på senast valda nod.
2. Klarade noder visar sina guldföremål (●●○). Nästa olåsta nod lyser, låsta noder är grå
   med hänglås men syns.
3. Spelaren väljer nod, ser ett kort ("1-4 Fallande stenar · Nytt hinder: fallande sten
   · Bästa: 1 240 p") och trycker **Spela**.
4. Dör man startar banan om från början, eller från checkpoint (se 3.3). Når man målet
   visas en resultatskärm med poäng, guld x/3, hemlighet och personbästa, och nästa nod
   låses upp. Avataren går längs stigen till nästa nod.
5. Klarade banor kan spelas om för bättre poäng, saknat guld eller hemligheter.

## 3. Mål och belöningar per bana

### 3.1 Tre guldföremål per bana
Namnet är inte bestämt. Förslag: **Gravitationsstjärnor**, **Guldkugghjul** eller
**Kometsplitter**.
- De ligger på fasta, handplacerade positioner. Minst ett ligger "fel" sida eller nära
  ett hinder, så att man måste välja en riskabel fil eller flippa mitt i en sekvens.
- Ett plockat guld räknas bara om man också når målet. Då lönar det sig inte att plocka
  och sedan dö med flit.

### 3.2 Hemlighet (en per bana, inte på alla banor i början)
- Ett gömt föremål på en plats man normalt inte är på, till exempel taket i en
  sektion där golvet känns naturligt, eller bakom en mur som bara nås via en lucka.
- Belöning: kosmetiskt. Alla hemligheter i en värld låser upp en karaktär eller ett
  utseende. Förslag: Ängen ger Flinka (räv), Grottan Pingo, Spökskogen Misse och Vulkanen Bit.

### 3.3 Poäng och liv
- **Poäng** = mynt × 10 + guld × 500 + hemlighet × 1 000 + bonus för noll dödsfall.
  Farten är konstant, så tid används inte i poängen.
- **Checkpoint** från bana 4 i varje värld, i mitten av banan. Den nollställer guld
  plockat efter checkpointen och ger ingen bonus för noll dödsfall.
- **Inga liv eller game over** på kartnivå. Det passar en webb- och mobilrunner bäst.

### 3.4 Medaljer per bana (visas på kartnoden)
- Klar, alla tre guld, och "perfekt" (utan att dö och med hemligheten). Det blir tre ikoner
  under noden.

## 4. Teknik

### 4.1 Hur banorna definieras
Arkitekturen är redan förberedd: `CourseRunDefinition` säger uttryckligen att kampanjsteg
kan vara resurser med permanent seed och regelverk.

**Rekommendation: generera, välj, frys och finjustera.**
1. Ett verktyg (`tools/campaign/search_level.gd`) provar många seeds med banans regelverk
   och betygsätter dem: hinderantal, lösbarhet vid 500–750 px/s, inga orimliga hopp, att
   rätt hinder introduceras.
2. Den bästa seeden **fryses** till en datafil (`campaign/levels/1-4.tres`) med den
   färdiga händelselistan (källhändelser för `CourseManifestBuilder`). Då påverkar
   framtida generatorändringar aldrig befintliga banor.
3. Guld, hemlighet, checkpoint och mål läggs till för hand i samma fil.
4. Vid laddning körs den frysta listan genom samma resolver och manifest som MP. Den
   valideras med `is_plan_solvable` och de befintliga säkerhetsfiltren, så kampanjen
   använder exakt samma hindermodeller som resten av spelet.

`CampaignLevel` (Resource):
```
id: "1-4"            world: &"classic"          title_key: "Fallande stenar"
length_px: 22000     source_events: Array[Dictionary]  (frusen)
generator_version: 21   ruleset: CourseGenerationRuleset (för fingeravtryck)
golden: [ {x, lane}, {x, lane}, {x, lane} ]   secret: {x, lane, reward_id}
checkpoint_x: -1 | px      new_hazards: ["falling_rock"]   coin_layout: auto | frusen
par_score: int       boss: null | CampaignBoss
```
`CampaignWorld` (Resource): id, biom, titel, kartlayout (nodpositioner och stig),
musik, `levels[6]`, `boss`, och karaktären eller skinet man får för alla hemligheter.

### 4.2 Biomlås
- Lägg till `locked_biome: StringName` i regelverket. Det ingår i fingeravtrycket, så det
  ger en ny banidentitet.
- `CourseGenerator._biome_id_at()` returnerar det låsta biomet när fältet är satt.
  Hinder som är låsta till ett biom (spöken i Spökskogen, lava i Vulkanen) fungerar då
  automatiskt.
- `BiomeRenderer.definition_for_generator()` får en motsvarande parameter, så att
  bakgrund, ytor och väder stannar i biomet.
- Befintliga generatorversioner, seeds och MP påverkas inte, eftersom fältet är tomt där.

### 4.3 Körning i `main.gd`
- Ett `scenario_id = &"campaign"` sätter en målflagga vid `length_px`: hinder slutar spawna
  innan målet, och löparen springer i mål och saktar in. Det triggar en ny
  `run_end_panel`-variant med "Bana klar".
- Guld och hemlighet spawnas som pickups, med en ny variant av `collectibles/coin.tscn`
  med egen grafik och eget ljud.
- Checkpoint: spara banans tillstånd vid `checkpoint_x` (tick, position, plockat). Vid
  död startar `_start_run` från checkpointens distans.
  - Simuleringen är distansbaserad, så det räcker att generera fram till samma punkt.
  - **Risk:** hinder som triggas före checkpointen och lever efter den. Lösningen är att
    placera checkpointen i en hinderfri sektion, och verktyget kontrollerar det.
- Hinderintroduktion: första gången ett hinder i `new_hazards` syns visas ett kort utrop
  ("Ny: fallande sten!") och kameran zoomar ut lite. Det är bara presentation.

### 4.4 Kartan (`ui/campaign/world_map.gd`)
- En helskärm med världens biom som bakgrund. Den återanvänder `BiomeRenderer`-bakgrunden
  statiskt, eller en egen målad bild per värld senare.
- Stigen och noderna kommer från `CampaignWorld.map_nodes` (positioner i 960×540-rymden),
  ritade med `_draw()`. Det är billigt, eftersom kartan är statisk.
- Avataren är vald `CharacterDefinition` plus skinet, som går längs stigen i
  springanimationen när man väljer nod. Kort och knappen **Spela** ligger nere till höger.
- Världsbyte görs med pilar eller svep. Låsta världar visas som silhuett med "Besegra
  bossen i Ängen".
- Kontroller: tangentbord (←/→ mellan noder, Enter spelar), mus och touch.

### 4.5 Progress och lagring
- **Lokalt (gäst):** `PlayerProfile` får en `campaign`-sektion:
  `{level_id: {best_score, golden_mask, secret, perfect, completions}}`.
- **Inloggad:** en Supabase-tabell `campaign_progress (user_id, level_id, best_score,
  golden_mask, secret_found, perfect, completions, updated_at)` med RPC:n
  `submit_campaign_result(level_id, level_fingerprint, score, golden_mask, ...)`.
  - Servern tar alltid max eller OR med det som redan finns och avvisar okänd
    `level_fingerprint`.
  - Vid inloggning slås gästprogress ihop uppåt.
- **Topplista per bana:** den kan återanvända seed-challenge-infrastrukturen, eftersom
  banans identitet är generatorversion + fingeravtryck + seed.
- **Fusk:** till en början litar servern på klienten, som för seed-challenges i dag. Senare
  kommer replay-verifiering enligt backloggen, med headless uppspelning som i Block Pact.

## 5. Svårighetskurva (förslag)

Regelverkets rattar: `event_density`, `reaction_margin`, `hazard_size`,
`lane_alternation`, `included_profile_ids` och `profile_weight_multipliers`. Längden
anges i px vid 500 px/s.

| Bana | Ängen (classic) | Grottan (cave) | Spökskogen (haunted) | Vulkanen (lava) |
|---|---|---|---|---|
| 1 | spikar + block, täthet 0,7, marginal 1,5 | ytgrund + stenar | spikar + spöke (jagare) | lavaspricka |
| 2 | + luckor i golv/tak | + istappar | + svävande spöke (flyby) | + trappsteg vid lava |
| 3 | + tunnor | + trappsteg/sluttningar | + sågar | + vulkan (solfjäder) |
| 4 | + trappsteg/sluttning, checkpoint | + spikade tunnor | + förföljande spöke (pursuit) | + tidvattenpool |
| 5 | + fallande sten + såg | mix, täthet 1,3 | mix, täthet 1,4 | mix, täthet 1,5 |
| 6 | examen: allt, täthet 1,2, marginal 1,0 | examen 1,5 | examen 1,6 | examen 1,8, marginal 0,85 |

- Längden ökar från cirka 15 000 px (1-1) till cirka 37 500 px (4-6).
- Senare världar börjar något svårare än förra världens bana 6, men bana 1 i varje värld
  är alltid "lugn" med ett nytt hinder.

## 6. Bossar (skiss)

En löpare springer alltid, så en boss är ett manus: bossen hänger kvar vid skärmkanten
och "attackerar" med befintliga hindermodeller enligt ett deterministiskt schema. Man
skadar den genom att flippa genom **svaga punkter** (lysande plattor eller kristaller),
som dyker upp i en fil i taget. Tre träffar besegrar bossen. Bossen är alltså en
kampanjbana med `boss`-data. Ingen ny fysik behövs, bara presentation och schemalagda
hinder.

| Värld | Boss | Attacker (befintliga modeller) | Svag punkt |
|---|---|---|---|
| Ängen | **Rullaren**, en stor maskin till höger som skickar ut tunnor | tunnkedjor, spikade tunnor, block som "spottas" ut | en tryckplatta i golvet efter varje tunnvåg |
| Grottan | **Stalaktitjätten**, en fladdermus i taket | istappar och fallande stenar i mönster | en kristall i taket när den dyker |
| Spökskogen | **Spökkungen**, som speglar din fil med fördröjning | flyby och pursuit, lyktor som släcks | lockas in i en lykta: flippa precis innan den låser |
| Vulkanen | **Magmaormen**, som reser sig ur lavan bakom dig | vulkansolfjädrar, sprickor, tidvatten | glödande fjäll som exponeras efter varje solfjäder |

- Faser: fas 1 (3 attacker, sedan svag punkt) → fas 2 (snabbare) → fas 3 (blandat). Varje
  fas har en checkpoint.
- Rullaren först: den använder bara tunnor och block, som redan har bäst simulering och
  render-interpolation, och blir mallen för de andra.
- Grafik: placeholder (en stor sprite och en ram-animation) tills art finns.

## 7. Achievements

Kräver en migration som utökar `achievement_metric_supported` (och `scope_key` per värld).

| Achievement | Metrik | Scope |
|---|---|---|
| Första steget – klara 1-1 | `campaign_levels_completed` ≥ 1 | – |
| Världsvandrare – klara en hel värld (inkl. boss) | `campaign_world_completed` | värld |
| Guldgrävare – 10 / 30 / 72 guld | `campaign_golden_total` | – |
| Allt guld i en värld | `campaign_world_golden` = 18 | värld |
| Hemlighetsjägare – alla hemligheter i en värld | `campaign_world_secrets` = 6 | värld |
| Bosskrossare – besegra varje boss | `campaign_boss_defeated` | värld |
| Felfri – klara en bana utan att dö (med checkpoint-banor) | `campaign_perfect_levels` | – |
| Kampanjmästare – allt guld + alla hemligheter | `campaign_complete_100` | – |

Nya metriker räknas från `campaign_progress` på servern, alltså samma mönster som
`achievements.sql`, så upplåsningen blir idempotent.

## 8. Faser

| Fas | Innehåll | Klart när |
|---|---|---|
| **0 – grunden** | `CampaignLevel`/`CampaignWorld`, biomlås, målflagga, "Bana klar"-skärm, banlista som enkel meny, 3 banor i Ängen | man kan spela 1-1 → 1-3 i ett fast biom till mål |
| **1 – kartan** | världskarta, avatar, låsta noder, guld (3/bana), lokal progress, resten av Ängen | Ängen 1-1…1-6 spelbar från kartan, guld sparas |
| **2 – verktyg och innehåll** | seed-sökare, frysning, validering, banor för alla 4 världar | 24 banor som klarar valideringen |
| **3 – backend** | `campaign_progress` + RPC, topplista per bana, gästsammanslagning, achievements-migration | progress följer kontot, achievements låses upp |
| **4 – bossar** | Rullaren (mall), sedan övriga | Ängen kan avslutas med boss, nästa värld låses upp |
| **5 – hemligheter och belöningar** | hemligheter, karaktärsupplåsning per värld, medaljer på kartan | alla hemligheter i Ängen låser upp Flinka |

Fas 0 och 1 kan jag göra direkt när du säger till. Fas 3 kräver att Gravity Runs
Supabase-projekt är åtkomligt för mig, eller att Codex kör migrationerna.

## 9. Beslut som behöver dig

1. **Namn på guldföremålen** (förslag i 3.1).
2. **Checkpoints** från bana 4, eller inga alls ("varje bana i ett svep")?
3. **Banlängd:** 30–75 sekunder är förslaget. Kortare eller längre?
4. **Karaktärsegenskaper i kampanjen:** samma för alla, eller ska egenskaper påverka?
   Det påverkar topplistor per bana.
5. **Vad hemligheterna låser upp:** karaktärer, utseenden eller något nytt
   (till exempel spår vid flip)?
6. **Bossarna:** ska Rullaren testas först som prototyp innan vi bestämmer resten?
