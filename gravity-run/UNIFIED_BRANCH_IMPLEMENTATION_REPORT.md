# Införanderapport: gemensam kodbas och presentation

Datum: 2026-09-30. Källkod, migrationshistorik och gemensam publicering är införda. Ett fullständigt manuellt multiplayerprov genom lobby/start/resultat/omspel återstår; det ska inte förväxlas med de godkända transport- och scenproven nedan.

## Leverans och Git

Alla avsedda V2-ändringar finns nu på `codex/current-prototype`, pushad till Azure `origin`. Singleplayer, Multiplayer och Multiplayer V2 (test) finns i samma projekt och samma Web-export.

| Referens | Commit |
| --- | --- |
| Normalspår före merge | `4790caf51c89bbe129d0eaddbf0c1309acfb2b39` |
| V2 före sparande av senaste arbete | `456cc0efd57ced6f805d9c69f276caa38e55460a` |
| Sparat senaste V2-arbete, reconnect/session sync r7 | `d7f1b72` |
| Merge på normalbranchen | `1e64b5f` |
| Slutlig implementation och källa till publicerad export | `bc6826f17b069bd3bfb4515e52c3201a8c28ed67` |
| Pages före denna release | `7c5f24847a788a6b2f8a4701913477f20b0863d0` |
| Publicerad Pages-release | `4023e1407f9677a1237e366db860a4f631b9dbdd` |

De fyra ocommittade V2-filerna (`project.godot`, service, WebRTC-transport och kontrakttest) committades i V2-worktreet före merge. Deras r7-arbete ingår i normalbranchens historik. Den enda manuella mergekonflikten var projektversionen: slutvärdet är `2026.09.30-unified`. V2-autoload, menyval och den gemensamma banpresentationen ingår.

V1:s finish-/timingändringar från normalspåret behölls, liksom V2:s tidigare startbarriärer, peer map, failure recovery och reconnect session synchronization. V1:s auktoritativa terminaltillstånd/resultat och gästens tidigare prediktions-/renderklockor ersattes inte.

Lokala återställningsreferenser finns som `codex/backup-normal-before-unification-20260930` och `codex/backup-v2-before-unification-20260930`. V2-worktreet behålls tills användaren har granskat leveransen. Befintliga ospårade analyser, planer och scratchfiler mass-stagades inte.

## Migrationskollisionen

Båda funktionaliteterna är bevarade. Remote-historiken för `202609290003` avsåg `v2_lobby_skin_rpc`; dess registrerade statements innehöll skin-funktionen och inte readiness-funktionen. Därför behölls dess befintliga versionsnummer.

Readiness-filen fick det nya, oanvända namnet `202609300001_require_all_v2_players_ready.sql`. Innehållet ändrades inte. En dry-run visade att enbart den migrationen återstod, varefter den applicerades på den länkade databasen. Läsning av backendfunktionerna bekräftade både `multiplayer_v2_set_skin` och readiness-kontrollen i `multiplayer_v2_prepare_round`.

Slutlig `supabase migration list --linked` visar matchande lokal/remote historik för samtliga 34 versioner, inklusive `202609290003`, `202609290004` och `202609300001`. Ingen historik reparerades bort och ingen databasreset kördes.

## R5: positionsleverans och remote-presentation

Positions-RPC:n använder nu `unreliable_ordered` på logisk kanal **0**. WebRTCMultiplayerPeers inbyggda kanaler väljs efter transfer mode på kanal 0; den tidigare explicita kanalen 1 saknade motsvarande extrakanalkonfiguration. Signaler, start, audit och terminalkontroll fortsätter på sina tillförlitliga kanaler.

Endpointens sändmetoder returnerar nu ett verkligt `Error` från `Node.rpc`/`Node.rpc_id`. Servicekedjan räknar försök, OK/fel och mottagning separat för lokala host-samples och nätverkssamples. Den registrerar avslag per owner/sender/anledning och godkända samples per owner. Första sändfelet får en diagnostikhändelse med kanal, mode, mål, runda och sekvens.

Matchscenen räknar track-insertions/rejections per owner samt exponerar valid/stale, sekvens, render tick och sample age. Tracks avancerar varje renderframe. Spectator väljer endast giltiga remote-spår, och kameran följer samma visade position inklusive V2:s befintliga slot-offset. Bekräftade remote-terminalpositioner fryser; resultatstatus skrivs inte över av vanlig HUD-uppdatering.

V2:s lobbyversion är höjd från `2.1.20260930.1` till `2.1.20260930.2`, så att gamla V2-klienter inte blandas med den ändrade positionskonfigurationen. Runtime-build-ID är `2026.09.30-unified`.

