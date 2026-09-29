# En kodbas för singleplayer, Multiplayer V1 och Multiplayer V2

Datum: 2026-09-30. Detta är en införandeplan, inte en genomförd merge eller verifierad release.

Användarens förtydligande 2026-09-30: de fyra senaste ocommittade V2-filerna ska ingå och committas före merge. Båda SQL-migrationernas funktionalitet ska också ingå; samma versionsprefix är ett historik-/namngivningsproblem och inte ett skäl att välja bort någon av dem. V1:s övergång till gemensam banpresentation är en accepterad refaktorisering, med bibehållen regressionskontroll.

## 1. Uppdrag och slutresultat

Sammanför V2-arbetet med normalspåret på `codex/current-prototype`. Behåll tre fungerande menyval: singleplayer, Multiplayer och Multiplayer V2 (test). All fortsatt utveckling sker från den sammanförda branchen tills valet av multiplayermodell är gjort.

Efter mergen: implementera R5-planens transport-/remote-rättningar, och inför gemensam presentation med jämn lokal rörelse och kamera i samtliga lägen. Behåll V1:s hostauktoritet/prediktion och V2:s klientauktoritet som separata nätverksmodeller.

Publicera en enda sammanförd Web-build på den vanliga adressen `https://hjelmdev.github.io/gravity-run/`. Användaren ska välja spelläge i spelets meny och inte behöva separata URL:er eller exporter för V1 och V2.

Källkod och Pages-export ligger fortfarande i två olika repositories. Kravet på en branch gäller den gemensamma källkoden; Pages-repots `main` innehåller publiceringsartefakterna. Flytta inte Godot-källkod till Pages-repot för att uppfylla branchkravet.

## 2. Kontrollerat nuläge och verkliga integrationsrisker

Följande lästes från lokala branches/worktrees den 30 september. Kontrollera på nytt före införande eftersom det parallella spåret kan ha fortsatt.

| Del | Lästa värden |
| --- | --- |
| Normalspår | `E:/Utveckling/Gravity Run`, branch `codex/current-prototype`, HEAD `4790caf51c89bbe129d0eaddbf0c1309acfb2b39` |
| V2-spår | `C:/Users/hjelm/.codex/worktrees/multiplayer-v2/Gravity Run`, branch `codex/multiplayer-v2`, HEAD `456cc0efd57ced6f805d9c69f276caa38e55460a` |
| Normalspårets egna commits | `3dfa16a` och `4790caf`, inklusive V1:s finish-/timingförbättringar |
| V2-spårets commits efter gemensam bas | Nio commits, från `523f481` till `456cc0e` |
| Ocommittat i V2 | `project.godot`, `multiplayer_v2_service.gd`, `v2_webrtc_transport.gd`, `tools/multiplayer_v2/contract_test.gd`; ungefär 425 tillagda och 63 borttagna rader |
| Ospårat i normalspåret | Många användarskapade analyser/planer, inklusive R5, samt scratch-/exportmappar. De ska inte mass-stagas |

V2 består inte enbart av nya filer. Den ändrar även:

- `gravity-run/project.godot`: version och V2-autoload.
- `gravity-run/systems/app_navigation.gd`: V2-navigation.
- `gravity-run/ui/game_hub.gd` och `ui/main_menu.gd`: menyval, lobby och matchstart.
- `gravity-run/ui/multiplayer_match.gd`: V1 använder en ny gemensam `RaceCoursePresentation` i stället för egen baninstansiering/ritning.
- Supabase-migrationer: både V2-isolering och en V1-countdownkompatibilitetsändring.

En läsande trevägsförhandsvisning av de committade heads visar en versionskonflikt i `project.godot`. `ui/multiplayer_match.gd` ändras i båda spåren; förhandsvisningen visar ingen konfliktmarkör där, men filen måste granskas semantiskt. Detta är inte ett löfte om konfliktfri merge av de ännu ocommittade V2-ändringarna. En modern `merge-tree --write-tree` kunde inte slutföras på grund av skrivskydd för Git-objekt i analysmiljön; den läsande förhandsvisningen användes i stället.

Två V2-migrationer har samma versionsprefix:

