# Jagande spöke, istappar och rytmiska lavapölar

Användaren godkände alla tre förslagen 2026-10-06 och bad att Luna börjar direkt. Root samordnar befintlig Luna, hjälper vid konkreta blockerare och slutgranskar före ordinarie publicering. All gameplay och presentation ska vara gemensam för SP och MP; grafik ska kunna bytas separat.

## Baslinje och avgränsning

- Bekräfta HEAD före ändring. Aktuell release: Gen16, API `2.1.20261006.12`, manifest 9, godkänt gravitationsljud utan air-lagret (`0a7c016`, metadata `7e6062d`, report `d3f9a4b`). Publik build `flip-tone-0a7c016-20261006`.
- Bevara godkänt gravitationsljud, inspelat dödsljud, touchfix, grottans float-clipping-fix, diagnostik och myntens gemensamma presentation/belöningar. Orelaterade dirty hunks i main/meny/renderpacing/dokument får inte följa med i commits.
- Inventera befintliga GhostModel, fallande sten/såg, lava och gemensam CourseManifest/WorldSimulation/Presentation innan ny implementation. En scen/modell per nytt hot används av båda lägena, inga parallella SP/MP-beteenden.
- Detta uppdrag ger tre nya biomebundna möten; ingen campaign, generell prestandarefaktor, ekonomiförändring eller extra global täthetsökning. Begränsa antalet samtidiga objekt/effekter.
- Dokumentera fas, beslut, mätningar, blockerare och nästa steg i motsvarande STATUS. Vid kapacitetsfel lämna ett reproducerbart checkpoint åt root.

## 1. Kort jagande spöke i spökbiomen

- Separat tydlig variant av gemensamt spökmöte: kommer ikapp bakifrån under en kort, begränsad sträcka/tid. Spelaren kan byta till motsatt stödytas sida för att undvika det. Samma utbytbara spökskins är möjliga utan ändrad collision.
- Definiera spawn, begriplig aktivering, jakt, utfasning och despawn. Ingen dödlig spawn inuti spelaren och inget hot som följer valfri höjd utan möjlighet att undkomma. Behåll nåbar motsatt sida under hela kontaktfönstret.
- Rörelse, hitbox och faser ska härledas från gemensam simulationstakt och eventdata, inte kamera, render-FPS, lokal väggklocka eller vem som är host. Om ett mål krävs i MP ska urvalet vara kanoniskt och entydigt; enklare seedstyrd jaktbana är att föredra framför ett nytt nätverksprotokoll.
- Inkludera jaktens hela swept corridor i kandidatfilter, myntfilter och ruttkontroll. Vanliga spökets regler och äldre seeds förblir oförändrade.

## 2. Fallande istappar i isgrottan

- Takförankrad istapp, läsbar lossning/fallrörelse, därefter synligt tillfälligt golvhinder som försvinner efter deterministisk livstid. Kontaktdöden/hindertyp och exakta synliga kontaktytor ska vara dokumenterade; inget osynligt hinder före eller efter presentationen.
- Använd gemensam modell för stöd/fall där lämpligt. Istappen ska falla genom ett faktiskt hål i golvet och försvinna ur spelplanet, inte komma upp igen. På lutningar/block ska korrekt stöd väljas; tak-/golvgeometri och visual vinkel måste stämma.
- Ingen fallande spawn på runner eller obligatorisk istapp mellan omöjliga samtidiga tak-/golvhinder. Efter nedslag måste motsatt stöd vara nåbart och det tillfälliga hindret ingå i ruttsimuleringen.
- Samma fall, landning, livstid och terminalkontakt i SP/MP, retry/baseline/spectator. Infällt stöd/utbytbar grafik i en egen hazardscen; begränsad nedslagseffekt och återanvänd befintlig SFX-dedup där passande.

## 3. Rytmiskt växande lavapölar

- Biomebundet separat möte med synlig pöl som växer och drar sig tillbaka i en tydlig, deterministisk rytm. Bounded bredd/höjd, heta kontaktområdet följer exakt den aktuella visuella formen. Dekorativ glöd får inte utöka osynlig hitbox.
- Återanvänd gemensam lavafamilj/fasgrund, håll befintliga sprickor och vulkaners versionerade regler oförändrade. Poolen är ett varmt stödytområde, inte automatiskt ett golvhål.
- Ingen lodrät stråle genom hela spelkorridoren. Minst en verkligt nåbar säker passage vid de testade faserna/hastigheterna; kontrollera motsatt yta, flipcooldown och närliggande hot. Riskmynt förblir frivilliga och får inte ligga i ogenomförbara dynamiska kontaktfönster.
- Rendering, kollision, ljudfas/dedup och baseline återger samma kanoniska tillstånd. Inga nya lokala timer/RNG-beslut eller ackumulerande permanenta pölar.

