# Nattuppdrag: status för gemensamma scener, biomer, såg och täthet

Uppdaterad: 2026-10-03, efter live-migration och verifierad Pages-publicering.

## Fas

`PUBLISHED` — user-authorized release is live. Supabase migration `202610030001_generator9_saw_blade_release.sql` was applied and linked history now matches through that version. Azure gameplay commit `6384278` plus clean-build fix `9114cb8` are pushed to `codex/current-prototype` (source branch then advanced with status-only documentation commits). Pages commit `e504354a987981ea8fbb1956a7c5c8aceb519200` publishes the exact clean `9114cb8` export. The Pages workflow completed successfully; the public root and game loader serve the new build ID and the downloaded PCK SHA-256 matches the export.

## Levererat

- Gemensamma biomer definieras i `BiomeDefinition`-resurser och renderas av `BiomeRenderer`/`CourseSurfaceRenderer`, återanvända av `main.gd` och `RaceCoursePresentation`. Distanssekvensen är classic 0–4800 px, cave 4800–9600 px, haunted 9600–14400 px och upprepas deterministiskt.
- TileSet-atlasen byts via resursfält; stödytorna UV-beskärs till verkliga golv-/takintervall och lämnar hål tomma. Steg delas vid gräns och ytan följer slopeprovet. Takets orientering hanteras av resursflaggan. Guide finns i `BIOME_ASSET_GUIDE.md`.
- Slutliga renderjusteringar efter roots inspektion: cave-dekor hålls dämpad; haunted-ruinerna ligger i den synliga bakgrundskorridoren i både SP och MP; atlasens lutningswedge-celler används inte eftersom deras vinkel ser ut som spikar. Neutral ytcell används tills korrekt tilekonst tillkommer.
- Gemensamma sten- och sågscener finns. Sågen använder en deterministisk 60 Hz-modell och samma scen i SP/MP; ceiling gap leder till fall, golvlandning fortsätter rörelsen och stödbrist i golv tar bort klingan. Ny v9 generatorprofil innehåller måttligt justerade frekvenser och såg; tidigare v8 och äldre versioner är frysta.
- Generatorn bygger v9/manifest v4 och matchande synlig build `2026.10.03-shared-biomes-saw-gen9`; serviceversion är `2.1.20261003.5`. Migration `supabase/migrations/202610030001_generator9_saw_blade_release.sql` flyttar aktuella create- och coin-register-grindar till versionen. Root verifierade lokal ren migrationskedja/RPC; live-migrationen är applicerad och linked history verifierad.
- Showcase-fixture finns i `tools/biome_saw_showcase.tscn`; den visar atlasbyte, terrängkanter, slope/step, icke-rutnätsjusterat gap, tak, runner, mynt, spik, varning och såg i stående/liggande vy. Den är inte publik menyväg.

## Verifiering

