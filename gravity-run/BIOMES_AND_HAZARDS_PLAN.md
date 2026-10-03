# Biomer och faror i Gravity Run

Status: idé- och implementationsplan, 2026-09-27. Detta dokument föreslår ändringar; det innebär inte att nya biomer eller faror redan finns i endless.

## Spelprincip

Gravity Run har två spelbara ytor, golv och tak, och spelaren löser möten genom att byta gravitation. Varje ny fara bör därför kunna beskrivas med **var**, **när** och **hur länge** den gör en yta farlig. En biome ska ge platsen en tydlig identitet och nya kombinationer, men aldrig dölja kollisionsytor eller kräva ett gravitationsbyte snabbare än spelaren hinner göra.

Tre nivåer av variation kan byggas oberoende av varandra:

1. **Presentation:** färg, textur, bakgrund, partiklar, ljud. Ingen effekt på banans geometri eller jämförbarheten mellan seed-körningar.
2. **Mötesurval:** samma kända faror men andra vikter och kombinationer i olika biomer. Detta påverkar banan och måste ingå i kursens identitet.
3. **Nya mekaniker:** nya rörelser, träffytor och miljöeffekter. Dessa kräver egen ruttprognos, kollisionslogik och testning.

## Nuläge i koden

| Del | Vad som finns | Följd för planeringen |
| --- | --- | --- |
| `systems/course_generator.gd` | Deterministiska profiler för `spike_group`, `block`, `barrel_chain`, `floor_gap`, `ceiling_gap`, `terrain_step` och `terrain_slope`. Version 4 väljer tunnor som ett extra möte efter vissa hinder. En ruttkontroll avvisar orimliga överlapp. | Behåll profil-ID och hotintervall som grund. En ny fara måste kunna förutsägas av planeraren, inte bara skapas som en scen. |
| `systems/course_hazard_profile.gd` | Vikt, tillåtna ytor, bredd, höjd, antal, rörelsefaktor, valfria flera hotfönster och valfri `runtime_scene`. | Enkel statisk fara kan vara datadriven; tidsstyrd eller rörlig fara kan behöva en specialiserad profil som bygger egna intervall. |
| `systems/course_generation_ruleset.gd` | Tillåtelselista och vikter per profil, plus täthet, storlek och reaktionsmarginal. Payload och fingeravtryck finns för delade utmaningar. | Val av faror är redan delvis konfigurerbart utan nytt gränssnitt. Biome-schema saknas. |
| `systems/course_run_definition.gd` och `main.gd` | En endless-runda får seed och ruleset. `main.gd` skapar hinder, uppdaterar kollisioner och ritar bakgrund och bana. Okända profilslag kan skapas via `runtime_scene`. | Endless behöver ett explicit biome-val. `main.gd` behöver en gemensam biome-renderare och färre hårdkodade faro-grenar på sikt. |
| `hazards/` och `terrain/` | Spikar och block står stilla, tunnor rullar, hål tar bort stöd på ena ytan, steg kan blockera och ha spikar, sluttningar ändrar ytan. Hål kan leda till fall ur banan. | Skilj på *fara* och *terränghändelse*. Lava i ett hål är till exempel hål plus dödlig vätska, inte bara ett nytt färgat hål. |
| `systems/course_surface_renderer.gd` och `main.gd` | Fylld bana med fasta färger, mörk bakgrund och stjärnprickar ritas i kod. | Byt först till biome-styrda färger och bakgrundsmotiv; håll fysikytan oberoende av ritningen. |
| `biomes/biome_definition.gd`, `assets/biomes/definitions/`, `tools/biome_terrain_test.gd` | Fyra palettresurser och atlas-/TileMap-tester finns. De används inte av endless. Resurserna har även tomma fält för flera tak- och dekorvarianter; samtliga har i dag samma bakgrundsfärg. | Återanvänd definitionerna som utgångspunkt, men koppla dem till runtime och ge dem riktiga biome-ID, separata golv-/takval och bakgrundsrecept. |
| Multiplayer | `course_manifest_builder.gd` och `multiplayer_course_manifest.gd` accepterar bara de sex befintliga eventslagen. Simulationen har särskild logik för tunnor och kollisioner. | Nya mekaniska faror bör först landa i endless/seed-utmaningar. Om multiplayer ska stödja dem krävs manifestformat, validering, simulation och versionslyft. |

