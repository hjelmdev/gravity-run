# V2: resultat, första anslutningen, kollision och presentation

Datum: 2026-09-30. Status: införandet genomfört; se `MULTIPLAYER_V2_RESULTS_AND_SESSION_IMPLEMENTATION_REPORT.md` för verifiering och återstående manuella kontroller. Analysdelen nedan beskriver utgångsläget före ändringarna.

## Uppdrag och utgångsläge

Utgå från den redan sammanförda branchen `codex/current-prototype`. Singleplayer, V1 och V2 ingår i samma projekt och rootpublicering. Gör inte en ny merge eller en separat V2-publicering. Behåll V1:s hostauktoritet och V2:s klientauktoritet för den egna löparen.

Användarens önskemål är V1-liknande resultat med namn, placering och prispall; färre felsökningskontroller i matchvyn; namn på rätt sida av en flippad figur; första start utan manuell återanslutning; korrekt visuell kollisionsposition. Lobbyknappen får gärna fortsätta fungera individuellt om omspel och hostens kontroll över nästa runda är robusta. Singleplayers tidigare upplevelse av fart–inbromsning–fart ska också följas upp.

Läs tillsammans med `UNIFIED_BRANCH_IMPLEMENTATION_REPORT.md`, `UNIFIED_BRANCH_MERGE_AND_PRESENTATION_PLAN.md` och `MULTIPLAYER_V2_R5_POSITION_CHANNEL_AND_REMOTE_RENDER_PLAN.md`. R5:s positionsleverans är redan införd; denna plan bygger vidare på den.

## Underlag och slutsatser

Tre rapporter från samma runda `02cb1c6a8b08…` har granskats:

- `multiplayer_v2_match_peer1_host_02cb1c6a8b08_1790746444.json`
- `multiplayer_v2_match_peer2_guest_02cb1c6a8b08_1790746447.json`
- `multiplayer_v2_match_peer3_guest_02cb1c6a8b08_1790746450.json`

Filerna ligger i användarens Downloads. Skärmbilden visar de tre resultatvyerna. Rapporterna gäller build `2026.09.30-unified`, version `2.1.20260930.2`, manifest-seed 1260459445. Kopiera inte autentisering, användaridentiteter eller signalinguppgifter till publika fixtures.

### Bekräftat: positionskanalen levererar

| Sampleägare | Hos hosten | Hos den andra gästen |
| --- | ---: | ---: |
| Host / Peer 1 | 98 lokala | 98 hos båda gästerna |
| Peer 2 | 794 mottagna | 794 hos Peer 3 |
| Peer 3 | 155 mottagna | 155 hos Peer 2 |

Hostens 1 145 sändförsök och gästernas 794 respektive 155 har motsvarande `sample_send_ok`. Remote-track-insertions motsvarar mottagningen. Det finns inget registrerat sändfel i dessa räknare. Detta ger starkare stöd för R5-fixen än den tidigare interna trepeer-fixturen. Det innebär inte att all framtida nätverksförlust är utesluten.

De stora slutliga `sample_age_ticks` gäller spår vars spelare redan dött. Renderklockan fortsätter avancera medan terminalfiguren är fryst. Tolka inte dessa värden som att levande spelare saknade positionsleverans.

### Bekräftat: resultatordningen är fel

`MultiplayerV2Service._maybe_finish_round()` sorterar finishers först, därefter alla spelare efter stigande terminaltick. Det ger den som dör först bäst placering bland utslagna spelare. Resultatvyn visar dessutom `Peer N` och härleder plats från radindex.

| Spelare | Terminaltick | World x, ungefär | Orsak | Nuvarande plats | Plats enligt V1:s distansregel |
| --- | ---: | ---: | --- | ---: | ---: |
| Peer 1 | 198 | 1 846,5 | spikes | 1 | 3 |
| Peer 3 | 312 | 2 780 | step_spikes | 2 | 2 |
| Peer 2 | 1 591 | 13 438,3 | spikes | 3 | 1 |

Samtliga dog. Det här är ett funktionellt resultatfel, utöver den saknade presentationen. V1 visar en rankad lista med medaljer; en fysisk trestegspall är ett tillägg till den komponenten.