- `202609290003_require_all_v2_players_ready.sql`
- `202609290003_v2_lobby_skin_rpc.sql`

Detta kräver avstämning mot faktiskt tillämpad backendhistorik, även om Git kan slå ihop filerna utan konflikt.

## 3. Underlag och prioriteringsordning

Läs dessa lokala dokument före implementation:

1. `MULTIPLAYER_V2_R5_POSITION_CHANNEL_AND_REMOTE_RENDER_PLAN.md` — obligatorisk transport-/renderreparation efter merge.
2. `MULTIPLAYER_V2_START_AND_SHARED_GAMEPLAY_ANALYSIS.md` — gemensam spelmekanik/presentation och tidigare startfel.
3. `MULTIPLAYER_V2_R3_START_ROOT_CAUSE_AND_FIX_PLAN.md` och `MULTIPLAYER_V2_R4_HEARTBEAT_DISCONNECT_AND_ABORT_PLAN.md` — tidigare regressioner att bevara rättningar för.
4. `MULTIPLAYER_V2_START_AND_SHARED_GAMEPLAY_TEST_REPORT.md` och `MULTIPLAYER_V2_TEST_RESULTS.md` från V2-branchen — historiska testutfall, inte bevis för den nya builden.
5. `E:/Utveckling/Gravity Run/DEPLOYMENT.md` — nuvarande export/publiceringsflöde.

Arbetsordning: säkra båda spåren → merge → verifiera meny/backendisolering → R5 → gemensam rörelse/kamera/presentation → regressionstester → en sammanförd Web-export → publicera rootadressen.

Håll ändringarna i separata, granskningsbara commits. Undvik att blanda mergekonflikter, transportfix, kamerarefaktor och Pages-byte i en stor commit.

## 4. Etapp A — säkra allt V2-arbete före merge

1. Kontrollera tillämpliga `AGENTS.md`, Git-remotes, branches, worktrees och status i båda spåren. Inventera även nya filer, inte bara tracked diff.
2. Koordinera en tydlig överlämningspunkt med det aktiva V2-spåret. Ändra inte dess arbetsfiler samtidigt som dess agent arbetar. Meddelanden till ett annat chatspår kräver användarens uttryckliga instruktion; annars lägg överlämningsbehovet i rapporten.
3. De fyra ocommittade V2-filerna är obligatoriska i leveransen enligt användarens förtydligande. Granska och verifiera dem vid överlämningspunkten och committa ändringarna på V2-branchen före mergen, med uttrycklig staging av dessa filer. De ingår inte i branchens nuvarande HEAD; en merge av bara dagens commits uppfyller därför inte uppdraget. Om verifieringen hittar ett fel: rätta det och bevara det senaste arbetets avsedda funktionalitet. Välj inte bort filerna för att förenkla mergen. Registrera testutfall och den nya commitens SHA.
4. Registrera slutlig V2-SHA efter överlämningen. Använd den som mergekälla och i rapporten, inte en gammal exportsnapshot.
5. Normalspårets ospårade användardokument ska bevaras. Staga uttryckligen denna plan och de underlag som ska bli versionshanterade, särskilt R5. Kopiera inte `.codex-v2-build/project` ovanpå källprojektet. Den katalogen är en export-/byggkopia, inte sanningskällan.
6. Skapa återställningsreferenser till båda committade heads. Säkerställ separat att ospårade dokument och ofärdigt arbete finns kvar; en Git-ref bevarar inte ospårade filer.

Exempel på läsande inventering från normalspåret:

```powershell
git worktree list --porcelain
git status --short
git branch -vv
git remote -v
git log --oneline codex/current-prototype..codex/multiplayer-v2
git log --oneline codex/multiplayer-v2..codex/current-prototype
git diff --name-status codex/current-prototype...codex/multiplayer-v2
```

Git rapporterade dubious ownership för V2-worktreet i sandboxen. Vid läsning användes en kommandolokal `git -c 'safe.directory=C:/Users/hjelm/.codex/worktrees/multiplayer-v2/Gravity Run' -C ...`. Ändra inte global Git-konfiguration för att kringgå det.

**Godkänt när:** båda spårens leverans-SHA är registrerade, allt avsett V2-arbete ingår och inget pågående/ospårat arbete har tappats.