**Nuvarande möten, spelmässigt:** Spikar är dödliga vid kontakt och kan sitta på båda ytorna. Block är dödliga rektanglar på golv eller tak. Tunnor är rörliga, kommer från golvet, kan falla i hål och kan slå sönder vissa objekt. Golv- och takhål tar bort stöd. Steg är främst geometriska stopp som kräver byte eller rätt riktning, ibland med spikar; sluttningar är terrängvariation snarare än en direkt dödlig fara. Spelsystemet gör redan viss skillnad på spikimmunitet och andra träffar, så farotyper bör ange hur utrustning/status påverkar dem.

**Begränsningar att lösa tidigt:** Ruttkontrollen arbetar med konservativa intervall på två ytor, men den simulerar inte hela spelarens vertikala rörelse eller varje kombination av hål, vägg och rörligt objekt. Renderingen och spawn-koden känner till flera faror via specialfall. En ny tidsstyrd fara kan se möjlig ut i profilen men bli orättvis om dess animation, träffyta eller spawn-tid skiljer sig från prognosen. Befintliga seed och delade utmaningar får inte tyst ändra innehåll när katalogen växer.

## Faroidéer

### Beslutad nästa hazard, 2026-10-01

Fallande sten ska först införas gemensamt i singleplayer och multiplayer: tydlig förvarning och markerad nedslagsyta, fall, nedslag och en delvis nedgrävd synlig sten som är ett dödligt hinder resten av rundan. Ett tidigt gravitationsbyte ska ha en verifierad säker rutt, även under själva fallet. Stenen förbrukas inte när en spelare träffar den. Första versionen använder plana golv-/takpartier; framtida istapps-/lavavarianter återanvänder den gemensamma modellen.

Detaljer finns i `SHARED_FALLING_ROCK_IMPLEMENTATION_PLAN.md`. Gemensamma mynt med kontobelöning och högre hindertäthet planeras parallellt som föregående delar i `SHARED_COINS_DENSITY_AND_FALLING_ROCK_PLAN.md`. Dessa dokument är införandeplaner, inte redan implementerade funktioner.

**Svårighet:** L = lätt att prova med dagens mekanik, M = ny enkel logik, H = rörelse/timing eller särskild fysik. *Telegraf* är den visuella förvarning spelaren behöver.

### Oberoende av biome

| Fara | Beteende och motspel | Telegraf | Nivå |
| --- | --- | --- | --- |
| Stalaktit / fallande sten | Takmarkerad punkt släpper ett föremål när spelaren närmar sig; byt yta före fallzonen. Kan få olika utseende i grotta, is och ruiner. | Spricka, skakning och kort skugga på golvet. | M/H |
| Infällbara spikar | Spikar är farliga under ett tydligt tidsfönster; mellan pulser kan samma yta vara säker. | Glödande fog och förutsägbar rytm. | H |
| Pendel / rotor | En kropp sveper över ena ytan eller korridoren. Mötets faser måste ge en säker passage. | Synlig bana och ljud före svingen. | H |
| Elektrisk båge mellan fästen | Korsar mittzonen i korta pulser; kan göra själva gravitationsbytet till beslutet. | Laddning på båda fästena. | H |
| Rullande stock / vagn | Samma bas som tunnan men större hitbox eller annat kollisionsutfall. Bra första variant om mekaniken verkligen skiljer sig. | Vibration och synlig infart. | L/M |
| Tryckplatta med pil | Avfyrar en projektil längs en känd bana när ett område passeras. | Fäste, laddning och riktad pil. | H |
| Klibbig fläck | Bromsar kort på en yta, vilket ändrar tajming men inte dödar direkt. Kräver granskning av seed-säkerhet och utrustningsbonus. | Avvikande ytmönster. | M/H |