### Återanslutningen: konkreta luckor, inte bevisad ICE-orsak

Gästerna har två `peer_connection_created` var. Hosten registrerar två `reconnect_sync_timed_out` i lobbyn, med cirka 17,54 respektive 17,86 sekunders redan ackumulerad tid. Därefter följer sync-svar och bekräftelse. Inga `peer_disconnected` eller automatiska `restart_requested` finns registrerade i dessa rapporter.

Koden har två tydliga luckor:

1. `_on_peer_connected()` startar gästens sync bara om `_disconnect_since_usec` redan finns. En första anslutning får statusen ”validating session”, men använder inte ovillkorligen samma fullständiga bekräftelseförfarande.
2. Gästens automatiska retry väljer främst saknad transport eller kombinationen sync-pending och fel API-peer-ID. En anslutning med rätt peer-ID men utebliven sessionsbekräftelse kan bli kvar utan en aktiv återhämtningsväg. Sync-deadline återanvänder dessutom den äldre outage-tiden och kan vara förbrukad när transporten precis blivit ansluten.

Det finns också en oåtkomlig guest-gren inne i host-grenen i `_check_disconnect_grace()`. Den ska redas ut när ansvar för recovery görs explicit.

Skinbyten sker genom lobbyproviderns backendanrop och room-uppdateringar. Att hosten ser ett skin bevisar därför kontakt med backend, men inte att spelarnas WebRTC-session är färdig och bekräftad. Rapporterna bevisar inte att den ursprungliga länken först var frisk och sedan bröts. Exakt första felsteg behöver en fixture och bättre handshakehändelser.

### Blockhändelsen: två rimliga mekanismer

De tre bifogade rapporterna beskriver spikes/step_spikes, inte ett blockdödsfall. Dra ingen säker slutsats om den andra rundan.

V2:s `_player_render_pose()` lägger dock till `slot * 18` pixlar till spritepositionen. Peer 2 får +18 och Peer 3 +36 pixlar jämfört med kollisionspositionen, även när terminalpositionen fryses. Detta kan direkt visa en figur inne i ett hinder trots att simulationen stannade vid kanten. V1:s motsvarande offset togs bort vid sammanslagningen; V2:s finns kvar.

Dessutom kontrolleras terminalkontakt efter ett diskret fysiksteg. Vid 500 px/s och 60 fysiktick/s är ett horisontellt steg cirka 8,33 pixlar. Vertikal rörelse och rörliga hinder kan ge ytterligare överlappning. `Motion.SIZE` är 34 × 44 pixlar; spritegrafiken och den faktiska hitboxen måste jämföras separat. Terminalkontakt i den första kandidatkontrollen används inte som en generell lösning för att stanna exakt vid första kontakt.

### Kamera och singleplayer: redan infört

`systems/runner_camera.gd` är en riktig `Camera2D` som används i alla tre lägen. Den följer en redan samplad renderpose utan extra kamerautjämning. `systems/runner_presentation.gd` interpolerar föregående och aktuella simulationstillstånd.

Singleplayers `main._process()` samplar med `Engine.get_physics_interpolation_fraction()`, flyttar spritepresentationen och låter kamera och banritning utgå från samma renderposition. Fysikpositionen ändras inte av rendering. Rörliga barrels har också visuell interpolation. Variabla hastigheter från items kräver inga jämnt delbara tal.

Tidigare verifiering omfattar 30/60/75/120/144 Hz och 475/500/507,35/525 px/s, inklusive reset/blockering och oförändrad kollisionsposition. Den visar att mekanismen är införd, inte att varje riktig browser/skärm upplevs helt jämn. Ingen singleplayer-rapport bifogades här. Frame-ringen i V2-rapporterna innehåller bara slutdelen av matchen: 4 096 frames, med tusentals bortträngda äldre frames. Gör ingen bedömning av hela startens frame pacing utifrån den svansen.

## Rekommenderad införandeordning

