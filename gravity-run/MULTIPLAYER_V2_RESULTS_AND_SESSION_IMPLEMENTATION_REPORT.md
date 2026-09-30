# Resultat, anslutning och presentation: införanderapport

Datum: 2026-09-30. Källbranch: `codex/current-prototype`.
Build: `2026.09.30-results-session`. V2-kontrakt: `2.1.20260930.3`.
Gemensam speladress: https://hjelmdev.github.io/gravity-run/

## Genomfört arbete

Arbetet följer `MULTIPLAYER_V2_RESULTS_RECONNECT_AND_PRESENTATION_IMPLEMENTATION_PLAN.md`. Luna delegerades resultatmodell, första presentationen och tillhörande tester. Huvudagenten granskade och integrerade dessa och genomförde sessionsprotokoll, lobbyövergångar, kollisionskontakt, diagnostik, singleplayer-kontroller och release. Ingen ny merge eller backendmigration behövdes.

### Gemensamma resultat för V1 och V2

`RaceResults` bygger explicita placeringar från rundans frysta roster och terminalrapporter. Namn, identitet och skin följer rundans deltagare även om den aktuella lobbyn ändras. Finishers rankas först efter sluttick; övriga efter längst uppnådd sträcka. V2 delar placering vid samma sluttick eller samma utslagningssträcka. V1 behåller sin tidigare regel för lika sluttick och sin befintliga vinnar-/authoritylogik.

Den bifogade rundans modellfixture ger Peer 2 först, Peer 3 tvåa och Peer 1 trea. Den tidigare stigande dödsticksordningen används inte längre för V2-rankningen.

`RaceResultsView` används i båda multiplayerlägena. Den visar pall, namn, skins, explicita placeringar och medaljlista. Delade platser visar deltagarna tillsammans på samma steg. Långa namn radbryts; resultatlistan kan skrollas och knapparna ligger utanför den. Dödsorsaken finns som läsbar tooltip, inte som `Peer N — eliminated (...)` i huvudresultatet.

V2:s resultat är hostbekräftade och frysta. RESULT_COMMIT kontrollerar rund-ID, resultat-ID/version, deltagarantal, unika deltagare och giltiga platser. Upprepade commit-meddelanden kvitteras utan att återöppna resultatet; en föregående rundas commit kan inte återöppna en återställd lobby. Coordinatorn har ett explicit FINISHED-läge.

### Första anslutning och recovery

Första WebRTC-anslutningen kör nu samma fullständiga sessionsbekräftelse som återanslutning. Varje synkförsök får ett nytt request-ID och en egen deadline från transportanslutningen. ACK, CONFIRMED och COMPLETE måste matcha aktuellt försök, rund-ID och världsrevision. Gamla svar kan inte bekräfta ett nytt försök. Hosten blockerar start tills de obligatoriska gästsessionerna är bekräftade.

En ansluten transport med utebliven sessionsbekräftelse försöker synka igen och kan sedan återskapas med begränsad retry. Även den första transporten utan någon tidigare heartbeat kan återhämtas automatiskt. Detta sista fall hittades i det verkliga webbprovet: en gäst kunde tidigare ligga kvar i Connecting utan att recovery-villkoret någonsin blev sant. Den oåtkomliga guest-grenen i hostlogiken har tagits bort. Befintlig grace för en pågående runda finns kvar.

Kontroll-RPC skickas först när både datakanalen och MultiplayerAPI-transporten är anslutna; protokollets retries täcker väntan. Gäster visar övriga gäster som anslutna via hosten när hostlänken är klar, i stället för att felaktigt antyda att en direkt gäst-till-gäst-länk saknas. Ett backendbekräftat skinbyte betyder fortfarande inte i sig att WebRTC-sessionen är färdig.

### Lobbyåtergång och omspel

En gäst får fortsätta gå till lobbyvyn individuellt. Det ändrar inte hostens ansvar för backendfas, generation och nästa runda. Hosten behåller resultatet medan backendåtergången pågår och navigerar först när den lyckats; fel visas på resultatvyn. RETURN_LOBBY återställer gästernas runddata, terminaler och coordinator. Navigationsguard förhindrar dubbla scenbyten när backend-uppdatering och protokollhändelse kommer nära varandra. Transport/session behålls genom normala omspel.

### Kollisionsposition i V2

Spritepositionen använder samma world_x som runnerns kollisionspose. Den gamla slotförskjutningen på 18/36 pixlar är borttagen även vid död och spectator.

V2 beräknar första kontakt under hela fysikstegets förflyttning för statiska block, steg och faktiska spike-trianglar. Runnern fryses vid kontaktpunkten innan terminalrapporten skickas. Detta förhindrar att ett steg placerar runnern inne i ett tunt hinder. Fixturen täcker olika hastigheter inklusive 507,35 px/s, horisontell och vertikal kontakt, båda vertikala riktningarna och spikgeometri. Kandidatfrågan muterar inte hostens entity-ledger.

Rörliga barrels behåller sin befintliga hostauktoritet och kontaktmodell. Den nya statiska sweepen är inte en allmän lösning för kollisionsprecision mot rörliga objekt. De ursprungliga användarrapporterna innehåller spikes/step_spikes, inte det observerade blockdödsfallet; dess exakta tidigare orsak kan därför inte bevisas retroaktivt.

