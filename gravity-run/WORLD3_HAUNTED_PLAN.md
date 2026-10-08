# Värld 3 – Spökskogen

Plan för kampanjens tredje värld. Den följer samma mall som Ängen och Grottan
(`WORLD2_CAVE_PLAN.md`): sex banor, en boss, data i `CampaignCatalog`, frysta seeds och
stjärnor från `campaign_level_tool.gd`, och kontroll av golv- och takhål. Kartan
(`map_haunted.png`), kartnoderna (`HAUNTED_MAP_NODES`) och accentfärgen `b69cff` finns
redan.

Punkterna märkta **(förval)** har Adam inte bestämt än. De är rimliga utgångslägen, och ett
nattpass kan bygga efter dem.

## 1. Vad som skiljer Spökskogen

- **Spöken är världens nya hinder från generatorn.** Haunted-mixen har två egna profiler:
  `haunted_ghost` (svävande spöke som flyger förbi, flyby) och `haunted_chaser` (spöke som
  jagar bakifrån, pursuit). Båda finns i generator 21, så de kräver ingen ny
  generatorversion.
- **Biomet är det riktiga `haunted`.** Mixen höjer spöken kraftigt och dämpar terrängen.
- **Allt annat kommer via skriptade inslag** från `campaign_run.gd`, med samma mekanism som
  Grottan inför (rasen m.m.). Grottans inslag byggs först, så Spökskogen kan återanvända
  den kanalen.
- **Svårighet:** Spökskogen börjar ungefär där Grottan slutar, med lite högre täthet.

## 2. Banorna (33–50 s)

| Bana | Titel | Nytt | Täthet / marginal | Längd |
|---|---|---|---|---|
| 3-1 | Spökstigen | svävande spöken (`haunted_ghost`) | 1,1 / 1,2 | 16 500 |
| 3-2 | Jagad | spöke som jagar bakifrån (`haunted_chaser`) | 1,2 / 1,15 | 18 000 |
| 3-3 | Kyrkogården | händer ur marken (skriptat) | 1,3 / 1,1 | 19 500 |
| 3-4 | Dimman | dimbankar (skriptat) | 1,4 / 1,05 | 21 000 |
| 3-5 | Irrbloss | irrbloss som speglar din fil (skriptat) | 1,5 / 1,0 | 22 500 |
| 3-6 | Skogsprovet | allt | 1,6 / 0,95 | 25 000 |
| 3-B | Spökkungen | boss | – | – |

Varje bana får ”Nytt hinder”-banner, tre gravitationsstjärnor och kontroll med
`gap_conflicts`. Nivåverktyget behöver bara ta emot biomet `haunted`, efter samma
ändring som för Grottan.

## 3. Skriptade inslag (förval: alla fyra)

1. **Händer ur marken.** En lila glöd i golvet eller taket varnar ungefär 0,6 s i förväg.
   Sedan sträcker sig en spökhand upp ur den filen en kort stund. Hindret är en enkel
   rektangel med två bildrutor, alltså samma typ av nytt men enkelt hinder som Grottans
   fladdermussvärm.
2. **Dimbankar.** Ett dimlager täcker högra delen av skärmen en stund, men hinder inom
   cirka 300 px från löparen syns alltid tydligt. Inslaget påverkar bara utseendet, på
   samma sätt som Grottans mörker. Därför får det inte göra banan orättvis, och
   reaktionsmarginalen på dimpartierna höjs med 0,1.
3. **Irrbloss.** Ett irrbloss svävar framför dig och följer din fil med 0,8 s fördröjning.
   Det lär ut bossens grundidé ofarligt: ett plock på irrblosset ger 3 extra mynt.
4. **Gravstenar och kors.** Skin på `block` och `spike_group` i skogen. Inslaget påverkar
   bara utseendet, som gruvvagnarna i Grottan.

## 4. Utseende och ljud

- **Bakgrund:** dagens haunted-backdrop plus en stor måne, silhuetter av döda träd i två
  parallaxlager, låga dimband som glider och några svävande irrbloss. Färgerna är lila och
  mörkblå, med grönaktiga spökljus.
- **Musik:** genereras i `tools/audio/`, med kusligt orgel- och cembaloliknande chiptune i
  moll på 132 BPM. Musiken är takthållen, och löparen synkas till takten som i Ängen.
  **(förval)**
- **Ljud:** spökvisslan när ett spöke dyker upp, ett hand-ur-marken-skrap, ett lyktklang för
  bossträffar och ett spöklikt eko på stjärnljudet.

## 5. Bossen: Spökkungen (3-B)

En spökkung med krona svävar framför löparen. Han **speglar din fil med 0,7 s
fördröjning** hela striden. Är du i taket nu, är han i taket strax efter.

- **Attacker** (schemalagda som Rullarens `PHASES`):
  1. **Spökspår:** filen han befinner sig i lämnar kort efter sig spökeld. Den filen du var i
     för 0,7 s sedan blir alltså farlig, och det ger striden en rytm.
  2. **Spökvåg:** han kallar in svävande spöken i den fil du *inte* är i, så att du trängs.
  3. **Släck lyktorna:** skärmen mörknar och bara lyktorna lyser (samma teknik som dimman).
- **Svag punkt: lura in honom i en lykta** (från CAMPAIGN_PLAN). Lyktor hänger på
  utmärkta ställen, i taket eller på golvet. Eftersom han följer dig med fördröjning ska du
  vara på lyktans sida ungefär 0,7 s innan han når lyktan och sedan flippa bort. Då
  svävar han in i lyktan och fångas av ljuset. Det blir tre träffar, och fördröjningen
  krymper för varje träff (0,7 → 0,55 → 0,4 s).
- **Skillnad mot Stalaktitjätten:** jätten reagerar på var du är *när varningen kommer*. Kungen
  följer dig *hela tiden*, så du styr honom genom hela striden. Logiken blir en
  `observe_runner` med en ringbuffert av löparens sida, och lyktan räknas som träff om
  kungens fördröjda sida matchar lyktans och löparens nuvarande sida inte gör det.
- **Testbot:** samma typ av bot som tidigare, som klarar bossen två gånger i
  `campaign_runtime_test`.

## 6. Upplåsning

- Spökskogen låser upp **Misse** (katten), som CAMPAIGN_PLAN föreslår. **(förval)**

## 7. Arbetsordning

1. Lägg in `HAUNTED_STAGES` i katalogen. Låt nivåverktyget ta emot biomet `haunted`,
   sök seeds, frys stjärnorna och kör `gap_conflicts`.
2. Bygg utseendelyftet (måne, träd, dimband, irrbloss), musiken och ljuden.
3. Bygg de skriptade inslagen, i ordningen händer, gravstenar, irrbloss och dimma. Den
   skriptade kanalen från Grottan återanvänds.
4. Bygg bossen Spökkungen: logik, vy, bot och test.
5. Lägg in översättningar (sv.po), skärmdumpar, webbexport och mobiltest.

**Beroende:** Grottan (värld 2) byggs före Spökskogen. Steg 1 här kan ändå göras samtidigt
som Grottans steg 1, eftersom båda bara är katalogdata och seed-sökning.

## 8. Öppna frågor till Adam

- Ska musiken vara takthållen (förval) eller en friare, mer svävande stämning?
- Stämmer Misse som upplåsning?
- Är 0,7 s fördröjning lagom för Spökkungen, eller ska den kännas mer direkt?