## 5. Etapp B — merge till normalspårets branch

Genomför mergen i `E:/Utveckling/Gravity Run` på `codex/current-prototype`. Behåll båda spårens historia med en vanlig merge; ersätt inte normalspårets filer med V2-versionerna i bulk.

```powershell
git branch --show-current
git merge --no-ff --no-commit codex/multiplayer-v2
git diff --name-only --diff-filter=U
git diff --cached --stat
```

Kör först efter etapp A och ny statuskontroll. Spara inte ett mergecommit med kvarvarande konfliktmarkörer.

Konflikt-/granskningspolicy:

- `project.godot`: behåll befintliga V1-autoloads och lägg till V2-autoload. Välj ett nytt gemensamt build-ID. Ingen V2-exklusiv huvudscen eller exportstart; huvudscenen ska fortfarande vara menyn.
- `ui/multiplayer_match.gd`: behåll normalspårets finish-/timingförbättringar från `3dfa16a` samtidigt som `RaceCoursePresentation` integreras. Granska resultathändelser, diagnostics, gamla borttagna banfält och anropsordningen; en automatisk merge bevisar inte att detta fungerar.
- V1-service, diagnostics och lobbyprovider: bevara normalspårets senaste ändringar. V2 ska inte överta deras signaler, sessioner eller auktoritet.
- Menyn/navigationen: båda multiplayerlägena ska kunna nås och lämnas. Navigationsflaggor får inte öppna fel lobby efter byte mellan lägen.
- `.gd.uid` och scenreferenser: behåll UIDs för importerade nya resurser och kontrollera dubbla globala `class_name` samt brutna preload-/scenreferenser.

Importera/parsa Godot-projektet, kör relevant mergebaslinje enligt etapp H och granska staged diff före mergecommit. Registrera merge-SHA och baslinjens testutfall. Publicera inte ett mellanläge med känd R5-bugg.

**Godkänt när:** samma branch innehåller avsett arbete från båda spåren, tre menyval fungerar och V1:s senaste rättningar finns kvar.

## 6. Etapp C — Supabase och två samtidigt laddade multiplayer-services

1. Jämför lokal migrationslista med linked remotehistorik före push. Äldre rapporter uppger redan applicerade V2-migrationer; utgå inte från att alla sammanslagna filer är nya.
2. Båda migrationernas SQL/funktionalitet ska med: readinesskravet i `202609290003_require_all_v2_players_ready.sql` och skin-RPC:n i `202609290003_v2_lobby_skin_rpc.sql`. Supabase identifierar migrationsversionen genom det numeriska prefixet före första understrecket; olika beskrivningar ger inte två unika versioner. Utred därför prefixkollisionen `202609290003`. Identifiera vilken SQL som faktiskt körts och vilken fil som motsvarar den registrerade versionen. Behåll korrekt historik för applicerade migrationer; ge en ännu inte applicerad migration en ny unik version. Om den andra SQL-ändringen körts manuellt, dokumentera tillståndet och skapa vid behov en ny framåtriktad migration som bevarar dess funktionalitet. Om ingen är applicerad kan de ges två lediga versioner i korrekt ordning. Radera inte en migration eller slå bort dess innehåll för att lösa namnkollisionen. Kör inte blind `migration repair`, byt inte namn på applicerade migrationer på chans och använd inte linked `db reset`.
3. Granska slutliga definitioner av room payload, V1-countdown, V2 prepare/readiness och skins. En senare `CREATE OR REPLACE` kan påverka en funktion från en tidigare migration.
4. Behåll `network_mode`-isolering: V1 ska lista/join:a V1-rum, V2 motsvarande V2-rum. Fel läges join ska avvisas begripligt.
5. Kontrollera att två autoloads inte skriver över samma `SceneTree.multiplayer`/peer eller tar emot varandras RPC. Aktivera endast rätt session/transport för valt läge. V1:s kontrolltrafik får inte tolkas som V2-paket.
6. Vid byte V1 → meny → V2 och omvänt: stäng rätt peer, timers, polling och signalanslutningar; töm rätt runddata. Bevara gemensam inloggning, inventory och profil.
7. Kör linked dry-run innan eventuella nya migrationer appliceras och verifiera remotehistorik och funktioner efteråt.