Geometriska varianter som dubbla steg, korta hål och spikar på stegets sida bör först provas med befintliga profiler och justerade vikter. Lägg inte till egna faro-ID om de bara byter färg.

### Biomer att bygga

För varje rad behövs en `BiomeDefinition` med unikt ID, färgpalett för **golvfyllning, golvkant, takfyllning, takkant, bakgrund och kontrastfärg för faror**, ett bakgrundsrecept i flera djup, ett golv-/takmönster eller textur, samt 1–2 diskreta dekorationer. Kolumnen "första läget" fungerar utan nya bildfiler. Dekorationer och dimma ska ligga bakom spelaren och träffytor; farornas siluetter ska alltid vara läsbara.

| Biome | Första läget: färg och bakgrund | Senare assets och ljud | Egna faror / särskild twist |
| --- | --- | --- | --- |
| **Plains / savann** | Ljus himmel i gradient, långsamma moln, gulgrönt gräs på både golv och tak, torra jordlager. | Moln, sol, grästuvar, savannträd långt bort, vind och insekter. | Gräshoppssvärm som kort täcker en yta; rullande höbal; rovfågel som sveper på förutsägbar höjd. |
| **Grotta** | Mörk blågrå klippa, ljusare lager i parallax, små kristallpunkter i stället för stjärnor. | Ojämna stenkanter, stalaktiter och stalagmiter, droppar, eko. | Fallande stalaktit; fladdermusflock på en yta; kristall som pulserar med tydlig förvarning. |
| **Lava / vulkan** | Mörk basalt och orange sprickor, glöd bakom banan, värmedaller som inte förvränger träffytan. | Basaltgolv/-tak, glödbassänger, rök och bubblor, dovt muller. | Lavalagd **i ett golvhål** som separat dödligt område; lavakastare som skjuter ur hålet i fasta intervall; droppande lavaklumpar från tak. Testa även takhål som säker passage eller källa till droppar. |
| **Is / glaciär** | Kall cyan och blåvit is, snöfall bakom spelplanet, blek horisont. | Transparenta iskanter, istappar, snödrev, knarrande is. | Fallande istapp; isblock som glider; tillfälligt sprickande isyta. Friktion/halka sparas tills spelkänslan är utprovad, eftersom den påverkar alla hinder. |
| **Träsk** | Mörk grönviolett himmel, låg dimma bakom banan, stilla vatten och eldflugor. | Rötter, alger, vass, dimlager, bubblor och kväkande ljud. | **Häxa på kvast** som flyger förbi på en av ett fåtal förutbestämda höjder och kanske släpper en långsam brygd; giftbubbla ur vattenhål; slingrande rot som växer över en yta. Dimman får inte gömma förvarningen eller träffytan. |
| **Spökbiome / hemsökt plats** (`haunted`) | Spooky-tema med mörk violett/blå palett, blekt månljus, dimma bakom spelplanet och siluetter av gravstenar eller ett övergivet slott. | Slitna stenkanter, döda träd, diskreta svävande ljus, vind och lågmälda spökljud. | Möjligt **spöke som hazard**: svävar längs en förutsägbar bana vid golv eller tak, eller korsar banan i ett tydligt förannonserat tidsfönster. Exakt beteende är en designidé att prova, inte ett beslutat krav. |
| **Öken / sandstorm** | Ockra och varmt lila, långsamma sandlager, blek sol. | Sandsten, dyner, damm, vind. | Sandgejser ur golvhål; nedfallande sten; sandstorm som ändrar bakgrund men inte kollisioner. |
| **Ruiner / urverk** | Tegel och mässing, valvbågar på avstånd, kugghjul som bakgrundssiluetter. | Mursten, mekaniska paneler, gnissel och klockslag. | Pendel, infällbara spikar, pilfälla. Passar precision och tydliga rytmer. |
| **Svampskog** | Djup indigo, bioluminiscent turkos/lila, sporer i bakgrunden. | Överdimensionerade svampar, mjukt ljus, fuktiga ljud. | Sporpuff som tillfälligt skymmer *bakgrunden* eller markerar en farlig yta; studsande svampvarelse. |
| **Storm / sky-fortress** | Mörkblå himmel, drivande moln och avlägsna blixtar. | Metall- eller molnplattformar, åskljud, vindstråk. | Blixt som slår ned på förmarkerad yta; elektrisk båge. Blinkeffekter ska ha ett lugnare tillgänglighetsläge. |
| **Rymd / asteroidbälte** | Bygger vidare på dagens stjärnhimmel och mörka bana. | Nebulosor, asteroidkonturer, lågmält ambient ljud. | Rymdskrot eller långsam meteor som korsar en yta; laser med laddningsfas. Bra som befintlig "classic"-biome. |
| **Jungel / tempel** | Tät grön bakgrund med stora blad i flera djup och fläckar av solljus. | Lianer, ruiner, löv, fågelläten och trummor. | Lian som svingar över banan; köttätande blomma som öppnar sig efter en tydlig signal; tempelblock som skjuts ut ur väggen. |
| **Undervattensvärld** | Djup blå gradient, långsamma bubblor och ljusstrålar uppifrån. | Korallkanter, sjögräs, fiskstim och dämpade vattenljud. | Ström som knuffar spelaren eller en projektil åt sidan; bubbelpelare som lyfter; manet som pulserar farlig/säker. Börja med visuella strömmar, eftersom sidvind påverkar hela rörelsemodellen. |
| **Godisland / leksaksfabrik** | Högmättade färger, pastellmoln eller mörkt fabrikstak. | Polkagrisar, gelé, leksaksdelar och studsiga ljud. | Klibbig kola som bromsar; studsande godisboll; leksakståg som passerar på en tydlig bana. Passar en lekfull specialrunda snarare än ständig bakgrund. |
| **Piratskepp / stormigt hav** | Skeppsdäck som banmotiv och vågor i bakgrunden. | Rep, segel, lanternor, saltstänk och knarrande trä. | Kanonkula som rullar längs ena ytan; svingande ankare; våg som tillfälligt sköljer över en förmarkerad yta. |
| **Kristallgrotta / arcane void** | Svartlila tomrum med stora glödande kristaller i fjärran. | Kristallkanter, runor, magiska ljud och långsam färgskiftning. | Runfält som växlar mellan säkra och farliga zoner; kristallstråle med synlig laddning; portal som flyttar ett hinder till en annan yta. Portaler kräver extra strikt prognos och är en senare idé. |

