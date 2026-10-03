# Nattuppdrag: gemensamma scener, biomer, sågklinga och måttlig täthet

Beställt 2026-10-02. Användaren har beställt implementation av alla delar, uttryckligen för både singleplayer och multiplayer. Prioritet: gemensamma scener och biomer, sågklinga, sist en enkel täthetsjustering. Root instruerar Luna, hjälper vid blockerare och slutbesiktigar. Fynd skickas tillbaka till Luna för rättning före slutleverans. Tidigare myntlatens ska lämnas i accepterat läge.

## Leverans och arbetsgränser

Arbeta i den befintliga Gravity Run-kodbasen, branch codex/current-prototype. Återanvänd /root/luna_shared_gameplay; root ska slutgranska kod, riktade tester och faktiska visuella fångster. Inget parallellt skrivande i samma filer av andra agenter. Bevara orelaterade ocommittade capture-/pacing-/menyändringar. Staging ska omfatta enbart uppdraget, inklusive rätt hunks i main.gd.

Skapa OVERNIGHT_SHARED_SCENES_BIOMES_AND_SAW_STATUS.md tidigt och håll den uppdaterad med aktuell fas, commits, tester, blockerare, återstående arbete och konkreta nästa kommandon. Den ska göra återupptagning möjlig utan omtag. Om användningsgränsen stoppar arbetet finns användarens instruktion att återuppta den 3 oktober 04:15 Europe/Stockholm efter uppgiven återställning 04:11. Schemalagd kontroll ska fortsätta befintligt arbete, inte starta en konkurrerande implementation.

Azure origin: https://hjelmdev.visualstudio.com/Gravityrun/_git/Gravityrun. Pagesrepo: E:/Utveckling/gravity-run-pages, main, https://github.com/hjelmdev/gravity-run.git. Aktiv export docs/game och root docs/index.html. Nödvändiga migrationer och publicering är auktoriserade i samtalet, men root slutgranskar detta större paket innan live-migration och publicering. Bygg från exakt ren commit; ingen återanvänd export från dirty working tree. Synlig ny buildetikett och verifierad Pages-workflow, loader och PCK-hash krävs.

## 1. Gemensamma hinderscener

- Inför hazards/falling_rock.tscn med befintligt gemensamt script/modell och underkomponenter. Singleplayer och multiplayer ska instansiera samma scen genom en delad presentation/factory där det är lämpligt.
- Inventera kopplingarna för befintliga spikar, block, tunnor och mynt så innehåll inte får separata effekter i olika spellägen. Återanvänd deras scener; gör ingen generell omskrivning av runner eller nätverk.
- Gemensam simulation är auktoritet för tidsförlopp/kollision; scenerna visar tillstånd. Samma nuvarande stenparametrar och kontakter i båda spellägena. Biome-grafik eller kamerastorlek får aldrig ändra falltid.
- Behåll accepterat myntflöde: lokal kontaktpresentation, tidig hostvaliderad gemensam effekt, senare separat belöning. Ingen ny utredning av nätlatens eller smoothness.

## 2. Grotta och hemsökt biome med utbytbara assets

### Resurskontrakt

Utöka befintliga biomes/biome_definition.gd i stället för att skapa ett fristående parallellt system. Definitionerna ska bära stabilt biome-ID, palett och valfria grafikresurser: TileSet/atlas med separata golv- och takytor, kanter, steg/sluttningar, bakgrundslager och dekor. Befintliga atlas-koordinatfält ska återanvändas där de passar.

En gemensam renderer/lagerkomponent används av SP och MP. Banans stödytor, geometri och hitboxar kommer från samma kursdata som tidigare. Presentationen följer dessa ytor. Byte från ritad reservgrafik till användarens tiles ska ske genom resurskonfiguration, utan if-grenar för varje biome i main.gd eller ny kollisionsimplementation.

Implementera och testa assetvägen redan nu med en liten testresurs/fixture: tilldelad atlas/texture ska faktiskt ersätta reservgrafiken, inte bara vara oanvända fält i ett Resource. Ange tile-storlek, orientering för tak och hur kanter/sluttningar väljs. Saknade resurser ska ge korrekt ritad fallback utan felspam. Lägg en kort guide för hur användaren byter tiles/bakgrund senare.

### Synlig första leverans

- Classic behålls som igenkännbar start.
- Cave: blågrå klippa, lager i bakgrunden, diskreta kristaller och separat ljusare ytkant. Inga dekorativa stalaktiter som ser ut att vara dödliga i spelplanet.
- Haunted: indigo/violett, blekt månljus, avlägsna ruiner/döda träd och mild dimma bakom banan. Inget nytt spökhinder i detta uppdrag.
- Snygga reservmotiv får vara ritade former/SVG/lager. Inga stora nya rasterassetpaket eller starka helskärmseffekter. Mynt, runner, varningar och faror ska vara läsbara i båda paletter.
- Gör alla tre teman synliga i normal spelning, inte endast i en debugscen. Rimligt standardval är samma deterministic distance-based temasekvens i båda lägena, med lugn övergång och första nya temat tillräckligt tidigt för ett kort morgonprov. Dokumentera intervallen. Seed/kursavstånd väljer presentation, inte aktuell viewport eller lokala FPS. Samma världsplats ska få samma tema på klienterna, även vid spectating och återanslutning.
- Biomer är visuella i denna leverans och ska inte ändra hazardvikter, fysik eller ekonomi beroende på temat.

## 3. Ny hazard: ensam rullande sågklinga

Användarens idé: en ensam klinga som rullar längs golv eller tak; vid ett hål i taket faller den ner och fortsätter längs golvet. Beteendet ska beskrivas och implementeras en gång.

