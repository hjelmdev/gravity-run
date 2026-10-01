# Ett multiplayerläge: pensionera V1 och gör dagens V2 till Multiplayer

Datum: 2026-10-01. Status: införandeklar plan. Detta dokument beskriver implementation; ingen spelkod eller publicering ändras genom att planen skrivs.

## Beslut och slutläge

Användaren vill bygga vidare på dagens V2 och pensionera V1. Spelet ska ha ett enda publikt multiplayerläge, benämnt **Multiplayer**, utan V1/V2/test-benämningar i spelargränssnittet. Ta bort användarens 30/60 Hz-val. Behåll loggsparning för analys av framtida hinder, biomes och andra spelelement.

Detta är produktstädning, routing och kontrollerad kodstädning. Ändra inte nätverksarkitektur, rörelsemodell, spelregler eller backendkontrakt som del av namnbytet. Den upplevda smoothness-frågan är dokumenterad som olöst och ska inte öppnas igen i detta uppdrag. Renderankaret ska fortsatt vara opt-in.

Slutläge:

- En Multiplayer-knapp som alltid startar den nuvarande V2-implementationen.
- Lobby, rumlista, match, resultat, feltexter och diagnostikknappar utan publika V2-benämningar, på svenska och engelska.
- Ordinarie positionskanal använder 30 Hz. Ingen 30/60-meny och ingen FPS-inställning tillkommer.
- Grunddiagnostik går att spara i lobby och match, även efter rundslut. Detaljprofilering är fortsatt opt-in.
- Root-adressen på Pages startar det aktiva spelet; gamla speladresser får inte lämna en fungerande V1-version tillgänglig som normalt alternativ.
- V1 bevaras i Git-historiken. Kod som kan behöva jämföras under införandet kan ligga kvar tillfälligt utan publikt eller aktivt runtimeflöde.

## 1. Gör en beroendeinventering före namnbyte och borttagning

Aktuella utgångspunkter:

| Område | Nuvarande filer/beroenden | Åtgärd |
|---|---|---|
| Hub | `ui/game_hub.gd`, två signaler/knappar | Behåll en neutral Multiplayer-signal/knapp |
| Menyrouting | `ui/main_menu.gd`, preloads för V1 och V2 | Neutral väg ska instansiera dagens V2-lobby/match |
| Lobbyretur | `systems/app_navigation.gd`, dubbla returintentioner | Samla till en neutral returväg som går till aktiv implementation |
| Aktiv lobby/match | `ui/multiplayer_v2/` | Rensa spelartexter och Hz-kontroll, behåll funktion |
| Services | `MultiplayerService` och `MultiplayerV2Service` i `project.godot` | Inventera referenser och aktiv nätverkspollning före pensionering/omdöpning |
| Positionskanal | `systems/multiplayer_v2/multiplayer_v2_service.gd` | Behåll standard `POSITION_RATE_HZ = 30`, ta bort publikt runtimeval |
| Diagnostik | `v2_diagnostics.gd`, `v2_diagnostics_export.gd`, singleplayerexport | Behåll gemensamma konsumenter och exportfrysfix |
| Lokalisering | `locale/sv.po` samt runtime-texter | Uppdatera aktiv text på båda språken |
| Pages | Root-wrapper samt `docs/game/` och `docs/game-v2/` | En aktiv bundle, kompatibla gamla adresser |
| Backend | V1/V2-RPC, migrationshistorik, signaling och protokollvärden | Behåll externa identifierare och data i detta uppdrag |

Sök med `rg` efter gamla scen-/scriptpaths, autoloadnamn, `class_name`, V1-signaler, navigation, testreferenser och export-/wrapperreferenser. Redovisa vilka filer som är V1-exklusiva och vilka som även används av singleplayer eller aktiv multiplayer. Ta inte bort en klass, migration, kursrenderer, exportör, runner-motion-hjälpare eller WebRTC-plugin bara för att den först infördes under V1.

## 2. Byt den publika ingången och stäng V1-flödet

Inför först med nuvarande V2-paths/autoloadnamn för att hålla routingändringen enkel att granska:

