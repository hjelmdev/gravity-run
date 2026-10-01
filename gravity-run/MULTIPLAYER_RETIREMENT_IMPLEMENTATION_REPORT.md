# Multiplayer: pensionering av V1 och neutrala produktnamn

Datum: 2026-10-01. Införd enligt MULTIPLAYER_V1_RETIREMENT_AND_PUBLIC_NAMING_IMPLEMENTATION_PLAN.md.

## Ändringar

- Hubben har en enda Multiplayer-knapp. Den neutrala startvägen instansierar tidigare V2:s lobby och match. Matchens retur använder den enda neutrala AppNavigation-intentionen.
- V1:s lobby/match, service, WebRTC-transport, diagnostik och fem V1-exklusiva tester är borttagna ur Godot-projektet. V1:s två autoloads är borttagna, så de kan inte skapa nätverksnoder, polla eller signalera i bakgrunden. Koden finns i Git-historiken samt en lokal arbetskopia utanför projektets resurskatalog.
- Gemensamma runner-, kamera-, simulerings-, kurs- och presentationshjälpare är kvar. V1-transportens före detta presentationstest är pensionerat tillsammans med transporten; aktiva kontrakts-, presentations-, kursflödes- och sessionstester finns kvar.
- Spelartexter och diagnostikknappar är neutrala. Nya svenska översättningar omfattar förberedelse, manifestfel, start-/avbrottsfel och versionsetikett.
- 30/60-väljaren och runtime-settern är borttagna. Host-/gästaktivering återställer 30 Hz och sändackumulatorn, och skriver position_rate_hz i sessionen innan diagnostiken startar. Omspel återanvänder denna låsta sändperiod och nollställer ackumulatorn i begin_round.
- Lobby och match behåller Spara diagnostik, även efter rundslut. Filprefixet är multiplayer_lobby respektive multiplayer_match. Singleplayers diagnostik och den begränsade exportvägen är kvar. Inga nya alltid aktiva framebuffertar tillkommer.

## Kompatibilitet

Interna paths och namn under multiplayer_v2/, MultiplayerV2Service och klassnamnen behålls. Det är ett dokumenterat senare refaktoreringsarbete, utan andra publika spellägen. network_mode="v2", protokollversion, V2_GAME_VERSION, backend-RPC/tabeller, migrationshistorik samt v2_profile/v2_render_anchor behålls för kompatibilitet. Ingen live-migration eller databasradering görs.

Simulationens 60 Hz, rendering, client-authority, kollisionsregler, startbarriär, readiness, rangordning och lobbyreturpolicy ändras inte. Renderankaret är fortsatt opt-in. Detta införande gör inget anspråk på att lösa upplevelsen av ojämnt hinderflöde.

## Verifiering före publicering

- Multiplayer retirement: faktisk hub-/menyrouting till aktiv lobby, matchscen, neutral engelsk/svensk diagnostik, frånvaro av rate-väljare och gamla autoloads. Två tiosekunders simulerade sändfönster gav 300 sample-dispatches vardera och 30 Hz-metadata från sessionens början; detta är ett test av sändschemaläggningen, inte en mätning av nätverkets väggklockleverans.
- V2 contract, session lifecycle, course flow trace, unified presentation, race course presentation, localization och diagnostics export passerade.
- Riktigt lokalt WebRTC-test passerade initial synk, 20 sekunders lobby och tre resultat-/ACK-/lobbycykler med bevarade peer-id:n. Detta testar transporten; det ersätter inte ett manuellt lopp med flera browseridentiteter.
- Exporttestet förberedde 1 200 stora frameposter på cirka 626 ms och passerade storleks-/trunkeringskontroller.
- Godot-import gav inga parse-/scriptfel. Sandlådemiljön rapporterar otillgänglig användarlogg/certifikatlagring och editorsettings; de ovanstående testerna passerar trots dessa miljöfel.

## Publicering

Webbygget ska komma från införandets källcommit, så befintliga ocommittade singleplayer-fixturändringar inte oavsiktligt följer med. Dessa ändringar lämnas kvar i arbetskatalogen.

Neutral bundle publiceras under docs/game/. Root-wrapper och manifest pekar dit. game-v2/index.html, multiplayer-v2/index.html och multiplayer-v2/game/index.html blir kompatibilitetsomdirigeringar som bevarar queryparametrar och fragment. De äldre bundlarna rensas inom respektive kontrollerad katalog. Rootens befintliga städning av äldre service-worker-scope/cache behålls.

Publiceringsresultat och browserverifiering kompletteras efter färdig build.