**Godkänt när:** migrationshistoriken är entydig, både readinesskravet och skin-RPC:n finns i versionshanterad SQL och är verifierade i backend, båda lägenas rum/start fungerar och services inte påverkar varandras sessioner.

## 7. Etapp D — implementera hela R5 efter mergen

R5 är ett eget leveranskrav, inte en hänvisning som kan lämnas till senare. Kanalfelet återfanns även i aktuellt V2-worktree: positions-RPC på kanal 1, men server/client/replacement-peer utan extra kanalkonfiguration.

### D1. Minsta transportfix

Ändra `systems/multiplayer_v2/v2_rpc_endpoint.gd::submit_player_sample` till:

```gdscript
@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
```

Behåll 30 Hz som grundläge och `unreliable_ordered`. Rätta kommentarerna om `channels_config` respektive ICE och sök igenom alla RPC-/peer-konstruktioner, inklusive reconnect. Alternativet med uttrycklig extra kanal finns i R5; använd en enda konsekvent strategi. Rekommendationen här är standardkanal 0.

### D2. Instrumentera den verkliga kedjan

- Returnera och kontrollera `Error` från sample-wrappers och `.rpc()`/`.rpc_id()`.
- Räkna försök, accepterade skickanrop och skickfel separat. `OK` är inte mottagningsbevis.
- Separera hostens lokala samples från nätverksmottagna samples.
- Registrera mottaget/accepterat/avvisat per spelarägare och transportavsändare, med avvisningsorsak.
- Registrera track-insertions, sample age, senaste renderade sequence och saknade/stale tracks per remote.
- Logga första skickfelet med kanal/mode, peer, round-id och sequence; begränsa upprepningar.
- Exportera JSON från browser med samma build-ID på alla deltagare. Inga tokens, SDP eller hemligheter i rapporter.

### D3. Verifiera från transport till synlig figur

Två riktiga browserklienter, samma nya export, minst fem sekunders levande spel: bevisa skickning → RPC-mottagning → ägarvalidering → signal → track → förändrad renderposition i båda riktningar. Vid 30 Hz ska över 100 accepterade remote-samples normalt hinna tas emot per klient i det lokala testet; redovisa verkliga siffror och luckor.

Gör olika gravitationsbyten så mottagen rörelse syns. Testa därefter host + två gäster: varje klient får båda remotes, inklusive guest → host relay → guest. Behåll säker ägarkontroll som skiljer transportavsändare från ursprunglig ägare.

Låt hosten dö först och kontrollera fortsatt relay/spectating. Kör gemensamt avslut och minst tre omstarter utan omladdning. Rätta statusraden som kan visa väntan trots färdigt resultat. Saknad ström ska synas i diagnostiken; dölj inte felet med en påhittad remote-rörelse.

**Godkänt när:** R5:s samtliga acceptanskrav uppfylls. Ett headless-test av hostens egna samples räcker inte. Dokumentera uttryckligen om två-/treklienttestet inte kunde köras; etappen är då inte fullt verifierad.

## 8. Etapp E — gemensamt kontrakt för rörelse och presentation

### E1. Problem som ska lösas

Singleplayer uppdaterar spelarposition och `Camera2D` i `_physics_process`; ingen fysikinterpolation är aktiverad i läst projektkonfiguration. Spelaren ligger stabilt på skärmen eftersom kameran flyttas lika långt, medan statiska hinder visar kamerans steg. Det är en stark kodbaserad kandidat till upplevd fart–inbromsning–fart, inte en uppmätt bekräftelse från användarens runda.

V1 flyttar banroten i stället för `Camera2D`. Hosten använder rå lokal simuleringsposition; gästen har egen renderhistorik/klocka och visuella korrigeringar. V2 flyttar också banroten och uppdaterar presentationen i `_physics_process`. Dess runner har `render_state(fraction)`, men kameran följer `player_state.world_x`. `_accumulator / FIXED_DELTA` samplas i fysikcallbacken och är inte en kontinuerlig fas per renderframe.

Klientauktoritet löser vem som bestämmer positionen. Den löser inte automatiskt stegen mellan simuleringsuppdateringar.