## Gemensam kamera och interpolering

`systems/runner_camera.gd` är en faktisk gemensam `Camera2D` för alla tre lägen. Den följer en redan samplad renderposition, utan en extra smoothing-loop. Bana, sprites och namnetiketter använder världskoordinater; multiplayerbanan flyttas inte längre samtidigt som kameran. Mållinjen ritas i rätt världsposition.

`systems/runner_presentation.gd` ger föregående/aktuell position och interpolation mellan dem. Det krävs inga hastigheter som delar bildfrekvensen jämnt. Singleplayer använder Godots physics-fraction och flyttar enbart spritens presentation; spelarens kollisionsposition hålls kvar i simulationen. Kameran och den ritade banan använder samma renderposition. Restart och terminaltillstånd återställer renderhistoriken.

V1-hosten samplar de två sista simulationsticken med accumulator-fraction, inklusive frames som kör flera catch-up-ticks. V1-gästen behåller tidigare prediktion, historik och visuella korrigeringar och matar den gemensamma kameran med sin renderposition. V2:s lokalrunner använder samma state-interpolering och physics-fraction. Rörliga barrels interpoleras visuellt i alla lägen; deras auktoritativa kollisionsdata ändras inte. Singleplayer-barrels slutar interpolera vid avslutad runda.

`RaceCoursePresentation` används i båda race-lägena. Dess hazard-fabrik används även av singleplayer för spikes/block/barrels. Singleplayers endlessgenerator och race-lägenas frysta manifest behåller sina olika scenarioregler. V1 förblir hostauktoritativt, V2 klientauktoritativt för egen runner.

V2-lobbyn städas också bort vid återgång till hubben, vilket förhindrar kvarvarande panel/signaler bakom nästa meny. Befintliga skillnader i loadout-clamps, exempelvis V2:s snävare cooldown-clamp, ändrades inte som en del av kamera-/transportarbetet.

## Verifiering

Godot-version: **4.7.2 stable**. Samtliga följande slutliga kontroller avslutades med exit 0:

| Kontroll | Resultat |
| --- | --- |
| `tools/unified_presentation_test.gd` | PASS: 30/60/75/120/144 Hz, 475/500/507,35/525 px/s, monotonic kamera och samma renderpose, blockering/restart, host catch-up, oförändrad authority/kollisionsrect |
| Samma tests V2-scenfixture | PASS: tre player views, två olika remote-y-positioner synliga, host dör → giltig spectator, samma kamera/slot-offset, remote finish fryser rätt position och väljer nästa gäst |
| `tools/multiplayer_v2/contract_test.gd` | PASS |
| `tools/multiplayer_simulation_test.gd` | PASS |
| `tools/race_course_presentation_test.gd` | PASS |
| `tools/course_manifest_test.gd`, `course_generator_test.gd` | PASS |
| `tools/equipment_model_test.gd`, `barrel_motion_test.gd` | PASS |
| `tools/multiplayer_lobby_contract_test.gd` | PASS; normaliserar CRLF vid läsning av källkodskontrakt |
| `tools/multiplayer_match_presentation_test.tscn` | PASS; fixture uppdaterad till den redan införda gemensamma presenter-komponenten |
| `tools/multiplayer_diagnostics_test.tscn`, `multiplayer_lobby_smoke_test.tscn` | PASS |
| Native WebRTC: `tools/unified_webrtc_rpc_test.gd` | PASS: tre peers, fyra anslutningar CONNECTED, 164 samples per remote-owner hos varje mottagare, 0 sändfel över cirka 5,5 s |
| Separat Web-export av `tools/unified_webrtc_rpc_test.tscn` i IAB/Chromium | PASS: samma trepeers-resultat, 164 samples per remote-owner och 0 sändfel |
| Web-export av releaseprojektet | PASS, exit 0, kompletta icke-tomma artefakter, inga parse-/scriptfel i exportloggen |
| Lokal runtime och Pages-shell | Meny med alla tre lägen, singleplayer-runda/resultat/återgång, V1- och V2-lobbyvyer kontrollerade; inga browser-runtimefel vid dessa kontroller |
| Direkt Godot-menyinputfixture | PASS med input i viewportens lokala koordinater; jämförelse av global-input-fixturen före/efter visade samma resultat och ingen ny skillnad |
| `git diff --check` | PASS |

Typiska körkommandon:

```powershell
& 'E:/Utveckling/Godot_v4.7.2-stable_win64_console.exe' --headless --path gravity-run --script tools/unified_presentation_test.gd
& 'E:/Utveckling/Godot_v4.7.2-stable_win64_console.exe' --headless --path gravity-run --script tools/unified_webrtc_rpc_test.gd
& 'E:/Utveckling/Godot_v4.7.2-stable_win64_console.exe' --headless --path gravity-run res://tools/multiplayer_match_presentation_test.tscn
```

