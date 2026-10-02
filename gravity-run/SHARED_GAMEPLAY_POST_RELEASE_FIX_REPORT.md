# Shared gameplay post-release fix report

Datum: 2026-10-02. Källrelease: `9be5402` (`codex/current-prototype`). Supabase migration: `202610020001_generator6_gameplay_release.sql`. Pages-release: `850d9e6` (`main`).

## Åtgärder

- Multiplayer prepare/start gick via kontolänkning, gästernas PREPARED och hostens frysta katalogregistrering innan commit/countdown. Den här koden lade till fältvalidering på backend-ACK, start-RPC-diagnostik med kö-/HTTP-tid, startanropens prioritet framför bakgrundssettlement, begränsad retry för tillfälliga bindningsfel och idempotent återanvändning av runtime-round-ID efter tappat registreringssvar. Inloggade spelare avbryter starten vid bindningsfel; de fortsätter inte obundet. V6-gaten sätts samtidigt för nya multiplayer-rum och coin-round-RPC.
- Musikens standard och fallback är 25 %. Reglagevärdet använder `0.35 × u²`, 0 är mute och Music-bussen är fortsatt enda användarvolymkontroll. Meny och lopp använder samma målvolym; uppspelningsgain sätts före start och kontextfade börjar från faktisk gain. Autoplay provas när musikresursen är redo. Vid browserblockering görs ett nytt försök först vid riktig mus/touch/tangent-input från användaren; det finns ingen syntetisk gest.
- Nya kurser använder generator 6, med klart vanligare accepterade stenar. Generator 5 och äldre banbeteende behålls för kompatibilitet. Stenens runtimekedja testas genom normal singleplayer-scene.

## Verifiering

- Godot 4.7.2: `course_generator_test.gd`, `challenge_service_test.gd`, `music_controller_test.gd`, `multiplayer_v2/contract_test.gd`, `shared_rock_v6_calibration_test.gd`, `singleplayer_rock_v6_runtime_test.gd` och `multiplayer_v2/prepare_start_integration_test.gd` passerade. Headless Godot gav en Windows root-certificate-store-varning men testerna avslutades med PASS.
- Prepare-testet kör tre riktiga lokala WebRTC-serviceklienter och faktisk coordinator-barriär; det fördröjer en gästs kontobindning och går igenom catalog-registrering, countdown och RUNNING utan att manuellt sätta RUNNING. RPC/auth-provider är styrd testdouble, inklusive idempotent lost-response-scenario. Det är inte ett inloggat GoTrue/PostgREST-webbläsarmöte eller ett live wallet-award-test.
- Gen6-kalibrering: 200 deterministiska seeds `100000000–100000199`, vardera 45 000 px: 546 accepterade stenar (medel 2,73), minst en sten i 181/200 banor, 4 372 spike-grupper (medel 21,86). 159 stenar före 10 000 px och 274 före 20 000 px. Stenarna är därmed vanliga men mycket färre än spike-grupper. Äldsta generationers frysta fixturetest och separat v5-profiltest har tidigare passerat; generation 5 behåller sin gamla lägre stenfrekvens.
- Riktig SP-scen på challenge `GR6-100000000` väljer seed 100000000 och instansierar första accepterade sten-eventet vid kursposition cirka 1 400 px. Testet följde dormant → warning → falling → buried. Detta är ett automatiserat lokalt scenprov, inte en provspelning med mänsklig input.
- Den nya migrationen kördes först lokalt mot PostgreSQL och gate för version 6 verifierades. Supabase CLI linked history visade endast `202610020001` pending; dry-run listade endast denna migration. Den applicerades därefter med `db push --linked` och linked history verifierade alla 37 migrationer matchade till och med `202610020001`. Detta verifierar migration/applicering, inte full produktionstransaktion med riktig inloggad användare.
- Web-exporten byggdes från ett isolerat arkiv av exakt source commit `9be5402`. Export-PCK är 2 667 612 byte, SHA-256 `DB439B03C314FA00F50C894235098F92E205B6284BFA1248817F1997F91E7159`. Den nya Pages-loadern anger en versionsunik `mainPack`; root-wrapper och paketerad Web-kod publiceras som aktiv `docs/game/` bundle. Publicerad root URL: [https://hjelmdev.github.io/gravity-run/](https://hjelmdev.github.io/gravity-run/).

## Kvarvarande verifieringsgränser

GitHub Pages workflow avslutades med `success` ([workflow](https://github.com/hjelmdev/gravity-run/actions/runs/36997311213)). Efter deployment gav root och game-loader HTTP 200; wrappern visar `shared-gameplay-fix1-9be5402-20261002` och loadern refererar till `index.shared-gameplay-fix1-9be5402-20261002.pck`. Den publikt nedladdade PCK matchade den lokala exporten byte för byte: 2 667 612 byte, SHA-256 `DB439B03C314FA00F50C894235098F92E205B6284BFA1248817F1997F91E7159`.

Inget separat browserfönster eller ljudutrustning var tillgängligt i denna körning. Autoplay tillåtet/blockerat, ljudets faktiska hörbarhet vid 5 %, och subjektiv nivåjämförelse måste därför provas av användaren. Browserns policy kan blockera autoplay tills en riktig gest.

Ingen riktig två-/trekontomatch via live GoTrue/PostgREST, live myntupphämtning/settlement eller live återspel genomfördes. Testet av prepare omfattar riktiga lokala WebRTC-kanaler och den faktiska service-/coordinator-koden, men kontot och RPC-svaren är testdouble. Tätare typisk hinderplacering är verifierad; det tidigare kända långa svansgapet från densitymätningen har inte optimerats i denna uppgift.

## Användarprov

1. Öppna root-länken, sätt musiken till 5 %, växla mellan meny/Options/inventory och starta/avsluta en runda. Kontrollera att menyskiften inte höjer nivån. Ladda om utan interaktion och kontrollera autoplay; om policyn blockerar ska en första mus-/touch-/tangentgest på startsidan starta musiken.
2. Med två eller tre konton, skapa ett nytt v6-rum och starta via normala menyval. Bekräfta kontobindning, allas förberedelse, hostregistrering, synkroniserad 3–2–1, plocka samma mynt med två spelare och kör rematch. Verifiera att endast vinnaren får det och att det sparas en gång.
3. I challenge-väljaren ange `GR6-100000000` (seed `100000000`). Den första accepterade v6-stenen ligger cirka `1 400 px` in i kursen. Följ varning, fall och nedgrävning i ett vanligt SP-lopp; stenen ska ligga kvar efter att den har landat.