**Förslag på första paket:** `classic`, `plains`, `cave`, `lava`, `ice`, `swamp` som färg-/bakgrundsbiomer. Spela därefter in tre olika mekaniker: fallande objekt, lavakastare och häxans flygbana. Övriga kan hållas som designkö. Häxan ska först vara ett förutsägbart hinder med en bana; brygdprojektiler är ett separat senare steg.

**Tillagt 2026-09-30: spökbiome i designkön.** Bygg gärna `haunted` som visuellt tema först och prova sedan ett spökhinder. Spöket kan vara genomskinligt som effekt, men dess farliga kropp och förvarning måste förbli tydliga. Om det materialiseras ska den dödliga fasen vara förutsägbar och förannonserad; det får inte plötsligt bli farligt inne i spelaren. En fin skillnad mot vanliga flygande fiender vore att spöket växlar mellan två tydligt markerade spår: spelaren läser vilken yta som blir hotad och byter gravitation i rätt ögonblick. En mer avancerad variant kan imitera spelarens förra gravitationsbyte med fördröjning, men bör bara provas om den går att förutse och inte känns som att spelet fuskar. Rörelse, hotfönster och biomeplacering ska följa samma seed-/tickbaserade regler och gemensamma presentationsbyggstenar som andra framtida hinder, så att temat kan återanvändas i singleplayer och multiplayer.

