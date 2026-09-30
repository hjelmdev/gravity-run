# V2: gemensamt banflöde och åskådartext — implementation

Datum: 2026-09-30.

## Genomfört

- Åskådarstatusen använder namnet från rundans frysta roster: `Watching %s`, med svensk översättning `Följer %s`. Tomma eller saknade namn visas som `Player`/`Spelare`. Peer-id används fortsatt bara internt.
- Kursens presenterade noder får stabil metadata för id, typ, rörlighet och hinderroll. Samma urvalskontrakt används för stillastående hinder och rörliga entiteter och går att utöka för nya hinder.
- Profilflaggan `v2_profile=1` aktiverar upp till fem banflödesfönster à högst 512 bilder per runda. Det första fönstret börjar vid rundstart; senare fönster väntar på synliga hinder. Ett sent fönster reserveras för en rörlig entitet om en sådan finns.
- Varje bildruta innehåller monoton Godot-tid, frame-index, delta, simulation-/presentationstick, renderfraktioner, fas och lokal spelarstatus. Kameramålet och den faktiska kameran/viewport-canvastransformen exporteras tillsammans med statiska och rörliga noders världs- och canvasposition.
- Tunneprover innehåller även föregående, aktuell och visad simuleringstillstånd samt spawn-/fall-/förstörd-status. Webbläsarens rAF-tidsstämplar exporteras med frame-index och mappas till Godots monotona klocka via en tidsbracket vid fönsterexport. Inget JSON eller JavaScriptBridge-anrop körs per bildruta.
- Profilering av startövergången loggar callbacken, första världssteg, första figurpresentation och första faktiska terrängritning. Varje steg har tid relativt startdeadlinen; uppmätt arbete har även varaktighet.
- Kostnaden för det nya spåret summeras i `phase_profile.common_course_flow_trace`.

## Exportformat

I V2-diagnostikens `events` finns:

- `common_course_flow_trace`: en händelse per fönster. `frames` innehåller samtidiga kamera-, nod- och spelartillstånd. `browser_raf.samples` innehåller rAF-index, webbläsartid och uppskattad Godot-monoton tid. Fönstret anger sample-antal, tappade browserprov, canvasmått, skalfaktor och avslutsorsak.
- `start_stage_profile`: en händelse per första startfas, med `relative_to_deadline_usec` och tillgänglig `duration_usec`.
- `render_cadence_window`: sekundsummering med kostnadsfasen för banflödesspåret.

## Kontroller

- Godot 4.7.2 headless: `course_flow_trace_test.tscn` — godkänd.
- Godot 4.7.2 headless: `tools/multiplayer_v2/contract_test.gd` — godkänd.
- Godot 4.7.2 headless: `race_course_presentation_test.gd` — godkänd, inklusive stabil hinderidentitet och metadata för stillastående/rörliga kursnoder.
- Godot 4.7.2 headless: `multiplayer_match_presentation_test.tscn` — godkänd.
- Godot 4.7.2 headless: `localization_test.gd` — godkänd.
- `git diff --check` — godkänd.

Godot rapporterade i denna låsta körmiljö att den inte kunde skriva `user://logs/godot.log`, samt en varning om Windows root-certifikatlagret. Testprocesserna avslutades ändå med exit code 0 och respektive test rapporterade godkänt.

## Återstår att mäta i webbläsare

Profileringskoden är implementerad, men detta är inte belägg för att det upplevda fart–stopp–fart-problemet är löst. På den publicerade versionen: kör värd och två gäster i två rundor på 30 Hz med `v2_profile=1`, spara allas exporter och jämför samma statiska hinder och tunna genom `common_course_flow_trace`. Kontrollera därutöver en senare rörlig entitet; använd en skärminspelning endast som kompletterande belägg.