## Versionering och bevis

- Nya gameplayregler förväntas behöva Gen17. Frys representativa Gen16 manifest-/event-/mynt-/biomehashar före ändring; kör även relevanta äldre frysstester. Äldre seedkoder får inte retroaktivt få nya hot eller nya rörelser.
- Audita versionerade defaults/allowlists/parser, generator, manifestvalidator, shared world, SP-spawn och MP presentation. Ändra API/manifestkontrakt endast när faktiskt nödvändigt, aldrig bara för grafik.
- Integrera nya hot via befintlig gemensam generator och säkerhetsgrind, inte extra spawns som kringgår filtren. Ge tidigt minst ett kort seed per möte.
- Testa faktisk gemensam runner-rörelse genom hela manifester vid 250/500/750 px/s och representativa aktiverings-/poolfaser, samt relevanta SP/MP cooldowns. Använd verklig simtid och framåtrörelse; inga frysta runner, gratis borttagna terminalhinder eller spikimmunitet som genväg. Reaktionsmarginal, stöd, biomegränser och hela rörliga corridor ska kontrolleras.
- Scenario-/scenbevis för SP/MP-paritet, late baseline/retry/spectator, render-FPS-oberoende och begränsat antal noder/effekter. Bevara samma myntledger/walletväg och idempotens; redovisa faktisk myntbudget innan/efter.
- Faktiska GPU-spelbilder i landscape/portrait för samtliga tre, inklusive istapp före/efter landning och lava i olika faser. Skilj offline scenfixture från riktig ansluten MP.
- Egna Godottester körs seriellt med timeout och egna PID/barncleanup. Bevara användarens editor/andras arbete. Kör relevanta tester, inte orelaterad bred upprepning.

## Review och ordinarie release

### Tillagt av användaren: enhetlig textinmatning (2026-10-06)

Användaren rapporterar att inklistring i troligen MP-seedfältet inte använder nickname-fältets egen inmatningskomponent/vy. Mobilens scroll/tangentbord gör då att det inte syns vad man skriver. Inventera verkliga redigerbara text-/nummerfält i SP/MP och menyer; återanvänd den befintliga nickname-lösningen för relevanta fält i stället för att bygga ännu en separat editvy. Dokumentera fält, scen, befintligt beteende och åtgärd i STATUS.

- Seedfält (både SP och MP), nickname och rumskod samt andra relevanta textfält ska få samma gemensamma tangentbords-/fokus-/editlivscykel. Fältspecifik etikett, validering, hemlig/lösenordstext och keyboardtyp behålls när tillämpligt. Sliders och andra icke-textkontroller omfattas inte av editvyn.
- Aktivt fält och bekräfta/avbryt ska vara åtkomliga när mobiltangentbordet visas. Verifiera långa/versionerade seedkoder, inklistring, tomt fält, ogiltig kod, byte mellan fält och korrekt returnerat fokus. Bevara äldre seedparsning, nuvarande skrivbordsflöde och nickname-inställningar.
- HUD-/edit-touches och Enter/Escape/release får inte trigga gameplay-flip eller oavsiktligt starta rundor. Stängning/avbryt återställer kontrollernas fokus/gesture.
- Testa verklig scenkoppling och gemensam komponent i portrait/landscape med simulerad tangentbordsinset där möjligt. Gör skillnaden mot faktiskt mobilt Safari/Chrome-test explicit; påstå inte deviceverifiering från nativefixtures.
- Denna användarstyrning ingår i nästa REVIEW_READY och samma granskade publicering, utan att stoppa rättningarna av biomefynden eller ändra backend/inloggningsregler.

- REVIEW_READY innehåller faktisk diff, kontrakt/rutttest och begränsningar, bilder, korta testseeds, versionsändringar och exakt nödvändiga migrations. Root granskar och Luna rättar konkreta fynd före livehandlingar.
- Efter ROOT_APPROVED: scoped Azure commit/push; granskade nödvändiga migrationer med linked history-verifiering; rent exakt-commit Webbygge; Pages root/game-publicering. Root verifierar workflow rätt head/success, båda BUILD_ID/loaders och oberoende nedladdad offentlig PCK-hash.
- Databasmigration begränsas till nödvändiga release-/versionsgrindar. Ingen walletdata/policy eller annan databasmigration ingår i uppdraget. Nekad livehandling återförsöks inte utan relevant faktisk användarauktorisation.
- Slutbesked ges först med verifierad releaseidentitet, länk och korta användartest för de tre mötena. Påstå inte allseed-spelbarhet eller mobilprestanda utifrån begränsade fixtures.