- Gemensam saw-blade-scen, grafik, rörelsemodell och hazardprofil. Återanvänd ytkartan och befintliga motion-/kontaktkontrakt där lämpligt, utan att kopiera tunnans hela implementation.
- Första versionen är dödlig vid kontakt, utan belöning och utan att förstöra andra hinder. Separat hazard-ID så exempelvis spikimmunitet inte oavsiktligt skyddar mot såg. Detta är ett rutinmässigt standardval; användaren har inte beställt förstörbar klinga/powerupinteraktion.
- En klinga per möte, förutsägbar horisontell rörelse och synlig rotation, även takplacerad. Golv- och takytor följer verklig support/step/slope-geometri.
- Vid takhål: stöd försvinner, klingan faller med gemensam gravitation, landar på golv om stöd finns och fortsätter i samma horisontella riktning. Vid golvhål kan den falla ur banan och avlägsnas. Ingen teleportation mellan ytor.
- Gemensamma simulationstick och initialt tillstånd. SP och MP får inte olika rörelse på grund av spawn/framefrekvens. Multiplayer sprider nödvändigt tillstånd/aktivering genom befintlig världskanal. Återanslutning och spectator ska visa samma klinga/tillstånd.
- Planner/ruttprognos måste ta med tak→fall→golv-fasen, inte bara den ursprungliga ytan. Förutsägbar infart, tillräcklig framförhållning och säker rutt vid grundhastighet samt itempåverkad hastighet. Begränsa kombinationer konservativt om prognosen ännu inte kan bevisa dem.
- Klingan ska förekomma både i vanlig SP och MP. En kort stabil testseed/demo ska göra golv, tak och takhålsfallet möjligt att prova utan lång grind.

## 4. Enkel tätare bana

Användaren har godkänt högre frekvens av spikar, tunnor och fallande stenar i båda lägena. Gör en måttlig, gemensam justering av profilvikter/täthet, inte en ny adaptiv svårighetsmodell. Behåll stenen mer sällsynt än spikar och sågklingan som ett separat, mindre vanligt möte.

Undvik att kalla en viktändring garanterat kortare tomrum. Gör en kort seedmätning av antal relevanta faror per distans och längsta tomrum före/efter, och kontrollera att den faktiska mängden normalt ökar. Säkerhetsmarginaler/ruttkontroll ska behållas. Ingen stor frameprofilering eller bred balansutredning behövs.

## Versions- och backendkontrakt

Saw-content och ändrad generering påverkar kursens identitet. Inför en ny generator-/reglerrevision och matchande game-version. Frys tidigare version 8 och alla äldre stödda seeds. Uppdatera samtliga consumers/whitelists, manifestkod, world-state/baseline, seedutmaningar och verifiering.

Databasen har exakta versionsgrindar! Lägg unik migration för aktuella CREATE- och coin-round-register-grindar och andra berörda definitioner. Kör alla migrationer i ordning i lokal ren DB och release-kontraktstest. Anta inte att en gammal migrations allmänt tillåtande funktion fortfarande är live. Bevara wallet-idempotens, kontobindning och historiska data. Nytt hazardformat ska ha manifest/baseline-storlekstest och eventuella baselinerevisionsregler så äldre klienter inte tyst tolkar saw-fält fel.

Supabase CLI finns på C:/Users/hjelm/AppData/Local/Temp/gravity-run-export-16e977f05bed4c61881951ced59b5178/supabase-cli/supabase.exe. Linked list/dry-run/db push kan behöva require_escalated för befintligt OS-credentiallager. Inga tokens ska skrivas i loggar.

## Riktad verifiering och slutbesiktning

1. Godot-import/parse och scenladdning med riktiga autoloads, både SP och MP; inte bara hjälpfunktioner.
2. Fångster från spelvyer: classic/cave/haunted i stående och liggande vy, med runner/coins/hazards och HUD. Visuell läsbarhet och ytor i bilderna ska slutbesiktigas av root. Registrera faktiska bildfiler.
3. Samma seed/version/kursavstånd ger samma hazard-/coinplacering och biome i båda lägena. Gamla v8-fixturer ska vara oförändrade.
4. Klinga: golv, tak, stöd över slope/step, takhål→fall→golvfortsättning, golvhål, faktisk runnerkontakt, start/reset, replay/reconnect samt SP/MP-tick-/positionsparitet. Ett kort förutsägbart demo-/challengeprov dokumenteras.
5. Befintlig sten, myntkontaktpresentation, belöningsbeslut, HUD/musik och omspel får inte regressa. Kör riktade befintliga integrationstester; bredda bara vid ändring som motiverar det.
6. Måttlig frekvensökning verifieras på ett litet representativt seedurval och säkra rutter; testa normal och 750 px/s planeringshastighet.
7. Root gör slutbesiktning och skickar konkreta fynd till Luna för rättning. Luna kommer först till REVIEW_READY, med diff/commits/testloggar/bilder/known limits. Ingen live-migration/Pagespublicering före denna rootbesiktning. Root fortsätter autonomt; detta kräver ingen ny human approval.
8. Efter rättningar och rootbesiktning: source push Azure, nödvändig live-migration och verifierad versionshistorik, ren exakt-commit export, scoped Pagescommit och push. Verifiera workflow success och publikt pakethash, inte endast HTTP 200. Rapportera publicerad build/länk och kort morgontest samt eventuella verkliga begränsningar.

Dokumentation får skala med uppdraget. Ingen separat redesign av butik, skins, economy, FPS eller multiplayernätverk ingår.