1. Lägg till reproducerande beteendefixtures för resultat och första anslutning samt bättre livscykeldiagnostik.
2. Rätta rankning, resultatkontrakt och slutlig rundfas.
3. Rätta första handshake och automatisk recovery utan att försvaga sessionsvalideringen.
4. Ta bort V2:s visuella x-offset och verifiera kollisioner. Inför kontaktprecision där reproduktion visar behov.
5. Inför gemensam resultatkomponent/prispall och robust lobbyåtergång.
6. Flytta debugkontroller, ta bort distans-HUD och rätta namnetiketter.
7. Verifiera singleplayer-flytet på riktig rendering och publicera en samlad release när accepterade tester passerar.

## A. Resultatmodell och slutlig rundfas — högsta prioritet

Berör främst `systems/multiplayer_v2/multiplayer_v2_service.gd`, `v2_round_coordinator.gd` och resultathanteringen i `ui/multiplayer_v2/multiplayer_v2_match.gd`. Jämför med `ui/multiplayer_match.gd` och `ui/result_medal.gd`.

Inför en gemensam ren resultatmodell, exempelvis `systems/race_results.gd`, med adapters för V1/V2. Behåll V1:s nuvarande vinnare-, disconnect- och tie-semantik vid extraktionen. Separera spelregler från UI.

- Bygg resultat från den frysta rundroster som användes vid start. Den levande lobbyroster som idag används får inte ändra vilka deltagare rundan väntar på eller vilka namn/skins resultatet visar.
- Finishers kommer före övriga och ordnas efter finish-tick. Utslagna ordnas efter nådd distans, fallande. Använd samma startpunkt och tie-tolerans som V1, utan att runda bort skillnader för tidigt.
- Gör plats och vinnare explicit. Stabil radordning för lika resultat får inte i sig utse en ensam vinnare. Bevara V1:s hantering av lika distans och bekräftade avbrott. Dokumentera särskilt hur lika finish-tick hanteras innan den gemensamma modellen tas i bruk.
- Varje rad ska bära stabil spelaridentitet, peer/slot för diagnostik, fryst display_name, skin, place, state, distans och separat terminal-/finish-tick. Kalla inte alla dödstick för `finish_tick`.
- Hosten committar samma immutabla resultat till alla. Gäster validerar round/session/revision och renderar den bekräftade platsen; de räknar inte om ordningen från nätverkets ankomsttid.
- Fallback vid saknat namn får vara ”Spelare N”. `Peer N`, råa `step_spikes` och tekniska state-strängar hör hemma i diagnostiken. Översätt spelorsaker till spelarnas språk.
- Lägg till ett explicit avslutat coordinator-tillstånd eller motsvarande avslutningsmetod. Nu saknar enum ett FINISHED-tillstånd och coordinator kan stå RUNNING när backend redan är FINISHED. Avsluta aktiv start-/disconnectövervakning, men behåll resultatretries/ACK tills leveransen är säkrad eller sessionen stängs.
- Uppdatera diagnostikens aktuella fas och generation; skilj ursprunglig sessionsmetadata från aktuell status. Bekräftade terminalspår ska redovisas som terminal/frozen, utan missvisande aktiv stale-alarm.

Acceptans: denna rapports fixture ger ordningen 2, 3, 1 hos alla klienter. Testa blandning av finish/death/disconnect, lika distans, lika finish-tick, dubblett-commit, fördröjd ACK, spelare som lämnar efter död samt gamla resultat efter nästa rundas start. V1:s befintliga resultatbeteende ska bestå.

## B. Första anslutning och recovery — högsta prioritet

Berör `multiplayer_v2_service.gd`, V2:s WebRTC-transport, RPC-endpoint och lobbyvy. Kontrollera befintliga reconnect-/world-sync-kontrakt innan ändring.

Definiera per peer en explicit kedja: anslutningsförsök → transport ansluten → session validerad → nödvändig world-sync bekräftad → startklar. Backendens `is_ready` och skinbekräftelse ska visas som separata egenskaper.

