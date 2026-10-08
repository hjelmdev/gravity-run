# Värld 2 – Grottan

Plan för kampanjens andra värld. Den bygger på samma mall som Ängen: sex banor, en boss,
data i `CampaignCatalog`, frysta seeds och stjärnor från `campaign_level_tool.gd`.
Kartan (`map_cave.png`) och kartnoderna (`CAVE_MAP_NODES`) finns redan.

## 1. Vad som skiljer Grottan från Ängen

- **Spelaren kan redan allt.** Ängen har lärt ut alla generella hinder. Grottan börjar
  därför ungefär på 1-4:s nivå och lär ut en enda ny generatorsak: **istappar**
  (`cave_icicle`, en takfäst sten som bara finns i cave-mixen).
- **Generatorn ändras inte.** Kampanjen kör generator 21. Nya hinder i generatorn kräver
  en ny generatorversion, så grottans egna överraskningar görs som **skriptade
  inslag** från `campaign_run.gd`, på samma sätt som Rullarens attacker
  (`pop_boss_events`). Då kan vi lägga in grottsaker på exakt bestämda ställen utan att
  röra endless.
- **Biomet är det riktiga `cave`.** Encounter-mixen för cave höjer redan fallande stenar och
  sågar. Det finns ingen separat presentationsbiom som för ängen, men däremot ett
  grottlyft av utseendet (se 4).

## 2. Banorna (30–48 s)

| Bana | Titel | Nytt | Täthet / marginal | Längd |
|---|---|---|---|---|
| 2-1 | Droppstenar | istappar | 1,0 / 1,3 | 16 500 |
| 2-2 | Trånga gångar | trappsteg och backar tätare (terrängvikt ×2) | 1,1 / 1,2 | 18 000 |
| 2-3 | Rullgruvan | rullande tunnor i grottan, med gruvvagnar som skin | 1,2 / 1,15 | 19 500 |
| 2-4 | Ras | fallande stenar + istappar i par (skriptat ”ras”) | 1,3 / 1,1 | 21 000 |
| 2-5 | Kristallsalen | mörk sal: kristaller lyser upp när du passerar | 1,4 / 1,05 | 22 500 |
| 2-6 | Grottprovet | allt | 1,5 / 1,0 | 24 000 |
| 2-B | Stalaktitjätten | boss | – | – |

Varje bana får ”Nytt hinder”-banner, tre gravitationsstjärnor och kontroll av
golv- och takhål (`gap_conflicts`), precis som i Ängen.

## 3. Skriptade grottinslag (förslag, välj vilka)

1. **Ras.** En varningsrad av damm i taket, sedan faller 3–4 stenar i följd. Bygger på
   befintlig `falling_rock`.
2. **Fladdermussvärm.** En svärm flyger längs ena filen en kort stund, så du måste vara på
   den andra sidan. Det här blir ett nytt men enkelt hinder: en rektangel med animation.
3. **Mörker.** En kort sektion där bara ett ljussken runt löparen syns, och kristaller
   lyser när du passerar. Inslaget påverkar bara utseendet och syns i 2-5. Det är viktigt
   att hindren inom 250 px alltid syns.
4. **Gruvvagnar.** Ett skin på `barrel_chain` i grottan. Inslaget påverkar bara utseendet.

## 4. Utseende och ljud

- **Bakgrund:** dagens ridge-backdrop plus stalaktitsiluetter i parallax, droppar som
  faller i bakgrunden och lysande kristaller (blå `8fb4ff` och lila). Taket och golvet
  använder cave-tiles.
- **Musik:** genereras som ängens (`tools/audio/`), men i moll med ekande chiptune, droppande
  perkussion och 150 BPM. Löparen synkas till takten som på ängen.
- **Ljud:** istapp som knäcks, ett rasmuller och en kristallklang för stjärnorna i grottan.

## 5. Bossen: Stalaktitjätten (2-B)

En jättefladdermus hänger i taket och följer med framför löparen.

- **Attacker** (schemalagda som Rullarens `PHASES`):
  1. Istappsrader: 2–4 istappar faller i ett mönster längs taket.
  2. Den slår med vingarna, och stenar faller i golvfilen medan istappar faller i taket
     om vartannat.
  3. **Dyket:** fladdermusen störtar längs en fil, och en röd varningsstrimma visar vilken.
     Du flippar bort.
- **Svag punkt:** efter varje dyk sitter den fast ett ögonblick, och en **kristall** lyser
  på golvet eller i taket. Spring igenom kristallen på rätt sida, så krossas den och
  ekot bedövar bossen. Det fungerar som Rullarens tryckplattor, så `PressurePlate` och
  `observe_runner` kan återanvändas. Bossen har 3 HP, och farten ökar per träff.
- **Testbot:** samma typ av bot som för Rullaren, som klarar bossen två gånger i
  `campaign_runtime_test`.

## 6. Arbetsordning

1. Lägg in `CAVE_STAGES` i katalogen. Låt nivåverktyget ta emot värld och biom
   (`cave`), sök seeds och frys stjärnorna.
2. Bygg grottlyftet av utseendet (stalaktiter, kristaller, droppar), grottmusiken och
   ljuden.
3. Bygg de skriptade inslagen. Det börjar med ras, och sedan kommer de inslag som väljs
   i 3.
4. Bygg bossen Stalaktitjätten: logik, vy, bot och test.
5. Lägg in översättningar (sv.po), skärmdumpar, webbexport och mobiltest.

Steg 1 räcker för att Grottan ska vara spelbar, med riktiga banor efter Rullaren. Resten
kan komma pass för pass.

## 7. Öppna frågor

- Vilka skriptade inslag ska med (ras, fladdermöss, mörker, gruvvagnar)?
- Ska bossens svaga punkt vara kristallen enligt förslaget, eller något annat (t.ex. att
  locka den att dyka in i en istapp)?
- Ska Pingo (pingvinen) låsas upp av Grottan, som CAMPAIGN_PLAN föreslår?