### E2. Gemensam struktur

Bygg gemensamma små komponenter, inte en gemensam jättescen med alla nätverks-/progressionsflöden:

| Gemensam del | Ansvar |
| --- | --- |
| `RunnerMotion` och stat-/effektupplösning | Rörelseregler, cooldown, verklig utrustningshastighet och effektlivslängd |
| Presentationssampler | Tidsstämplade föregående/aktuella positioner, renderposition och explicit reset vid spawn/ny runda |
| Kamerakomponent med `Camera2D` | Följa vald renderpose, viewport/zoom, kameraområde och world→screen |
| `RaceCoursePresentation` eller generaliserad efterföljare | Gemensamma hinder-/terrängresurser, banritning och visuellt tillstånd |
| Spellägesspecifika adaptrar | Tillhandahålla bandata och simuleringssamples för single, V1, V2 och spectator |

Återanvänd existerande `RaceCoursePresentation`, som redan införts i V1/V2 på V2-branchen. Utvidga dess inmatning för singleplayers streamade oändliga bana; kräv inte att singleplayer måste bli ett ändligt race-manifest. Återanvänd hazardresurser och `CourseSurfaceRenderer` i alla lägen.

Behåll singleplayers progression/HUD/endlessflöde och respektive multiplayerlobby/auktoritet i sina adaptrar. Kontrollera skillnader i world height/viewport från respektive manifest; hårdkoda inte 540 eller 720 för alla lägen.

### E3. En interpolationväg per transform

Rekommendation för samordningen är en explicit gemensam presentationssampler och `Camera2D`, eftersom V1 redan har egna tidskällor och remote-historik. Stäng av Godots inbyggda interpolation på transforms som redan interpoleras manuellt; aktivera inte en global utjämning som läggs ovanpå V1:s/V2:s egen interpolation.

För lokala fasta fysiksteg: spara prev/current med deras tick/tid. I `_process` beräkna renderpositionen med renderfasen mellan dem. Om simuleringen drivs av Godots fysikloop kan dess interpolation fraction användas; om V1 behåller egen simuleringsaccumulator måste fasen komma från den simulationen. Använd inte en accumulator från en annan klocka och flytta inte fysiken till variabelt render-delta för att få jämn bild.

```text
render_position = lerp(previous_position, current_position, render_fraction)
camera_target = den valda spelarens render_position
```

Hastigheten behöver inte vara jämnt delbar med fysik- eller skärmfrekvens. Interpolera positionerna som faktiskt beräknats, inklusive itemmodifierad fart, blockering och acceleration. Ingen fast 500 px/s-extrapolation av lokal runner.

Spara samples efter färdig simuleringsuppdatering inklusive kollision/terminalstatus. Kollisionsvärlden använder simuleringspositioner; interpolerade spritepositioner får inte skrivas tillbaka i simulerings-/kollisionsdata. Singleplayers `get_player_rect()` använder idag nodens globalposition: separera den från en visuellt interpolerad child eller separat rendernod så refaktorn inte ändrar kollisionerna.

V1-gästen behåller sin auktoritetskorrigering. Applicera den i dess adapter och använd samma slutliga renderpose för figur och kamera. V2:s lokala samples får aldrig ersättas av ett hosteko; remote-buffert eller host-ACK får inte bromsa den lokala renderklockan.

## 9. Etapp F — inför riktig gemensam Camera2D