1. Låt första anslutning och återanslutning gå genom samma idempotenta sessionshandshake. Gästens anslutning till hosten ska alltid starta rätt handshake, även utan tidigare outage. I OPEN kan world-baseline vara tom; i RUNNING krävs befintlig validering/synkronisering.
2. Starta handshake-timern när en ny handshake börjar. Behåll en separat total outage/grace-timer för spelregler. En gammal väntetid får inte omedelbart timeouta en ny, nyss ansluten lobbylänk.
3. Retrya ett uteblivet sync-svar/ACK först på den fungerande länken, med begränsad backoff och request-ID. Återskapa länken först när transporten eller den begränsade handshaken faktiskt misslyckas. Förhindra offer-stormar och parallella försök.
4. Gör recovery-ansvaret explicit: gästen initierar offer/recovery enligt nuvarande transportmodell; hosten kan begära/bevaka det. Ta bort den oåtkomliga grenen. Ett rätt peer-ID får inte vara enda argumentet för att avstå recovery.
5. Logga handshake start/skickad/mottagen/avvisad/ACK/bekräftad med attempt-ID, request-ID, aktuella generationer, transportstatus och avslagsorsak. Separera första anslutning från återanslutning. Logga inte hemliga signalingpayloads.
6. Reproducera olika ordning på join, roster-refresh, ready, skinbyte och heartbeat. Undersök strikt `lobby_generation` i `_packet_session_error()` och när transportens generationskontext uppdateras. Ändra kontraktet bara om denna reproduktion visar ett problem. Acceptera inte godtyckligt gamla generationer, fel runda eller fel session för att få ett grönt statusljus.
7. `get_start_blockers()` ska kräva bekräftad aktuell session för alla deltagare, utöver transport, ready och manifest-ACK. UI ska förklara ”ansluter/bekräftar” och återhämta automatiskt. Manuell Reconnect finns som reserv i felsökningsvyn.
8. Ett vanligt heartbeat får inte ersätta required world-sync under en aktiv runda. Bevara autentisering, assigned peer mapping och grace-regler. Kontrollera samtidigt att avslutade rundor inte får nya disconnect-terminaler.

Acceptans: tre färska klienter, gästerna byter skin och blir ready; vänta minst 20 sekunder före start. Alla blir startklara utan manuell Reconnect. Kör både snabba/långsamma joins och fördröjt sync-svar. Testa verklig transportförlust, ansluten men tyst länk, API-peer-ID-reset, utebliven ACK och stale generation. Återhämtning får inte dubblera deltagare eller släppa igenom osynkad world-state.

## C. Kollision och visuell position

Berör `_player_render_pose()`, `_step_local_round()`, V2-world-contact, terminalrapporter och delade hazarddefinitioner.

Första ändringen är att ta bort `slot * 18` från spritepositionen i V2. Sprite, namnetikett, terminalpose och kamera ska använda samma samplade world-position. Hantera överlappande spelare med kontur, transparens eller etikettlayout; flytta inte dem i färdriktningen för att göra dem synliga. Uppdatera befintlig scenfixture som idag uttryckligen accepterar slot-offset.

Inför en dold kollisionsdebugvy och en liten terminalhändelse med föregående pose, föreslagen pose, slutlig pose, hastighet, gravity, tick, entity-ID, hazardtyp och kollisionsgeometri. Lägg till ett kort förlopp kring döden så att händelsen finns kvar även om användaren exporterar långt efteråt.

Reproducera block från vänster, ovanifrån och underifrån; gravity flip nära kanten; step-block på sluttning; samma situation för samtliga slots. Jämför hitboxen 34 × 44 med spritegrafikens utbredning. Dela upp förskjutning av presentation, vanligt diskret överlapp och felaktig kontaktregel.

Om det återstår diskret penetration: inför första kontakt längs rörelsesegmentet, exempelvis swept AABB/time-of-impact för relevanta blockformer. För spikes och rörliga barrels måste deras befintliga kollisionsformer och relativrörelse användas. Rörliga hinder ska inte behandlas som statiska rectangles. Uppdatera horisontell och vertikal hantering tillsammans med floor/ceiling support, blockeringsregler och shared-barrel claims.

Returnera kontaktfraktion/normal/entity och terminalpose från simulationen. Ägarklienten rapporterar samma pose som den själv fryser; hosten committar den och remotes fryser där. Det får inte bli en kosmetisk clamp som endast flyttar bilden och lämnar distans/resultat på en annan punkt. Om första-kontaktlogik ändrar nådd distans ska det vara en dokumenterad spelregelsändring med tester.