## Datamodell utan konfigurationsgränssnitt

Föreslagen uppdelning (namnen är förslag, inte existerande API):

```text
EndlessConfig
  seed / ruleset
  biome_mode: fixed | sequence
  biome_ids: ["plains", "cave", ...]      # ordnad lista
  segment_length_px: 6000                  # bara sequence
  allowed_profile_ids: [...]               # explicit urval
  weight_overrides: {profile_id: factor}

BiomeDefinition (Resource)
  biome_id, display_name, visual_revision
  floor_style, ceiling_style, background_layers, accent_palette
  default_profile_weights, exclusive_profile_ids
  optional atmosphere/audio                     # visuellt tills mekanik beslutas

HazardCatalog
  profile_id -> CourseHazardProfile + runtime_scene + presentation/tags
```

`EndlessConfig` kan tills vidare vara en `.tres`-resurs som väljs i kod eller en debug-inställning. Senare kan spelverktyget visa checkboxar från samma katalog. Använd stabila `profile_id` i data och payload, aldrig skärmtext eller scenfilnamn som identitet. Ett biome har **standardvikter**, medan run-konfigurationen har **sista ordet**: en manuellt avstängd fara får aldrig dyka upp via biome, extratunna eller fallback. `include_all_profiles` bör få en medveten innebörd när katalogen växer; för reproducerbara skapade spel är en explicit lista säkrare än "alla framtida faror".

Lägg till validering för okända biome-/profil-ID, tomma listor, dubletter, ogiltiga vikter, faror som kräver saknad runtime-scen, och kombinationer där ingen möjlig mötestyp återstår. Om alla faror stängs av kan designen antingen tillåta en ren terrängbana eller säga nej; bestäm detta explicit i reglerna i stället för att tyst lägga in ett hinder. Håll slump för kosmetik separat från kursgeneratorns RNG, annars kan ett extra moln ändra nästa spikmönster.

### Biome-byte mitt i en endless-runda

**Rekommendation:** börja med fast biome; lägg sedan till en deterministisk, ordnad sekvens. Exempel: `plains → cave → lava → plains`. Välj biome för en händelse utifrån dess **planerade kursavstånd**, inte spawn-tid eller skärmens position. En sekvens kan återupprepas eller genereras från en separat biome-RNG som seedas och versionssätts. Definiera exakt gräns: `segment_index = floor(course_distance / segment_length_px)` och `biome_ids[segment_index % count]`. För att undvika biome-specifika möten som korsar gränsen: reservera en neutral övergångszon som är längre än största mötesbredd plus nödvändig bytesmarginal; skjut fram eller avvisa sådana möten med samma deterministiska regel. Rita den visuella gränsen i **världskoordinater**, så golv, tak och bakgrund byter tillsammans när spelaren färdas över den; lös det med två angränsande biome-segment i samma bildruta och kort, deterministisk färgblandning i bakgrunden. Kollisionsgeometrin ändras inte av färgblandningen. Där bakgrunder ser konstiga ut ihop kan en portal, ravin eller väderfront fungera som diskret övergångsmarkör, men den är kosmetisk.

Biome-unika faror väljs bara inne i sina segment. Globala faror kan förekomma överallt men får ny palett/asset där det passar. Förhindra att häxan från träsket fortfarande lever när lavasegmentets egen fara startar genom en tydlig livslängd och övergångszon. För tidsstyrda faror ska animationen beräknas från seed + event-ID + kursprogression/simulationstid enligt en dokumenterad regel; en lokal väggklocka ger inte samma utmaning vid olika bildfrekvens eller paus.