1. Implementera kamerakomponenten och koppla in singleplayer först med befintlig lead/zoom. Verifiera innan multiplayer flyttas över.
2. Koppla V2:s egen figur och kamera till samma renderpose i samma `_process`-frame. Flytta visuell player sync, kamera, remote-presentation och relevanta redraws till renderuppdateringen; behåll fysik, kollision och sampleproduktion i fasta steg.
3. Koppla V1-hostens lokala runner till interpolation mellan simulationsteg. V1-gästens befintliga renderpose går genom samma kamerakomponent utan extra lerp-lager.
4. Ta bort `_course_root.position.x = -camera_left` när `Camera2D` tar över. Banroten ska ligga i världsrummet. Samma translation får inte ske två gånger.
5. Granska varje `world_x - camera_left`, draw-offset, finishmarkör, bakgrundsstjärna, synlighetskontroll och `RaceCoursePresentation.set_camera_left`. Skilj viewportbaserad culling från faktisk rittranslation. HUD/lobby/resultat hör hemma i screen space/CanvasLayer och ska inte följa kameran.
6. Säkerställ callback-/processprioritet så kamerans canvastransform använder dagens renderpose utan en extra frames fördröjning. Kontrollera mot installerad Godot-version och mät slutlig skärmposition.
7. Låt spectator-kameran följa samma renderpose som faktiskt används för valt remote-track. Målet får inte väljas från rå position och sedan ritas från en annan tid.
8. Hantera initial spawn, retry, ny match, scene leave, explicit teleport och terminalfreeze med reset av prev/current, klocka och kameratillstånd. Fyll inte ny rundas första interpolation med förra rundans sista sample.
9. Återanvänd singleplayers viewport-/zoomprincip utan att ändra racebanans skala av misstag. Verifiera resize, mobilorientering och pixelavrundning; undvik separata konkurrerande avrundningar på kamera och objekt.

**Godkänt när:** alla tre lägen använder samma kamerakomponent, statiska hinder har en enda värld→skärmtransform och lokal figur/kamera visar samma renderpose.

## 10. Etapp G — rörliga hinder, gemensamma regler och diagnostik

- Interpolera tunnors position/rotation från rätt simuleringssamples. Statiska spikes/block står kvar i världen. Skapande/förstörelse är explicita diskreta händelser, inte vanlig lerp.
- V1:s världssamples och V2:s lokala värld behöver inte ha samma auktoritetsmodell. Samma presenterare ska kunna ta emot båda utan att ändra deras kollisionsregler.
- Återanvänd upplöst loadout/effektlogik. Kontrollera skillnader som V2:s egna clamps och singleplayers `player_effects`; ändra inte tillåtna statsintervall tyst under kamerarefaktorn. Identifiera avsiktliga regelskillnader och dokumentera dem.
- Singleplayer genererar/spawnar horisonter i fysiksteget. Mät eventuella kostnadstoppar innan optimering. Interpolation reparerar inte en verklig lång renderpaus.
- Logga per renderframe: delta, simtick, prev/current-tider, renderfas, raw/render X, camera X/delta, slutlig player screen X, korrigeringsdelta och resync/hold. För remote: renderklocka, sample age, track coverage och faktisk visad pose.
- Mät renderarbete separat från fysik-/nätverksarbete. V2:s nuvarande fysikframe-logg är inte tillräckligt underlag för hur varje bildruta visas.
- Använd indikatorn `(camera_x_now - camera_x_previous) / render_delta` under fri konstant löpning; jämför mot faktiskt utrustningsmodifierad hastighet. Exkludera namngivna spawn/terminal/spectatorbyten. Registrera nollsteg, felaktiga större steg och oförklarade resyncs.

## 11. Etapp H — tester och acceptansmatris

Använd installerad Godot 4.7.2. Exempel på import:

```powershell
& 'E:/Utveckling/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path 'E:/Utveckling/Gravity Run/gravity-run' --quit
git diff --check
```

Kör befintliga tester i deras rätta form: `.gd` med `--script`, `.tscn` som scen. Relevanta merge-/regressionskontroller är V2 `tools/multiplayer_v2/contract_test.gd`, `tools/race_course_presentation_test.gd`, V1 lobbycontract/smoke, simulation, diagnostics och `multiplayer_match_presentation_test.tscn`, samt course manifest/generator, equipment och barrel motion. Läs testets entrypoint före körning och redovisa kommandon/exitstatus/fel.

Lägg till meningsfulla kontrakttester för den nya gemensamma presentationen:

1. 60 Hz simulation med rendering vid 30/60/75/120/144 Hz och varierande render-delta. Konstant fri löpning ger korrekt tidsnormaliserad kamerafart och stabil player screen X.
2. Verkliga tillåtna utrustningshastigheter, inklusive värden som inte delar 60 jämnt; ändring av fart, effektutgång, blockering och återgång till löpning.
3. Spawn/retry/ny runda och död/finish utan interpolation från tidigare runda.
4. En enda translation av statisk geometri och oförändrade kollisionsutfall före/efter presentationsrefaktorn.
5. Samma kamerakontrakt i single, V1 host/guest och V2 host/guest; mode-adaptrar får egna inputklockor men inte egna kameraregler.