Säkerställ även att sample skickas efter att `blocked` och terminalstatus har applicerats. Kontrollera terminalgravitation: idag kan en remote-terminal få gravity från sista vanliga sample trots en senare flip. Terminalkontraktet behöver tillräckliga diskreta fält för korrekt fryst pose.

Acceptans: ingen slotberoende x-skillnad; lokalt och remote terminalläge överensstämmer; blockstopp och dödpunkt ligger inom beslutad geometrisk tolerans vid varierande hastighet. Ingen passage genom tunna hinder, inga nya felaktiga dödsfall på slänter, ingen regression för barrels. Lägg motsvarande fixture för single/V1 där en delad kontaktfunktion faktiskt ändras.

## D. Gemensam resultatvy och prispall

Skapa exempelvis `ui/race_results_panel.gd/.tscn`, matad med den gemensamma resultatmodellen. Flytta V1:s befintliga medalj-/resultatrendering till komponenten med bibehållen funktion, och byt V2:s RichText-lista mot samma panel.

- Visa en kompakt prispall för de tre främsta, med namn, skin/figur och placering. Vid tre olika platser används vanlig ordning 2–1–3. Visa en rankad lista för alla deltagare under pallen.
- Delad placering ska vara tydlig; duplicera inte en ensam vinnare eller tvinga olika medaljplatser vid oavgjort. Använd en anpassad rad/pallayout för ties och färre än tre deltagare.
- Terminalorsak är sekundär information med läsbara översättningar. Distans kan användas som sekundär resultatdata om det hjälper att förstå placeringen; den ska bort från vanlig match-HUD.
- Namn och skins kommer från den frysta roster som resultatet avser, även efter lobbyförändring eller leave.
- Resultatet ska passa mobil och små fönster: dynamisk storlek, radbrytning/namnförkortning, scrollbar för listan vid behov och åtkomliga knappar. Undvik nuvarande fasta 450 × 320 som enda layout.
- Använd produkttext som ”Rundan är slut”, ”Till lobbyn” och ”Lämna”. Tekniska peers/versioner hör hemma i debugvyn.

Acceptans: 1–5 spelare, långa/samma namn, olika skins, oavgjort, disconnect, alla döda, flera finishers, telefon och bred desktop. Samma bekräftade resultat hos host och gäster.

## E. Lobbyåtergång och omspel

Rekommendation: tillåt individuell navigation till lobbyn men låt bara hosten öppna nästa rundas gemensamma lobbygeneration. Det motsvarar användarens acceptans för den individuella knappen och behåller auktoriteten över omspel.

Idag navigerar varje klient direkt från resultatvyn. Hosten skickar ett asynkront backendanrop, men navigerar också innan svaret och rensar delar av resultatleveransen omedelbart. `RETURN_TO_LOBBY` uppdaterar gästens servicetillstånd, men matchvyn har ingen självklar gemensam navigation kopplad till den uppdateringen.

- Separera ”visa lobby” från ”bekräfta ny lobbygeneration”. Gästknappen ska inte resetta den delade rundan. Visa ”väntar på hosten” när backend fortfarande är FINISHED.
- Hosten ska få bekräftelse eller tydligt fel på återöppningen. Bevara fryst resultat och pågående leverans tills övergången är säker. Ny generation, nya ready-flaggor och rensning av rundtillstånd ska tillämpas atomiskt/idempotent.
- Klienter som fortfarande visar resultat måste kunna ta emot gemensam lobbyövergång och nästa PREPARE utan att fastna med gammal scen. Använd en persistent navigationssamordnare eller följ hostens bekräftade lobbyövergång i matchscenen. Rekommenderat beteende är att hostens bekräftade övergång även tar kvarvarande resultatvyer till lobbyn.
- Gamla RESULT_COMMIT/TERMINAL_COMMIT får inte återöppna resultat efter ny generation. PREPARE ska fortfarande kräva scen-ready innan start; sätt aldrig ready automatiskt som lösning på saknad scenövergång.
- Leave/host leave ska följa befintliga failure-regler med tydlig UI och städning av signaler/scener.