### Seed, delning och multiplayer

Biome-schema, längd, biome-specifika profilvikter och vald farolista måste ingå i reglernas serialiserade payload och fingeravtryck, eller i ett nytt versionerat körkontrakt som kursidentiteten omfattar. Enbart färgbyte kan versionssättas som visuellt tema utan att ändra banans identitet; så fort en biome påverkar eventurval eller fysik gäller ny identitet. Håll gamla versioner reproducerbara eller avvisa gamla koder tydligt enligt dagens versionspolicy. Uppdatera `ChallengeService` och sparade utmaningsdefinitioner när nya fält ska delas; migrera/validera lagrade payloads innan de används. Blanda inte resultat från olika kursregler på samma leaderboard.

Multiplayer bör få biomer som ren presentation först, med identiskt manifest på båda klienterna. Mekaniska faror där kräver att manifestet kan beskriva typ, position, fas och parametrar, att `MultiplayerSimulation` och träffreglerna förstår dem, samt nytt protokoll-/regelnummer. Nuvarande manifest avvisar okända slags event, så att bara registrera en profil i generatorn räcker inte.

## Praktisk implementationsordning

1. **Frys nuläget.** Välj `classic` som explicit standard och spara några kända seed-signaturer samt ett par skärmbilder. Kontrollera var biome- och faro-ID behöver visas i skapade spel och utmaningar. Ändra inte generatorns standardkatalog för äldre versioner.
2. **Koppla visuell biome till endless.** Utöka `BiomeDefinition` med färger och valfria texturer/bakgrundslager. Låt `main.gd` skicka aktiv biome till `CourseSurfaceRenderer` och en bakgrundsritare. Använd färg/procedurmotiv först. Rendera golv och tak separat och respektera hål, steg och sluttningar. Byt inte banans stödytor eller spelarens kollisioner. Kontrollera kontrast för spikar, block, HUD och spelare i alla paletter.
3. **Gör run-konfigurationen explicit.** Skapa en versionerad biome-plan i `CourseRunDefinition` eller ett sammanhållet konfigurationsobjekt. Låt endless läsa fast biome och vald tillåtelselista/vikter; mappa till befintligt `CourseGenerationRuleset`. Validera alla ID och säkra att fallback bara använder tillåtna profiler. Skriv ett litet exempel: `plains` med spikar/block, respektive `cave` med hela baskatalogen.
4. **Inför segment för mid-run-byte.** Gör biome-för-avstånd till en ren deterministisk funktion. Generatorn väljer profil ur segmentets aktiva katalog och exkluderar möten vid gränsen. Renderaren kan visa två segment samtidigt. Testa restart, olika skärmstorlekar och samma seed med olika event-horisont.
5. **Lägg till en ny mekanisk fara i taget.** För varje fara: en profil med exakt hotprognos; en scen med tydligt `configure_course_event`, rörelse och träffyta; interaktionsregel mot spelare/utrustning/tunnor; telegraf; registrering i katalog; biome-standardvikt; upptäckts-/prestations-ID om det är relevant. Först fallande sten/istapp, därefter lavakastare och sist häxa med flygbana. Återanvänd en liten uppsättning träffformer (rektangel, cirkel, triangel) innan ett större generellt kollisionssystem byggs.
6. **Lägg till riktiga assets.** Skapa/modulera sömlösa golv- och taktexturer, kanter för hål/steg/sluttningar och 2–3 parallaxlager per biome. Varje asset får ankare/skala och fallbackfärg i definitionen. Prova atlas-resurserna i `assets/biomes/definitions/` där de faktiskt passar; deras nuvarande TileMap-test ersätter inte den kodritade endless-banan automatiskt. Lägg ljud och partiklar efter att läsbarhet och prestanda fungerar.
7. **Utvidga multiplayer separat.** Ta in visuella biomer om båda klienter får samma segmentbeskrivning. Flytta över mekaniska faror först när manifest, simulation och nätverksvalidering stöder dem.