| Verkligt test | Krav |
| --- | --- |
| Singleplayer, desktop och web | Jämn bana, fungerande gravity flips/blockering/död/retry, HUD och progression |
| V1 host + guest | Start, befintlig prediktion, utrustning, bana, finish/resultat och rematch utan timingregression |
| V2 host + guest | Alla R5-led verifierade, skilda flips synliga, stabil lokal kamera, gemensamt avslut |
| V2 host + två gäster | Guest→guest relay, host dör först, fortsatt remote-rörelse/spectating, tre nya rundor |
| Byta spelläge | Single → V1 → V2 → V1 utan sidomladdning; inget peer-/signal-/lobbyläckage |
| Resize/mobil | Samma banlayout, rätt zoom, HUD/orientering och input |
| Flera bildfrekvenser | Headless kontrakt samt visuell kontroll där maskin/skärm stöder det |

Använd reproducerbar seed/längd och samma loadout för relevanta A/B-jämförelser. Singleplayers endlessscenario är inte identiskt med ett race; jämför de gemensamma reglerna i en kontrollerad fixture utan att ändra scenariosemantiken.

En godkänd import/export är inte bevis för nätverksleverans eller visuell jämnhet. Rapportera browser-/mobil-/treklienttester som ej körda när så är fallet. Gör inte ett kvalitetslöfte utifrån enbart FPS eller inga parsefel.

## 12. Etapp I — en export på GitHub Pages-rooten

### I1. Rootadress och filplacering

Nuvarande Pages-shell är `E:/Utveckling/gravity-run-pages/docs/index.html`. Den laddar `./game-v2/index.html` i en iframe; dessutom finns äldre `docs/game`, rootexportfiler och separat `docs/multiplayer-v2`.

Rekommenderat första sammanförda publiceringsflöde: behåll root-shellens orientering/input/cachefunktioner och ersätt innehållet i dess befintliga `docs/game-v2/` med EN export som har alla tre menyval. Rootadressen ovan blir därmed gemensam. Katalognamnet `game-v2` är här en befintlig exportplats och betyder inte att builden bara innehåller Multiplayer V2.

Att lägga alla Godot-filer direkt i `docs/` är inte nödvändigt för en gemensam rootadress och skulle kräva att shellens funktioner integreras i Godots HTML-template. Utför inte den extra flytten under första konsolideringen. Om filplaceringen senare ändras måste hela shell/cache/manifest/assetkedjan flyttas tillsammans.

### I2. Export och förhandskontroll

1. Säkerställ slutligt gemensamt sourcecommit och build-ID, push till rätt källremote. Exportera från det sammanförda projektet, inte från V2-worktreet eller `.codex-v2-build/project`.
2. Använd `Web`-preset och en ren temporär exportkatalog utanför källrepot enligt `DEPLOYMENT.md`. Kontrollera att native WebRTC-tillägget fortsatt exkluderas från webexport och att alla V2-scener finns i paketet.
3. Kontrollera icke-tom `index.html`, `index.js`, `index.wasm`, `index.pck` och alla faktiskt refererade stödresurser, inklusive eventuell mobile text entry. Registrera hashes/storlekar.
4. Serve:a exporten lokalt och kör root-shell + export tillsammans. Alla lägen ska vara tillgängliga från samma instans. Leta efter referenser till separata gamla V2-PCK-filer eller versionsbundna exportsökvägar.
5. Kontrollera Pages-klonens branch `main`, remote och status innan kopiering. Bevara orelaterade ändringar. Spara gamla deploy-SHA och artefakthashes för rollback.

### I3. Publiceringsändringar