Acceptans: gäst tillbaka först, host först, en gäst kvar på resultat, sena commits/ACK, misslyckat backendanrop och tre omspel. Inga nya Reconnect-klick, inga gamla terminalfigurer/resultat i nästa runda.

## F. HUD, debugmeny och namn

Flytta Position rate 30/60 Hz och Save diagnostics till en avsiktligt öppnad meny/felsökningspanel, gärna gemensam med V1. Lägg en liten menyknapp som fungerar på touch. En multiplayer-meny får inte pausa den gemensamma simulationen; låt inte öppna/stänga menyn av misstag generera flip-input.

Ta bort `_distance_label` ur vanlig V2-HUD. Behåll distans, tick, position rate, transportstatus och peers i diagnostiken. Vanlig matchvy visar endast relevanta spelbesked, exempelvis spectator med spelarens namn och väntan på resultat. Ratevalet avser sändfrekvens för positionssamples, inte fysikens 60 Hz eller skärmens FPS; märk det begripligt i felsökningspanelen. Behåll nuvarande möjlighet att jämföra 30/60 utan att oavsiktligt ändra vem inställningen gäller för.

Ge diagnostikexport en egen bekräftelse/toast som inte skrivs över av nästa `_update_hud()`. Export ska fortfarande fungera från lobby, aktiv match och resultat.

Namn placeras ovanför figurens hitbox vid normal gravitation och under vid flippad gravitation. Texten ska vara upprätt i båda fallen. Beräkna centrering från fontens verkliga bredd och placera baseline med fontens höjd; ta bort fast x-offset −16. Utgå från samma renderpose och gravity som sprite/kamera, även vid terminalfreeze och spectatorbyte. Använd kontrast/kontur och rimlig marginal till ceiling/floor. Hantera sammanfallande etiketter genom etikettlayout, utan att flytta löparen.

Acceptans: flips mitt i hopp och nära tak/golv, långa namn, remote terminal efter sista flip, överlappande spelare, ändrad viewport. Inga debugkontroller eller distance i normal matchvy.

## G. Singleplayer: verifiera den införda förbättringen

Börja med mätning och reproduktion. Lägg inte på en andra kamera-smoothing-loop och ändra inte löparhastigheter för att matcha bildfrekvensen. Den nu införda interpoleringen är grundlösningen.

Utöka `tools/unified_presentation_test.gd` med 50/90/165/239/240 Hz, ojämna frame-delta och flera catch-up-tick. Behåll tidigare varierande hastigheter och lägg till faktiska itemkombinationer/hastighetsövergångar. Verifiera kamera, sprite och stillastående hinder i samma renderframe, inte bara monotonic löparposition.

Lägg till valbar singleplayer-diagnostik: frame-delta, fysiktick/fraction, tidigare/aktuell/render-player-pose, kamera-left, render course distance och skärmposition för ett fast referenshinder. Mät hinderförflyttning per rendersekund under segment med konstant faktisk simulationhastighet. Separera verklig acceleration/blockering från periodiska presentationsvariationer. Sluttning/zoom/perspektiv och bildskärmens refresh kan påverka upplevelsen och ska märkas i testet.

Kontrollera särskilt:

- Alla stillastående spikes/block/slopes ligger kvar i världen och använder kamerans enda transform; ingen kvarvarande avrundad kursposition används vid render/culling av synliga objekt.
- Rörliga barrels och andra animerade världselement samplas en gång per frame med avsedd interpolation. Undvik olika samplingstid för samma entitet mellan sprite, namn och kamera.
- Start, död, retry, gravity flip, blockering, itemförändring och viewportbyte resetar historik när det behövs, utan ett extra visuellt hopp.
- Singleplayerkamerans runtime-inställningar motsvarar den gemensamma kamerans avsedda interpolation/smoothing, även när script sätts på den redan befintliga Camera2D-noden.
- Browserns faktiska frame pacing, CPU-kostnad och rendering under hög refresh. Numeriskt jämn interpolation kan fortfarande få ojämna visade frames om main thread missar tidsbudgeten. Optimera bara flaskhalsar som profileras; ändra inte nätverksklockan för att lösa lokal rendering.

