# Värld 4 – Vulkanen

Plan för kampanjens fjärde värld. Den följer samma mall som Grottan och Spökskogen
(`WORLD2_CAVE_PLAN.md`, `WORLD3_HAUNTED_PLAN.md`): sex banor, en boss, data i
`CampaignCatalog`, frysta seeds och stjärnor från `campaign_level_tool.gd`, och kontroll av
golv- och takhål. Kartnoderna (`LAVA_MAP_NODES`) och accentfärgen `ff814f` finns redan.

Punkterna märkta **(förval)** har Adam inte bestämt. Dagpasset 2026-10-09 bygger efter dem.

## 1. Vad som skiljer Vulkanen

- **Lavan är världens nya hinder från generatorn.** Lava-mixen har tre egna profiler i
  generator 21: `lava_crack` (spricka i golv eller tak), `lava_volcano` (vulkan som sprutar
  i en solfjäder) och `lava_tidal_pool` (tidvattenpool i golvet). Ingen ny generatorversion
  behövs.
- **Biomet är det riktiga `lava`.** Utseendet ritas som `volcano_campaign`, på samma sätt som
  `cave_campaign` och `haunted_campaign`.
- **Allt annat kommer via skriptade inslag** i `campaign_features.gd`.
- **Svårighet:** Vulkanen är sista världen och börjar där Spökskogen slutar.

## 2. Banorna (35–52 s)

| Bana | Titel | Nytt | Täthet / marginal | Längd |
|---|---|---|---|---|
| 4-1 | Glödande stig | lavasprickor (`lava_crack`) | 1,2 / 1,15 | 17 500 |
| 4-2 | Askregn | askregn (skriptat, bara utseende) | 1,3 / 1,1 | 19 000 |
| 4-3 | Utbrottet | vulkaner (`lava_volcano`) | 1,4 / 1,05 | 20 500 |
| 4-4 | Tidvatten | tidvattenpooler (`lava_tidal_pool`) | 1,5 / 1,0 | 22 000 |
| 4-5 | Eldregn | glödbomber som faller (skriptat) | 1,6 / 0,95 | 23 500 |
| 4-6 | Vulkanprovet | allt | 1,8 / 0,85 | 26 000 |
| 4-B | Magmaormen | boss | – | – |

## 3. Skriptade inslag (förval)

1. **Glödbomber.** En röd ring i golvet eller taket varnar ungefär 0,7 s i förväg, sedan slår
   en glödbomb ner i den filen. Samma typ av enkelt hinder som spökhanden.
2. **Askregn.** Grå aska faller över skärmen en stund. Bara utseende, som dimman, men
   hinder nära löparen syns alltid tydligt.
3. **Värmedallring.** Bakgrunden dallrar ovanför lavasprickor. Bara utseende.

## 4. Utseende och ljud

- **Bakgrund:** mörkröd himmel, en stor vulkan i fjärran som ryker, svarta basaltpelare i två
  parallaxlager och glöd underifrån.
- **Musik:** genereras i `tools/audio/`, i moll med tunga trummor, 156 BPM, takthållen som de
  andra världarna. **(förval)**
- **Ljud:** lavabubbel, nedslag för glödbomben och ett djupt ormvrål för bossen.

## 5. Bossen: Magmaormen (4-B)

En orm av magma reser sig ur lavan bakom löparen (till vänster på skärmen).

- **Attacker** (schemalagda som Rullarens `PHASES`):
  1. **Solfjäder:** ormen spottar en båge av glödbomber som slår ner i golv- eller takfilen.
  2. **Spricka:** en lavaspricka öppnar sig framför löparen i den fil ormen pekar på.
  3. **Tidvatten:** lavan stiger i golvfilen en stund, så du måste hålla dig i taket.
- **Svag punkt:** efter varje solfjäder exponeras ett glödande fjäll som hänger i taket eller
  ligger i golvet framför dig. Spring över det på rätt sida, som Rullarens platta. Tre
  träffar, och varje fas går lite fortare.
- **Testbot** som klarar bossen i `campaign_runtime_test`.

## 6. Upplåsning

- Vulkanen låser upp **Bit**, som CAMPAIGN_PLAN föreslår. **(förval)** Finns ingen Bit i
  rostern blir det nästa figur som saknar upplåsning.

## 7. Biomnycklar (utrustning steg 4)

En nyckel per värld, och den verkar bara i sin egen värld:
- **Isdubbar (Grottan):** istappar och ras varnar 30 % tidigare.
- **Lykta (Spökskogen):** dimman och mörkret lättar runt löparen, och spökhänderna lyser
  tydligare.
- **Värmesköld (Vulkanen):** en träff från lava (spricka, pool eller glödbomb) per bana tas
  utan att dö.

Nycklarna är ryggsäcksprylar med effekt-id `biome_key_cave`, `biome_key_haunted` och
`biome_key_volcano`. De vinns genom att besegra världens boss (inte köpbara) och kräver en
migration som utökar `item_definition_effect_valid`.

## 8. Arbetsordning

1. `LAVA_STAGES` i katalogen, seeds och stjärnor från verktyget, `gap_conflicts`.
2. Utseende, musik och ljud.
3. Skriptade inslag: glödbomber och askregn.
4. Magmaormen: logik, vy, bot och test.
5. Upplåsning, biomnycklar, översättningar, skärmdumpar och webbexport.