1. Ta bort `Multiplayer V2 (test)`-knappen i hubben. Den kvarvarande `Multiplayer`-knappen öppnar nuvarande V2-lobby.
2. Den neutrala startsignalen i hubben kopplas i `main_menu.gd` till aktiv lobby/match. Ta bort den tidigare publika V1-lobby-/matchstarten och kontrollera keyboard/controller-focus efter att en knapp försvinner.
3. Neutral lobbyretur i AppNavigation ska alltid öppna aktiv lobby. Uppdatera matchens retur-, avbrotts-, utträdes- och medlemsborttagningsvägar. Tillfällig intern aliasmetod får användas under refaktorering, men får inte kunna öppna V1 och ska få dokumenterad livslängd.
4. V1-autoloaden får inte fortsätta skapa rum, signalera, polla eller koppla upp i bakgrunden. Om den måste finnas kortvarigt för referenser: gör den inaktiv och verifiera detta. Ta bort autoloaden när alla aktiva konsumenter är lösta; ta inte bort en service som en gemensam funktion fortfarande anropar.
5. Inget publikt fallbackval ska öppna V1 om aktiv multiplayer får fel. Använd befintlig återhämtning/felhantering för aktiv implementation.

Verifiera denna fas före större interna filnamnsbyten. Routing och namnstädning ska inte samtidigt ändra client-authority, startbarriär, readiness, lobbyreturpolicy, kollisionsregler eller resultatrangordning.

## 3. Rensa spelartexter och synliga versionsetiketter

Granska hub, lobby/rumlista, anslutning, countdown, matchmeny, resultat, avbrott, felmeddelanden, sparbekräftelse, browser-titel och wrappertexter.

Exempel på aktuella texter att ersätta:

- `Multiplayer V2 (test)` → den enda `Multiplayer`-ingången.
- `Download V2 diagnostics` / `Save V2 diagnostics` → `Save diagnostics`, svenska `Spara diagnostik`.
- `V2 build %s` → `Build %s`, lämpligen endast i diagnostikdelen.
- `V2 round aborted`, V2-course/manifest-fel och eventuell `Preparing all V2 players…` → neutrala, översättningsbara texter.
- Gamla resultat-/retur-/leave-texter med V2-prefix → neutrala motsvarigheter.

Sök efter både `V2`, `v2` och gamla engelska/svenska translation keys. Radera inte historiska dokument, testnamn, protokollvärden eller build-id med blind sök/ersätt. Versionsnummer i tekniska rapporter är inte samma sak som V2 som produktnamn.

Använd namn på spelarna där det redan finns, inklusive åskådartext och prispall. Behåll meny/HUD som inte skymmer banan; introducera inga nya utvecklarfält i själva spelvyn.

## 4. Ta bort 30/60 Hz-valet och behåll 30 Hz

Matchens menykonstruktion innehåller i dag en OptionButton med `30 Hz` och `60 Hz`, kopplad till `set_snapshot_rate`. Ta bort kontrollen, etiketten och callbacken. Inaktivering betyder här att vanliga spelare inte kan ändra inställningen; visa inte en grå experimentkontroll.

Krav:

- Behåll positionskanalens befintliga 30 Hz-standard. Detta har inte valts som en ny smoothness-fix utan är produktens nuvarande standard.
- Säkerställ 30 Hz vid ny aktivering av session/transport och dokumentera om omspel återanvänder sessionen. Ett tidigare experimentval får inte leva vidare till nya ordinarie sessioner.
- Ange effektiv `position_rate_hz: 30` i diagnostikens session/timing metadata redan från början; export får inte kräva att användaren först ändrar ett menyval för att frekvensen ska bli synlig.
- Behåll en eventuell intern testfunktion endast där den behövs av utvecklartester. Ingen ny dold användarparameter för 60 Hz ska införas som ersättning för den borttagna menyn.
- Inventera kvarvarande anrop till `set_snapshot_rate` och eventuella sparade inställningar. Kontrollera att ordinarie körning inte kan återaktivera 60 Hz från sådan state.
- Ändra inte 60 Hz-simulationstick, skärmfrekvens/FPS eller renderinterpolation. Positionssändning och rendering är olika saker.

Verifiera verklig sändperiod via transportens mätning över ett tillräckligt fönster med tolerans för schemaläggning. En konstant i koden räcker inte som enda kontroll. Undvik sköra testkrav på exakt 30 paket under varje väggklocksekund.

## 5. Behåll användbar diagnostik utan experimentmenyer

Behåll `Spara diagnostik` i lobby och matchens meny, samt tillgänglig efter resultat. Behåll singleplayers befintliga `Diagnostik för bildflyt`-väg. Byt inte bort eller radera loggning bara för att V2 tas bort som publikt namn.