Transportfixturen använder riktiga WebRTC-anslutningar, produktionens RPC-endpoint, sample-validation och remote-track. Den använder tre isolerade SceneMultiplayer-instanser i samma process/browserruntime och testar host→guest, guest→host och hostens relay till den andra gästen. Den är **inte** tre separata människor/webklienter genom hela Supabase-lobbyn. Scenfixturen testar den verkliga matchscenens rendering, men använder kontrollerade samples.

Fullständiga V1/V2-rundor med separata browserklienter, tre omspel, mobil hårdvara och en subjektiv bedömning av jämnheten på olika riktiga skärmar är **inte godkända som körda**. Ett privat V2-lobbyprov påbörjades. Arbetet avbröts av kontots usage limit; efter flera timmar visade den gamla klienten signaling-avslag. Färska klienter laddade den nya releasebuilden, men browserkontrollens klick/tangentinput kunde sedan inte driva canvasmenyn vidare. Därför finns inget påstått godkänt fullständigt lobby/start/resultat-prov. Menyinput verifierades separat i Godot och lokal webmeny hade redan fungerat före avbrottet.

Sandboxkörningar gav miljöfel om användarlogg/root-certifikat, utan att kontrakttesterna fallerade. Native nätverkstest och export kördes med godkänd åtkomst till faktisk runtime/templates. Den automatiska granskningens tillfälliga usage-limit-fel löstes efter användarens instruktion att fortsätta; publiceringskontrollen är inte längre blockerad av det.

## Publicering och artefakter

Gemensam adress: **https://hjelmdev.github.io/gravity-run/**.

Pages-shellens orientering, OAuth-callback, mobile text entry och iframe bevarades. Iframe laddar `docs/game-v2/index.html`, nu med alla tre lägen. Ikon-/manifestreferenser pekar på aktuell export. Gamla V2-entrypoints (`multiplayer-v2/` och dess `game/index.html`) redirectar till rooten och bevarar query/hash. Gamla artefakter ligger kvar för historik/rollback men laddas inte från dessa entrypoints.

Release-loadern använder `index.unified-bc6826f.pck` som `mainPack`, för att undvika en gammal cachad PCK. `index.pck` finns kvar som identisk kompatibilitetskopia. Shellens worker-retirement omfattar även tidigare V2-scopes. `DEPLOYMENT.md` beskriver det gemensamma exportflödet och den exakta integrationsomfattningen.

| Artefakt | Byte | SHA-256 |
| --- | ---: | --- |
| Versionerad PCK samt `index.pck` | 1111396 | `D765C5D7E50C44F96B7DD9B8CD063D2009F79BCF4771436A40D5729F4986C209` |
| `index.wasm` | 39514754 | `FC74679E3B97F76878947FCD4FBE1268CBFA6188182A2E33BBC3F5DC9BFA57D0` |
| `index.js` | 279815 | `33C94CB3175F3333B82E2A3BE5E8E86F77986F0AA2042B1631F6367A4E5BB6BA` |

GitHub Pages-jobbet [36643625034](https://github.com/hjelmdev/gravity-run/actions/runs/36643625034) är `completed/success` för exakt Pages-commit `4023e1407f9677a1237e366db860a4f631b9dbdd`. Live-loadern refererar till den versionerade PCK-filen. Filen hämtades från Pages: byteantal och SHA-256 matchade releaseexporten exakt. Rootbuilden startade visuellt i browsern utan runtimefel. Gamla V2-länken verifierades navigera till rootadressen.

Rapporten kan uppdateras i en efterföljande dokumentationscommit utan ny export; den publicerade spelimplementationen är den ovan angivna `bc6826f`.

## Kvarvarande granskning och återställning

Användaren kan nu testa single, V1 och V2 från samma rootadress. Prioriterat manuellt efterprov: två/tre separata klienter, host dör före gäster, olika gravity-flips, gemensamt resultat och tre omspel. Bedöm också banflödet med utrustningshastigheter och efter blockering. Nätverkskorrigeringar/FPS-störningar kan fortfarande påverka upplevelsen; interpolation är inte ett löfte om perfekt flyt under alla driftsförhållanden.

Vid releaseproblem kan granskade Pages-filer återställas från `7c5f248` med ett nytt commit. Källkodens ändringar är avgränsade till merge och presentations-/R5-commit och kan återställas via vanliga revert-commits. Databasen ska inte resetas för en webrollback. Båda migrationernas funktionalitet ska behållas.