- Godot 4.7.2 editor/headless project parse: exit 0, inga `SCRIPT ERROR` eller `Parse Error`. Endast miljövarningen om Windows certifikatlager och kända Godot resource-teardown-varningar förekommer.
- `tools/generator_v8_compatibility_test.gd`: PASS, byte-exakta frysta v6/v7/v8-fixturer och deterministisk v9 manifest v4.
- `tools/course_generator_test.gd`: PASS, inklusive 12 seeded courses, ruttlösbarhet med 750 px/s clearancemodell, reproducerbarhet över hastighets-/viewportändringar och befintliga routefall.
- `tools/course_manifest_test.gd`: PASS efter uppdaterad kontraktsassert för v4/saw; testet verifierar deterministiska mynt, schema/hash och förekomst av såg för seed 918273645.
- `tools/generator_v9_smoke_test.gd`: PASS, seed 1: 61 events/4 sågar/29,225 JSON-byte; seed 42: 67/1/22,155; seed 100000014: 59/3/30,113. Det är ett litet representativt prov, inte statistisk frekvensgaranti.
- `tools/generator_v9_density_sample_test.gd`: PASS, jämför 45,000 px v8/v9 samma seeds. Relevanta accepterade hazards (spikes/barrels/rock/saw) blev seed 1: 30→33, seed 42: 23→26, seed 100000014: 31→30. Längsta gap mellan dessa eventcentra blev respektive 8976→6819 px, 7646→5148 px och 3960→5772 px. Provet visar generellt men inte universellt högre antal; enstaka seed kan ha större tomrum. Detta är inte en garanti om kortare max-gap.
- `tools/saw_blade_shared_tick_test.gd`: PASS SP-modell/MP-world tickparitet, takfall, landning och fortsatt golvrörelse. `tools/saw_blade_singleplayer_runtime_test.gd`: PASS riktig `main.tscn` spawn/kontakt för seed 100000014. `tools/multiplayer_v2/saw_blade_presentation_test.gd`: PASS riktig presentation, gapfall, landning och reset.
- `tools/biome_tile_swap_test.gd`: PASS ersättningsatlas, flat/step/slope-cellval, icke-gridstöd och gapexkludering. GPU-test `tools/biome_tile_swap_render_test.gd`: PASS; atlastexturens faktiska pixlar ersatte fallback och klipptes till stödintervallet [63,129].
- `tools/multiplayer_v2/release_version_contract_test.gd`: PASS source game/generator-konstanter matchar senaste migrationsgrindar och projektets synliga v9-build.
- `tools/race_course_presentation_test.gd`: PASS.
- `tools/course_generator_test.gd`: seeded generator test körs vid 500 och 750 px/s route-clearance för varje kursseed; generationen är version-/viewport/hastighetsoberoende.
- GPU showcase exporterade PNG:er för 1280×720 och 540×960 till `E:/Utveckling/Gravity Run/.codex-overnight-review/biome-saw-landscape.png` och `biome-saw-portrait.png`.
- Normal-SP-körning i `main.tscn` fångade 10 mål kring båda övergångarna med 0 omstarter. Normal MP-presentation fångades från manifest/world-tick vid samma 10 mål. Inga ogiltiga polygoner, parsefel eller scriptfel; endast certifikatlager-/teardownvarningar. Root har inspekterat de nya MP/SP-bilderna runt 4800/9600 och godkänt paletter, ruinernas synlighet och att lutningstiles inte längre liknar falska spikar.

Fångster ligger i `E:/Utveckling/Gravity Run/.codex-overnight-review/`: `sp-v9-distance-04700.png` ... `09700.png` och `mp-v9-distance-04700.png` ... `09700.png`, med 4790/4800/4810 samt 9590/9600/9610 tätt kring temagränser.

## Begränsningar / root-review