Två nivåer ska vara tydliga:

- Grunddiagnostik: session, build, implementation/protokollversion, seed/generator, roster/skins, effektiva positionsfrekvensen, anslutnings-/rundhändelser, terminalorsaker och befintliga begränsade översiktsmätningar. Sparbar utan att detaljprofilering först slås på.
- Detaljprofilering: befintlig opt-in för framtida analys av nya hinder/biomes, med begränsade buffertar och den etablerade exportvägen. Lägg ingen tung ständig per-frameprofilering som följd av produktstädningen.

Bevara kompakt JSON, bounded export, direkt buffer-download och skydd mot dubbel export i `0a53781`. Behåll explicit information när data har klippts. Lägg inte till upprepade fullrapportserialiseringar, base64-kodsträngar eller obundet växande profileringsdata.

Filer kan få neutral prefix, exempelvis `multiplayer_match_…` och `multiplayer_lobby_…`. Behåll schemafält/versionsmarkörer så äldre `multiplayer_v2_…`-loggar fortfarande går att analysera; filprefix får inte vara enda sättet att veta implementationen. Ingen radering av gamla insamlade rapporter eller analysdokument.

När framtida spelelement införs ska seed, generator/build och befintliga händelse-/entitets-id göra rapporterna spårbara. Uppdraget ska inte införa nya produktfunktioner eller hela biome-diagnostikscheman nu.

## 6. Interna namn och V1-kodstädning som separat verifierbar fas

Efter fungerande routing/produkttexter kan rena implementationstermer förenklas. Gör en dokumenterad namn-/pathmappning före ändringen:

- Aktiv lobby/match och signaler kan få neutrala namn; eventuella namn som tidigare ägdes av V1 frigörs först.
- När V1-service inte längre har runtimekonsumenter kan aktiv `MultiplayerV2Service` bli `MultiplayerService`. Två autoloads eller klasser får inte konkurrera om samma namn.
- Uppdatera `.tscn`-resurser, `.gd`-preloads, `.uid`-kopplingar, autoloadpaths, tester och exporter tillsammans. Låt Godots import verifiera paths och UID; skriv inte godtyckliga nya UID för att kringgå konflikter.
- V1-exklusiva runtimefiler och tester kan tas bort efter referensinventering. Flytta eventuell tillfällig referenskod ur aktiva/exporterade vägar och dokumentera den, eller förlita er på Git-historiken. Ingen levande andra multiplayerstack behöver behållas för framtiden.
- Behåll gemensam kamera, banpresentation, motion, backend/auth och exporthjälpare när de har andra konsumenter.

Externa kontrakt får behålla sina tekniska V2-namn i detta uppdrag: `network_mode = "v2"`, protokollfält, backendtabeller/RPC, signaling-identiteter, publicerade migrationer och befintliga opt-in-parametrar. De ska uttryckligen listas som kompatibilitetsundantag i införanderapporten. Ändra inte till `"multiplayer"` i ett paket eller RPC bara för att UI heter Multiplayer.

Ingen databasradering, omskrivning av historiska migrationer eller live-backendmigration krävs för denna pensionering. Om inventeringen visar ett verkligt kontraktsbehov: dokumentera ett separat migreringsarbete i stället för att blanda in det i namnbytet.

## 7. Pages och gamla adresser

I tidigare publicering finns en äldre bundle under `docs/game/` och aktiv utvecklad implementation under `docs/game-v2/`; root-wrappern styr till aktiv build. Verifiera faktiskt aktuellt publiceringsrepo och scripts före ändring, inte bara den lokala projektkatalogen.

Mål: root-adressen fortsätter fungera och leder till samma aktiva spel som direkta adresser. En enda aktiv spelbundle, utan att gamla direktlänkar tyst öppnar V1.

Föreslagen slutstruktur:

1. Publicera aktuellt aktiva spelet som neutral bundle under `docs/game/` och låt root-wrappern använda den.
2. Behåll `docs/game-v2/index.html` som kompatibilitetsredirect till den neutrala speladressen. Vid behov behåll samma wrapperkontrakt; forwarda avsedda queryparametrar och fragment korrekt.
3. Ta bort referenser till den gamla V1-packfilen och dess aktiva entrypoint från den publicerade vägen. Efter verifiering kan föråldrade exportartefakter rensas inom exakt kontrollerad publiceringskatalog.
4. Bevara singleplayer, konto, butik och övriga lägen från aktuell kodbas när neutral bundle byggs. Produktpensioneringen får inte återpublicera en gammal singleplayer-version eller skapa två divergenta spelbyggen.
5. Kontrollera PWA/service-worker/cachebeteende om det finns. Build-id och packfilreferenser ska höra ihop; en gammal cache får inte göra att vanliga Multiplayer fortfarande startar V1. Redirect får inte skapa iframe-loop eller ändra mobilens viewport/rotation.