## Definition av klart och fallgropar

- Samma seed + samma versionerade biome-/faro-konfiguration ger identisk **eventlista och biome-sekvens** oavsett viewport, omstart och hur långt generatorn planerar i varje anrop.
- Ingen utvald/avstängd fara kan komma via extrahändelse, biome-standard, fallback eller ett gammalt `include_all_profiles`-antagande.
- Ett nytt möte är möjligt att klara vid konservativ maxhastighet, även tillsammans med hål och nivåskillnader. Testa flera tusen seed och spela manuellt de värsta fallen; intervallkontrollen ensam är inte full fysiksimulering.
- Visa träffytan tydligt före kontakt. Dimma, snö, glöd och parallax får inte täcka spelaren, hotets telegraf eller banans kant. Erbjud reducerade blink-/partikeleffekter.
- Håll minst en säker väg vid biome-gränsen. Ingen fara ska materialiseras mitt i spelaren eller ändra fas vid paus, låg bildfrekvens eller varierande skärmstorlek.
- Profil och runtime måste enas om storlek, hastighet, spawn-lead och eventets livslängd. Lägg ett test som jämför faktiskt hotfönster mot profilens prognos för varje rörlig fara.
- Håll `biome_id` och `profile_id` stabila över tid. Byt utseende via `visual_revision`; ändra mekanik via generator-/reglernas version. Dokumentera kompatibilitet för gamla utmaningar och topplistor.

## Ytterligare idéer

- **Biome som berättelse:** ordna sekvensen som en resa (savann → grotta → vulkan → snögräns) och låt avlägsna bakgrundslandmärken förvarna nästa område. Det ger övergången syfte utan cutscene.
- **Mikroklimat inom samma biome:** dag/natt i plains, kristallgrotta i grotta, froststorm i is. Dessa kan vara rena presentationsvarianter och ge mer variation innan fler mekaniska faror behövs.
- **Kombinationsmöten:** en förannonserad häxa ovanför en golvrot, eller lavabubbla efter ett taksteg. Bygg dem som sammansatta profiler med en gemensam ruttprognos; låt inte två oberoende spawns råka skapa en olöslig kombination.
- **Miljö som feedback:** droppar före stalaktiten, bubblor före lavakastaren, kvastens skugga före häxan. Bakgrunden blir då en del av läsbarheten i stället för bara dekoration.
- **Spökets falska hot:** i haunted kan ett ofarligt sken-spöke passera i bakgrunden medan ett riktigt hot får en distinkt kontur/färg. Lär spelaren skillnaden, så temat kan skapa spänning utan att lura med en osynlig träffyta.
- **Två spår i stället för mer fart:** låt vissa fiender välja golv eller tak och byta spår med förvarning. Då använder de Gravity Runs kärnmekanik och behöver inte bara röra sig snabbare.
- **Biome-familjer:** återanvänd en mekanik med tematiska uttryck: fallande sten i grotta, istapp i glaciär, glödande slagg i lava; pendel i urverk, svingande lian i djungel, ankare på skepp. En gemensam profil/rörelseregel kan ha olika scen och ljud.
- **Bonusväg som riskval:** låt ett möte ibland öppna en tydligt frivillig högre eller svårare väg med mynt eller kosmetisk belöning, medan den vanliga vägen förblir möjlig. Håll detta separat från obligatoriska faror så att banan inte blir olöslig.
- **Skapade spel i framtiden:** låt skaparen kryssa i biomer och faror, välja fast/sekvens och eventuellt vikter. Visa en kort förhandsvisning och kör valideringen innan spelet sparas. Spara de stabila ID:na och versionerna, inte bara checkboxarnas aktuella läge.
