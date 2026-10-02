# Kvarvarande start-, ljud- och stenfixar

Datum: 2026-10-02. Generatorversion: 7. Kompatibilitetsmigration: `202610020002_generator7_rock_readability.sql`.

## Ändringar

Multiplayerstarten behåller barriärerna för scenberedskap, kontobindning, klocksynk, PREPARED, fryst katalogregistrering och startcommit. Klockpolicyn skiljer nu RTT från offsetskattningens stabilitet: en hög men stabil RTT uppfyller inte automatiskt osäkerhetsvillkoret, medan skiftande offsetprover fortsätter blockera starten. Startförsöket loggar bounded per-peer scen-, konto-, klock-, PREPARED-, registrerings- och commitstatus, tillsammans med kö-/HTTP-tider, tidsförlopp, sista fel och build. Diagnostikexporten behåller upp till åtta startförsök efter timeout och lobbyretur. Ingen token, nonce eller credential ingår. Save diagnostics finns i lobby och match/paus.

Musikspelaren behåller Stream-läget eftersom tidigare Sample-försök gav ett webbljud-/bufferfel. Menystart försöker autoplay när spelaren skapas. Webbläsaren kan markera AudioStreamPlayer som spelande fast ljudkontexten inte går fram; en begränsad progresskontroll lämnar då autoplay i väntande läge och en riktig mus-, touch- eller tangentgest gör ett nytt försök. Retry är spärrat medan musik är OFF och begränsat i tid för att undvika att en följd av samma gest startar om låten flera gånger. OFF stoppar spelaren och hindrar meny, runda och finished-callback från att starta den igen. Volymvärdet delas mellan SP, MP och Options med fin lågvolymskurva.

Generator 7 ger stenarna 90 varningstick (1,5 s), 42 falltick (0,7 s) och 1 800 px aktiveringsmarginal. En offscreen-markör visar hotet medan den fysiska stenen faller och därefter lämnas den permanenta nedgrävda kollisionsformen kvar. Multiplayer fortsätter använda samma WORLD_COMMIT och simulatortick för båda klienterna. Generator 6 och äldre hash-/seedregler är bevarade; migrationen uppdaterar bara de nödvändiga versionsgrindarna.

## Verifiering

- Godot 4.7.2 headless passerade multiplayerkontrakt, klockpolicy, timeoutdiagnostikexport, treklients prepare/start-barriär med fördröjd gästs kontobindning, musikprofil och OFF-cykler, generator/challenge, stenmarkörens synlighet, V7-kalibrering, verklig SP-runtime för V7 och V6 samt MP-tickparitet. Förberedelseprovet använder tre verkliga lokala WebRTC serviceklienter och går igenom barriärer, registrering, nedräkning och commit. Auth- och backendleverantören är testdubbel; det testet bevisar inte livekonton.
- Timeouttestet driver den riktiga coordinator-timeouten, låter tjänsten återgå till lobby och exporterar JSON. Startförsöket finns kvar och lobbyn är fortsatt användbar efter export.
- 200 seeds `100000000–100000199`, 45 000 px vardera: 843 accepterade stenar (medel 4,215; minst en i 191/200 banor), mot 3 956 spike-grupper (medel 19,780). 242 stenar låg före 10 000 px och 400 före 20 000 px. Första sten i seed `100000000` ligger på cirka 2 000 px. Säkerhetsfiltrering gav accepterade möten; inga avvisade kandidater tvingades igenom.
- V7 SP-provet följde dormant → warning → falling → buried i `GR7-100000000`; separat V6-prov behöll första stenen vid 1 400 px. Två V7-simuleringar applicerade samma rock-activation commit och nådde identisk permanent geometri på tick 139.
- Varningstestet använde 960×540 vy, kameraförskjutning 250 px och 750 px/s. Stenen blir synlig efter 88 tick medan markören täcker hela varningen på 90 tick. Modellrutten passerade med 0,84 s kvarvarande cooldown och 200 ms reaktionstid. Detta är ett automatiserat geometri-/tidsprov, inte en mänsklig läsbarhetsbedömning.
- Nya migrationen kompilerades i lokal PostgreSQL i rollbacktransaktion. `db push --dry-run --linked` listade endast `202610020002`; migrationen applicerades därefter och Supabase linked history visar alla 37 lokala och fjärrmigrationer matchade genom `202610020002`.