- Kopiera endast den verifierade gemensamma exporten till `docs/game-v2/`. Granska gamla filer från tidigare exporter så att endast avsedda filer används; gör inte en rekursiv radering av hela `docs/`.
- Behåll `docs/index.html` som huvudstart. Granska dess cache-/serviceworkerhantering, ikoner och manifest: vissa referenser pekar fortfarande på `./game/`, medan iframe pekar på `./game-v2/`. Ändra endast referenser som behövs för att rooten faktiskt använder gemensamma aktuella resurser.
- Gör gamla `docs/multiplayer-v2/`-ingången till en kompatibilitetsredirect till rooten när rootbuilden är verifierad. Bevara dess rollbackmöjlighet. Låt inte den gamla sidan fortsätta servera en egen aktiv experimentbuild.
- Uppdatera `DEPLOYMENT.md` med ett enda exportflöde, vilka shell-/manifest-/redirectfiler som får ändras och vilket build-ID som verifierats. Gamla V2-only instruktioner får inte återinföra två aktiva builds.
- Staga exporten och endast uttryckligt valda shell-/redirect-/manifeständringar. Kontrollera varje staged sökväg. Push Pages `main` utan force-push.

`DEPLOYMENT.md` begränsar idag normal exportstaging till `docs/game-v2`. Den aktuella konsolideringen omfattar även granskade ändringar av rootens integration och den gamla V2-ingången enligt användarens uppdrag; dokumentera den ändrade deployomfattningen. Ändra inte andra Pages-projekt eller användarfiler.

### I4. Verifiera live

Vänta på faktisk Pages-deploy och testa den normala rootadressen med både ren browserprofil och en tidigare använd profil. Kontrollera runtime-build-ID, nätverkets laddade PCK/JS/WASM och att host/guest kör samma build. Verifiera R5:s remote-rörelse och ett modebyte även på publicerad build.

Publiceringsmiljön kan kräva åtkomst till separat Pages-klon, exporttemplates eller nätverk. Gör allt tillgängligt förhandsarbete först och redovisa exakta blockerade steg om miljön saknar behörighet. Markera inte publiceringen klar utan verifierad deploy.

**Godkänt när:** rooten laddar en gemensam build med tre lägen och gamla V2-länken leder dit. Användaren behöver inte välja URL efter spelläge.

## 13. Återställning och avveckling av parallellspåret

- Vid fel före release: behåll fungerande tidigare deploy. Rätta på den sammanförda branchen eller reverta en avgränsad felaktig commit; radera inte användararbete eller force-pusha historik.
- Vid releasefel: återställ granskade Pages-artefakter/shell från registrerat deploycommit med ett nytt commit. Backendrollback måste bedömas separat; återställ inte databasen med reset för att återställa en webbuild.
- Behåll V2-branchen/worktreet tills dess avsedda commits/ändringar finns i normalspåret och alla relevanta verifieringar är avslutade. Ett kvarvarande historiskt branchnamn betyder inte att två aktiva utvecklingsspår behövs.
- Avveckla eller arkivera worktreet först efter verifierad överlämning och bevarat arbete. Ta särskilt hand om ignored export-/testartefakter som behövs som bevis. Fortsatt implementation görs i normalspåret; skapa inte ännu en permanent integrationsbranch.

## 14. Rapport som införande-agenten ska lämna

Spara en separat införanderapport bredvid denna plan med:

1. Exakta före-/efter-SHA, överlämnat ocommittat V2-arbete, mergekonflikter och valda lösningar.
2. Vilka V1-timingrättningar och tidigare V2-starträttningar som bevarats.
3. Lokal/remote migrationshistorik och hantering av versionskollisionen.
4. Implementerade R5-ändringar och verkliga sample-/render-räknare för två-/treklienttest.
5. Gemensamma komponenter och kvarvarande avsiktliga skillnader i auktoritet/scenario.
6. Testmatris med pass/fail/ej körd, kommandon, browser/build-ID och kända kvarvarande problem.
7. Gemensamt sourcecommit, Web-artefakthashes, Pages-commit/deploystatus, rootadress och rollbackreferens.
8. Eventuella blockerade moment uttryckligt angivna. Merge, R5, presentation och publicering har varsin status.

Slutleveransen är klar först när avsett V2-arbete finns på `codex/current-prototype`, R5 är implementerad och verifierad, gemensam presentation uppfyller kontraktet och samma publicerade rootbuild kan användas för singleplayer, V1 och V2.