- Root har godkänt staging/review. Lokal ren migrationskedja och authenticated RPC verifierades separat av root. Live history visade 39 synkade migrations och endast `202610030001` pending; CLI dry-run visade exakt den migrationen. Ingen live-mutation gjordes efter auto-reviewavslaget.
- Commits `6384278e32f870ba6adf15d4679f682a2fe4a726` (scoped gameplay) och `9114cb8b3e0ba20136be214d0c2e7391d4b3338c` (clean-build tab-fix) är pushade till Azure. Den senare clean archive:n klarade `--headless --editor --quit` utan parse-/scriptfel och `saw_blade_singleplayer_runtime_test.gd` PASS i faktisk `main.tscn`.
- Export från exakt `9114cb8` finns i `E:/Utveckling/Gravity Run/.codex-release-9114cb8-v9/out`; PCK `index.pck` är 2,893,748 byte, SHA-256 `A7BE80FE04F5CABD16173CA7AB4F8BB85A1ADCC4F6C99D7749851FE01198454A`. Pages-payload är isolerad i `E:/Utveckling/Gravity Run/.codex-pages-stage-9114cb8`, med mainPack/root build label `shared-biomes-saw-gen9-9114cb8-20261003`. Den är inte kopierad till Pages-repot och inte publicerad.
- Pages commit `e504354a987981ea8fbb1956a7c5c8aceb519200` publicerade bundle och root wrapper. GitHub Actions `pages build and deployment` rapporterade `success` för just den committen. Live root `https://hjelmdev.github.io/gravity-run/` och `/game/index.html?build=shared-biomes-saw-gen9-9114cb8-20261003` svarade HTTP 200 och innehåller det nya build-ID/mainPack. PCK hämtad från den publika URL:en är 2,893,748 byte med SHA-256 `A7BE80FE04F5CABD16173CA7AB4F8BB85A1ADCC4F6C99D7749851FE01198454A`, exakt samma som clean exporten.
- Saw route safety är nu riktat provad på vanlig generated v9 seed 1: mätning använde `RunnerMotion`, `surface_at()` från hela resolved manifest och samma distance-trigger/+12 tick activation. Stationär floor-lane kontakter vid 250/500 px/s låg på offsets +592/+775 och täcktes av det accepterade floor threat intervallet +560..+1100. Ingen stationär-lane-kontakt uppstod vid 750 i detta fixture; det rapporteras inte som generellt fri passage. Separat tidsstyrd RunnerMotion-sökning fann grounded floor→ceiling→floor rutt utan kontakt vid 250/500/750, med första flip 300 px före trigger och återgång knuten till roof gap. Det är en riktad route-fixture, inte ett fullständigt bevis för alla seeds, utrustning/cooldowns eller live MP.
- MP historisk `player_contact_at()` verifierar hit vid sparad saw-pose och miss i cirkelns AABB-hörn; `player_contact()` verifierar också aktuell pose. Den riktiga SP `main.tscn` resolver testar hit och AABB-hörnmiss via shared SawBlade-scenen.
- Sen sceninstansiering jämförs med MP-world replay efter 4,501 ticks. Root körde dessutom en oberoende korrektionsrepro som matchade en sent skapad SP-scen mot MP efter takgap/landning, samt ett miljon-tick dormant skip på 6 µs; se rootens logg i `.codex-overnight-review/`.
- Biome-canvascoordinates normaliseras nu via en gemensam absolute-world-x→course-distance-funktion: SP omvandlar sin course-relative camera left till absolute world-x med `PLAYER_X`; MP använder `manifest.start_x`. Tile-grid offset följer samma 180 px origin i båda. Gränsprovet täcker absolut world-x 4790/4800/4810 och 9590/9600/9610.
- v9 frekvensen mättes endast på tre seedkörningar här. Det finns ingen påstådd garanterad kortare max-gap; högsta svansrisk kräver bredare seedmaterial om root vill ha det efter review.
- Rendering av löpande vyer verifierades i lokala Godot GPU-fångster. En lokal browserkontroll av första `6384278`-exporten hittade den felaktiga bokstavliga `\t`-indentationen; den exporterades inte. Fixen `9114cb8` reparsades och SP-runtime-testades från ren archive och byggdes om. Root verifierade korrigerad export lokalt; efter publicering verifierades Pages-workflow, offentligt build-ID/loader och exakt publik PCK-hash. Ingen separat inloggad live-match med två riktiga användarkonton kördes i denna releasekontroll.

## Sista riktade körningar

- `tools/saw_blade_activation_route_test.gd`: PASS, first-sample och redan-förbi-tröskel-aktivering, runner-surface-baserade mätningar, faktisk planner-window-täckning, grounded rutter vid 250/500/750, aktuell och historisk MP cirkelkontakt, sen SawBlade-scenpose och biomegränser. Baseline format 2 och duplicate activation återspelas idempotent.
- `tools/saw_blade_singleplayer_runtime_test.gd`: PASS, riktig SP-scen/resolver; misshörnstestets kropp överlappar såg-AABB men missar den verkliga cirkeln. Hittestet kräver ett ändligt sweep-fraction-värde inom [0,1].
- `tools/saw_blade_shared_tick_test.gd`, `tools/multiplayer_v2/saw_blade_presentation_test.gd`, `tools/generator_v8_compatibility_test.gd`, `tools/course_manifest_test.gd` och `tools/multiplayer_v2/release_version_contract_test.gd`: PASS efter ändringarna. v6/v7/v8 frysta fixtures förblir oförändrade.
- Headless Godot 4.7.2 project/editor parse: PASS utan `SCRIPT ERROR`/`Parse Error`. Windows root-certificate warning kan visas i isolerad testprofil.

## Orelaterat / staging

Orelaterade dirty `main.gd` capture hunks, `ui/main_menu.gd`, `tools/singleplayer_render_capture.gd`, `tools/unified_presentation_test.gd`, `SHARED_FRAME_PACING_EXPERIMENT_RESULTS.md`, `../IMPLEMENTATION_PLAN.md` och övriga otrackade planer/loggar/artifacts är bevarade utanför releasen.