## Publicering

Källkoden publicerades till Azure `codex/current-prototype` i releasecommit `0a1bdbb881fb068274b0e3870f6511dca990bd95`. Web-exporten byggdes från just den committen med Godot 4.7.2. GitHub Pages `main`-commit är `e07ba28980c1c5f13efb6dd95ca307a5490055f4`; dess Pages-workflow avslutades med success ([workflow](https://github.com/hjelmdev/gravity-run/actions/runs/37005206584)). Aktivt build-ID är `start-audio-rock-fix-0a1bdbb-20261002`; loadern väljer `index.start-audio-rock-fix-0a1bdbb.pck` (2 696 156 byte, SHA-256 `111D3DA567BBC6404C4EBF0EF83E1570B531D869F99BAEAEC0A865341EE80C88`). Root, loader, JS, WASM och PCK svarade HTTP 200. Den publikt hämtade PCK:n matchade exporten byte för byte. Gammal `game-v2`-/`multiplayer-v2`-redirectstruktur lämnades kvar.

Ingen separat interaktiv webbläsare fanns tillgänglig för denna agentkörning. HTTP- och Actions-kontroller verifierar publicerade filer och Pages-bygget, inte att UI:t kör, ljudet hörs eller att autoplaybeteendet fungerar i en verklig browser.

## Kvarvarande verifieringsgränser

Det rapporterade timeoutfelet är fortfarande **inte bekräftat löst i en riktig inloggad browsermatch**. Klocktestet tar bort den verifierade robusthetsrisken för stabil RTT över 33 ms och diagnosfilen kan nu visa exakt vilken spärr som återstår, men vi saknar ett host-/gästexporterat timeoutspår från användarens browser eller en live 2–3-kontomatch mot GoTrue/PostgREST. Därför går det inte att hävda att den rapporterade orsaken hittats.

Autoplay, browserns faktiska AudioContext-upplåsning, ljudets hörbarhet och längre loop-/övergångsprov har inte körts i en browser i denna arbetsomgång. Progresskontrollen skiljer spelarförfrågan från en framåtskridande streamposition, men ska valideras i webbläsare med både tillåten och blockerad autoplay. Den befintliga Stream-lösningen behålls i avvaktan på sådan provlyssning; ingen hosting- eller trådpolicy har ändrats. Timeouttestet verifierar lokal JSON-skrivning/återläsning och att samma lobby står kvar, inte browserns faktiska Save diagnostics-klick/nedladdning efter ett live-timeout.

Frekvensen är tydligt högre än tidigare, men rapporterar inte att varje bana når 2–4 stenar. Fördelningsmålet följs upp med den redovisade 200-seedmätningen. Varningstestens marker- och reaktionstid är simulerad; stående mobilvy, faktisk spelarreaktion och subjektiv stenläsbarhet behöver provas manuellt.

## Kort användarprov

1. Öppna den publicerade Pages-rooten, ställ musiken på 5 %, gå mellan meny, Options och inventory, och slå OFF/ON. Kontrollera att OFF består och att övergångar inte höjer nivån. Prova även första sidgesten i en browser som blockerar autoplay.
2. Kör ett normalt två- eller trekontorsrum genom prepare, konto-/beredskapsbarriär, countdown, lopp, resultat och omspel. Om det timear ut, välj Save diagnostics direkt i lobby och skicka exporten; den innehåller senaste startförsöket utan hemliga autentiseringsvärden.
3. Starta challenge `GR7-100000000` (seed `100000000`) och följ stenen runt 2 000 px: markör/varning, fall och permanent nedgrävning.