Byte av path innebär att relativepaths i exporterad HTML/JS och wrapper måste verifieras. Om publiceringsverktygen kräver att aktiv bundle tills vidare ligger i `game-v2/`: neutralisera publikt namn och blockera/redirecta den äldre V1-entrypointen nu, dokumentera fysisk paths flytt som kvarvarande teknisk städning. Presentera inte ett historiskt fil-/URL-segment som ett andra användarläge.

## 8. Verifiering och ordning

Gör minst två separata verifierbara ändringsgrupper: först produkt/routing/Hz/diagnostik, därefter interna namn/V1-borttagning/publiceringspaths där dessa behövs. Refaktorering ska kunna granskas separat från beteendeförändringen.

Automatiska kontroller:

- Hub har en Multiplayer-ingång och neutral start-/lobbyretur leder till aktiva scener.
- Lokalisering och synliga active UI-strängar saknar V2/test-etiketter.
- Ingen 30/60-kontroll instansieras. Nya sessioner och omspel har effektiv 30 Hz och exporten registrerar den.
- Relevanta unified-/race-course-/match-presentation-/V2-contract-/diagnostics-export-/localization-tester passerar. Uppdatera bara testnamn/paths som faktiskt ändrats; gamla backendkontraktsvärden är fortfarande giltiga.
- Projektimport/build saknar brutna preloads, saknade autoloads, UID-konflikter eller dubbla serviceklassnamn.

Manuell browserverifiering med separata identiteter:

1. Root → Multiplayer → skapa rum, rumlista/join, namn/skins, ready och start.
2. Match/countdown, resultat/prispall, åskådartext, individuell lobbyretur enligt befintlig policy, nytt lopp samt utträde ur rum.
3. Ingen V1-menyväg, ingen synlig V2-etikett och inget Hz-val. Ingen bakgrundsanslutning från V1-service.
4. Spara grunddiagnostik i lobby/resultat; spara stor profilerad rapport i browser och kontrollera fortsatt lobby-/matchfunktion efter export. En liten fil räcker inte som storrapporttest.
5. Singleplayer/pause/resultatexport och konto-/profil-/inventoryflöde fungerar efter service-/pathstädningen.
6. Root, neutral direktadress och gammal V2-direktadress laddar rätt build utan V1 eller redirectloop. Kontrollera desktop och mobilvy där möjligheten finns.

Om faktisk multiplayer/browserutrustning saknas: rapportera exakt vad som inte verifierats. Byggsuccess och en laddad huvudmeny ersätter inte en start-/omspelskontroll. Kräv ingen ny lång smoothness-loggserie från användaren.

## 9. Leverans, återställning och kort användartest

Följ projektets vanliga källkods-/Pages-väg inom agentens publiceringsuppdrag. Redovisa sourcecommit, Pages-commit och build-id. Git-historiken ger återställning; ta inte bort backenddata för att pensionera UI.

Införanderapporten ska ange:

- Vilket läge är aktivt och vilka tidigare V1-ingångar/autoloads/artefakter har inaktiverats eller tagits bort?
- Vilka interna namn har förenklats och vilka externa V2-identifierare behålls med avsikt?
- Var finns Spara diagnostik och hur aktiveras detaljprofilering vid ett framtida konkret analysbehov?
- Vilken frekvens används och verifierades den faktiskt?
- Hur fungerar root och gamla direktlänkar, samt vilka kontroller kördes/återstår?

Efter verifiering räcker ett kort användartest: öppna vanliga adressen, kontrollera att bara Multiplayer finns, spela en runda med gäster, gå tillbaka och prova omspel. En grundexport kan sparas för att kontrollera build/frekvens; ingen 30/60-jämförelse, renderankarsjämförelse eller insamling av tolv filer krävs.

Godkänt slutläge är ett enda tydligt multiplayererbjudande, oförändrade spel-/nätverksregler och fortsatt användbar loggsparning för kommande innehåll.