Spela/exportera en verklig singleplayer-runda på samma maskin där symptomen sågs. Filma eller mät ett konstant-hastighetssegment med ett stillastående hinder; jämför 60 Hz och hög refresh, inklusive web-export. Acceptans är jämn skärmförflyttning inom vald mättolerans och ingen regelbunden fysiktickrelaterad platå vid konstant hastighet. Dokumentera verklig FPS, skärmrefresh och kvarstående variation. Vid observerad restjitter gör en separat konkret fix och regressionstest; markera inte det som färdigt enbart för att grundinterpoleringen finns.

## H. Diagnostik, tester och release

Behåll begränsade ringbuffertar, men låt viktiga livscykel-/terminalhändelser överleva många frames på resultatvyn. Ha separata sammanfattningar för lobby, levande match, spectator och resultat. För terminalhändelser behövs ett kort bevarat frame-fönster. Använd `at_unix_usec` för jämförelse mellan klientrapporter och monotonic tid för durationer inom varje klient; jämför inte klienternas `at_usec` direkt.

Föreslagna beteendetester: `race_results_test.gd`, V2 initial-handshake/recovery-fixture, terminal-collision-fixture och result-panel/scennavigationsfixture. De ska köra verkliga modell-/stateövergångar, inte bara leta efter en viss text i källkoden. Uppdatera befintliga V2-kontrakt, unified presentation och V1-presentationstester när kontrakt förändras.

Slutlig manuell matris:

| Prov | Måste visa |
| --- | --- |
| Tre färska webbklienter, skin/ready, 20 s lobby | Automatisk bekräftad session och start |
| Den bifogade rundans terminalfixture | Peer 2 först, Peer 3 tvåa, Peer 1 trea, namn/skins |
| Block/spikes, alla slots, både gravityriktningar | Samma korrekt frysta kollisionspose |
| Host dör först, gäster fortsätter | Synliga remotes och sammanhängande spectator-kamera |
| Individuell lobbyåtergång + tre omspel | Hostägd generation, inga manuella reconnects |
| Förlust av transport/sync/ACK | Begränsad automatisk recovery och befintlig grace/säkerhet |
| Mobil/små fönster | Läsbar pall/lista, åtkomliga knappar, ren HUD |
| Singleplayer vid 60 och hög refresh, items | Uppmätt flyt utan tickplatåer |
| V1 full runda och omspel | Bibehållen authority, rankning och navigation |

Kör relevanta headless/scen-/nätverkstester, `git diff --check` och web-export. Kör riktiga separata webbklienter genom lobby/start/resultat; den interna WebRTC-fixturen ensam räcker inte för handshake och omspel. Redovisa uttryckligen vilka mänskliga/visuella tester som återstår.

Om resultat-/terminal-/handshakekontrakt ändras ska kompatibilitet granskas och V2-version/build-ID höjas så att gamla klienter inte blandas med nya. Befintliga backend-RPC:er bör räcka; skapa ingen migration utan ett konkret backendbehov. Om det behövs en migration ska den få ett nytt unikt versionsnummer och båda redan införda migrationerna bevaras.

Committa endast arbetets filer. Bevara övriga lokala analyser och scratchfiler. Publicera en gemensam export via dokumenterat rootflöde i `DEPLOYMENT.md`, med cachebrytning och verifierat Pages-jobb. Leverera en implementationsrapport med vad som införts, tester, eventuella kvarstående orsaker och den gemensamma URL:en.

## Definition av klart

Resultatet visar rätt namn och bekräftad placering med gemensam pall/resultatkomponent. Första anslutning och tre omspel fungerar utan manuellt reconnect i normalfallet. Ingen slotförskjutning skapar skenbar hinderpenetration. Kollisionernas återstående precision är reproducerad och åtgärdad eller tydligt avgränsad med evidens. Normal HUD är ren, namn följer gravitationen och singleplayer-flytet har verifierats på riktig rendering. V1:s authority och V2:s klientägda runner är bevarade, och alla tre lägen publiceras på samma rootadress.