### Renare matchvy och bättre diagnostik

30/60 Hz och export ligger i V2:s meny för diagnostik. Distansraden är borttagen från match-HUD. Namnet centreras ovanför normal runner och under flippad runner, med texten rättvänd. Den terminalbekräftade gravitationen bevaras också för döda remotes.

Diagnostik skiljer frysta terminalspår från för gamla levande samples. De sista 120 frames före terminalhändelsen bevaras separat; resultatvyn skriver inte över matchfönstret. Kontaktlogg innehåller föregående, föreslagen och slutlig pose, hastighet och kontaktgeometri. Sessionsfas/generation hålls aktuell i rapporterna.

## Singleplayer och Camera2D

Singleplayer, V1 och V2 använder redan den gemensamma riktiga `RunnerCamera`/Camera2D och renderinterpoleringen från den tidigare sammanslagningen. Hastigheter behöver inte vara jämnt delbara med fysik- eller skärmfrekvensen. Den här ändringen sätter dessutom uttryckligen Camera2D:s inbyggda interpolation till OFF och smoothing till false i singleplayer: kameran får redan en interpolerad pose och ska inte filtrera den igen.

Singleplayer har valfri inspelning under Paus → diagnostik för bildflyt. Rapporten innehåller render-delta, fysiktick/fraction, föregående/aktuell/renderad x, kamerans vänsterkant, hastighet/blockering, statiskt hinders world-/screen-x, FPS, seed, viewport och zoom. Export finns både i diagnostikmenyn och efter rundan när inspelning varit aktiverad. Resultatframes skriver inte över körningen. Escape efter död öppnar inte längre en dold pausvy som blockerar resultatknapparna.

`singleplayer_render_capture.gd` körde den normala singleplayerscenen med riktig OpenGL-rendering på denna maskin, med FPS-tak 60 och 144. Efter de första 20 uppvärmningsframesen mättes:

| FPS-tak | Analyserade frames | Genomsnittligt render-delta | Platåer i render-x | Bakåtrörelser | Par med samma statiska hinder |
| --- | ---: | ---: | ---: | ---: | ---: |
| 60 | 157 | 16,666 ms | 0 | 0 | 145 |
| 144 | 318 | 6,944 ms | 0 | 0 | 102 |

Hindrets skärmförflyttning motsvarade hastighet gånger render-delta inom avrundning i dessa segment. Detta är mätning av verklig engine-rendering med FPS-tak, inte mätning av skärmens fysiska presentation eller en verifiering på användarens specifika webbläsare/skärm. Numeriska regressionstester omfattar 30–240 FPS, ojämna frametider och hastigheter 475, 500, 507,35 och 525 px/s.

## Verifiering

- Resultatmodell och den bifogade rundans ordning: PASS.
- V2 initial handshake, gamla ACK, retry/deadline, första saknade transport utan heartbeat, frozen roster, resultat-idempotens och lobbyreset: PASS.
- Tre riktiga native WebRTC-peers, automatisk sync, 20 sekunder lobby och tre resultat/ACK/RETURN_LOBBY-cykler med samma peer-ID:n: PASS. Detta test använder backendstub och ersätter inte webbprovet.
- Webbexport med tre separata klientidentiteter mot den riktiga backend-lobbyn: automatisk första anslutning, skinbyten, ready, första start och tre omspel, samma resultat hos alla, individuell gästretur och hoststyrd lobbyretur kontrollerade. Ingen manuell reconnect användes efter recovery-rättningen. Exporterade host-/gästrapporter bekräftar fungerande positionsleverans: hosten 1 581 lyckade sändförsök, gästen 395/395, 791 mottagna nätverkssamples hos vardera. Räknarna är kumulativa för sessionen, inte endast den sista rundan. Senare små ändringar av menylager/delade pallporträtt och transportens RPC-guard verifierades separat i slutexporten.
- Statisk terminalkontakt, shared Camera2D/interpolation, V1:s resultat-/spectatorpresentation och befintliga simulations-/kontraktstester: PASS.
- Prispallen granskad med verklig rendering i 960×540 och 640×360. Ingen separat mobiltelefon användes.
- `git diff --check` och full Web-releaseexport kontrollerade. Sandboxens varningar om Godots lokala logg och certifikatläsning är miljöbegränsningar; inga GDScript-fel i godkända testkörningar.

## Kvarstående manuella kontroller

Kontrollera på användarens skärm/webbläsare att stillastående hinder flyter jämnt vid 60 och hög refresh, även över verkliga item-/hastighetsbyten. Använd den nya singleplayer-exporten om fart–inbromsning–fart fortfarande syns. Profilera faktisk frame pacing innan ytterligare klock-/renderändringar görs.

Gör gärna en längre spelad V1-runda och omspel, en V2-runda där hosten dör först och gäster överlever länge, verklig nätförlust samt ett mobilprov med långa namn. Dessa scenarier är delvis täckta av fixtures men hela hårdvaru-/nätmatrisen är inte verifierad genom mänskligt spel. Rörliga barrel-kollisioner kräver ett separat reproducerbart fall om fel kontaktposition fortfarande observeras där.

Alla lägen behåller samma rootpublicering; ingen separat V2-URL eller ny databasversion införs.