## Nästa steg efter root-review

1. Open the public build at `https://hjelmdev.github.io/gravity-run/` and try a v9 singleplayer run using challenge code `GR9-100000014`.
2. Try a multiplayer room after the v9 database gate is live; compare visible biome transitions and a saw encounter with another player when available.
3. Report failures with the diagnostics export; generator frequency measurements cover only three representative seeds and do not guarantee shorter worst-case gaps.

## Post-release visual follow-up — biome backdrop anchoring

Uppdaterad 2026-10-03 efter rootens godkännande av GPU-fångster. Denna ändring är en ren presentationsfix efter publicerad gen9-release; generator 9, serviceversion `2.1.20261003.5`, fysik, hazardtiming och databasekontrakt är oförändrade. Synlig projektetikett för den nya exporten är `2026.10.03-gen9-biome-backdrop-anchor`.

- Bakgrundslager repeteras nu i en fast course-/parallaxkoordinat och beskärs med UV-regioner inom varje biomefragment. Texturer behåller fast skala oavsett fragmentbredd. Klassiska stjärnor, grottkristaller och ruiner får samma stabila deterministiska gitter; grottans ridgepolygon beräknar exakta fragmentändpunkter och kan inte måla ut i angränsande tema.
- Haunted-resursen använder utbytbara SVG-lager för avlägsna ruiner och dämpad dimma via `BiomeDefinition.background_layers`, med konfigurerad storlek, vertikal placering och parallax. Måne/halo och SVG-lager använder en gemensam 540 px logisk bakgrundshöjd för SP och MP, vilket håller dem synliga i den normala spelkorridoren även i portrait och vid SP-zoom.
- Riktad regression `tools/biome_backdrop_anchor_test.gd` PASS för temaavstånden 4800/14400, 20 px gränsfönster och parallaxfaktorer 0.055/0.12/0.22, med jämförelse mellan hel viewport och uppdelade fragment i 1280- och 540-px layouter. `tools/biome_tile_swap_test.gd` PASS; editor/headless parse PASS. Godots lokala Windows-certifikatstore gav en miljövarning; inga GDScript-/parsefel rapporterades.
- Aktuella GPU-fångster för SP `main.tscn` och MP `RaceCoursePresentation` finns i `.codex-overnight-review/`: `sp-v9-live-demo-distance-09700.png` är en normal, oförflyttad demo vid 9700 utan omstart och visar måne/ruiner/dimma över den tidigare höga takytan. Övriga SP seam-bilder (`sp-v9-distance-*`, `sp-v9-portrait-distance-*`) är seek-fixturebilder från riktiga main-scenen. MP har landscape- och portrait-seamserier (`mp-v9-distance-*`, `mp-v9-portrait-distance-*`) vid 4790/4800/4810, 9590/9600/9610 och 14390/14400/14410; capturekameran använder kursrelativ camera origin som matchruntime.
- Root visuellt godkände MP landscape/portrait och normal SP live-demo-bilden vid 9700. Den aktuella visuella uppföljningen är godkänd för scoped release; inga migrationer eller protokolländringar behövs.

### Slutlig publicering

- Source-commit `91170fa9973b1f2f90e102bc2192dc9d3b7ddbba` är pushad till Azure `codex/current-prototype`. En separat statusuppdatering efter publicering dokumenterar Pagesresultatet.
- Ren Godot 4.7.2-export byggdes från exakt commit `91170fa` i `.codex-clean-biome-91170fa`; `index.pck` är 2,924,696 byte och SHA-256 `65BB84BBCA9B64C3C2DCDD013914608EC1A40C96F543491C7D179FB24D5DEDC3`.
- Pages-commit `6e9c9fb52a52e4f84879bf583b77f21f911ea3cb` publicerar bunten i `docs/game` och uppdaterar rotloaderns build-ID till `shared-biome-backdrop-gen9-91170fa-20261003`. GitHub Pages-workflow körning `37103205304` slutfördes med `success`.
- Live root och game loader svarade HTTP 200 och innehöll rätt build-ID respektive `mainPack`. Den publika PCK-hämtningen var exakt 2,924,696 byte med samma SHA-256 som den rena exporten. Ingen ny live-databasmigration behövdes.

