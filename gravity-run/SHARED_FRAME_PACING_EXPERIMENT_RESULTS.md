# Shared frame pacing: första singleplayer-utredningen

Datum: 2026-10-01. Native-fixturens build-id: `2026.10.01-shared-frame-pacing-diagnostics`. Browserrapporten är från föregående Pages-build `2026.10.01-v2-diagnostics-export-fix`.

## Fynd

Ingen konkret rörelse- eller frame-pacing-orsak är verifierad. En reproducerbar native-körning med ordinarie renderinställningar visar jämna callback-intervall efter uppvärmning, monoton kamera och överensstämmelse mellan statiskt hinders beräknade och faktiska canvasposition. Den körningen bevisar inte att användarens upplevda fart–broms–fart är löst eller att andra skärmar och webbläsare beter sig likadant.

V2:s renderankare var inte aktiverat eller ändrat. Ingen ny FPS-gräns, frame-pacing-inställning, kamerautjämning eller spelregeländring infördes.

## Fixtur och reproducerbarhet

`tools/singleplayer_render_capture.gd` har ändrats från två korta körningar med olika FPS-tak och slumpmässiga banor till en körning med:

- seed `918273645`, generatorversion `4` och spelets inbyggda demo-AI som inputkälla;
- projektets normala renderinställningar, utan att ändra VSync eller FPS-tak;
- två sekunders uppvärmning följt av minst tio sammanhängande sekunder;
- begränsad framebuffert och en lokal JSON-fil i `.codex-v2-analysis/`.

Två separata körningar gav samma status, fart och gravitationsriktning på samtliga 600 fysiktick som fanns i båda mätfönstren. Render-callbackarnas exakta tidpunkter är däremot hårdvaruberoende och är inte fixturdata.

## Mätning

Den native-körningen använde Godot 4.7.2 på Windows, NVIDIA GeForce RTX 5070 Ti och OpenGL 3.3 Compatibility. Fönster och viewport var 960 × 540, zoom 1, VSync-läge aktiverat och `Engine.max_fps = 0`. Skärmens fysiska uppdateringsfrekvens mättes inte; callbackfrekvens ska inte tolkas som ett säkert mått på skärmfrekvens.

Efter de två uppvärmningssekunderna samlades 2 399 renderframes under 10,00 sekunder:

- `render_delta_ms`: median, p95 och p99 4,167 ms; max 4,545 ms; inga intervall över 8,3 ms. Rapporterad Godot-FPS låg mellan 239 och 240.
- Kameran hade inga bakåthopp. Spelaren använde 500 px/s och multiplikatorerna för spelare och utrustning var 1,0 under hela fönstret.
- Gravitationsväxlingar i båda riktningarna, en marklutning och en tunna förekom. Tunnan hade 373 mätposter; marklutningens golvprov hade 212.
- Statiska hinder hade 2 188 canvasprov. Skillnaden mellan förväntad och faktisk canvasposition var p95 0 px, max cirka 0,00025 px.
- Mätkodens egen insamling kostade p95 87 µs och max 158 µs. Bakgrunds- och banritningens CPU-kommandotid var p95 340 µs och max 673 µs. Detta är tid för CPU-insamling/ritkommandon, inte GPU- eller compositor-sluttid.

Speed-item kunde inte mätas. Den aktuella fixturen hade ingen aktiv speed-effekt, spelaren och utrustningen hade multiplikator 1,0, och den befintliga `activate_speed_boost`-metoden har inga anropare i projektet. En manuellt injicerad multiplikator skulle inte motsvara ett faktiskt itemflöde.

## Browser

På den publicerade root-adressen använde jag befintlig singleplayer-meny och pausmenyns diagnostik. Etiketterna i svenska browser-sessionen var **Diagnostik för bildflyt**, **Spela in bildflyt**, **Spara diagnostik**, **Fortsätt** och **Tillbaka**. Webexporten laddade ned `singleplayer_smoothness_1790859835.json` (216 594 byte).

Rapporten innehåller 372 frames över 1,547 sekunder, median/p95 4,167 ms, max 6,975 ms och angiven Godot-FPS 240. Den fångsten tog slut när spelaren kolliderade vid 265 m; den är för kort för att jämföra samma tiosekundersfixtur som native-körningen. Browsern var Codex In-app Browser i ett 1280 × 720-fönster med spelets 960 × 540-vy. Fysisk skärmuppdatering och browserns Performance/GPU/compositor-spår saknas.

Den visuella fart–broms–fart-upplevelsen har därför inte reproducerats eller avfärdats. Browserresultatet och native-resultatet använder inte samma automatiserade inputsekvens och kan inte jämföras som ett före/efter-test.

## Mätstödsändring

Singleplayerns opt-in-inspelning innehåller nu, utöver tidigare uppgifter:

- tidpunkten då spelarposen samplades, nästa callbackstart och kostnaden för själva diagnostikinsamlingen;
- spelarens föregående/aktuella/renderade position, gravitationsläge, fartmultiplikatorer och faktiskt tillämpad viewport-canvastransform;
- canvastransform och canvasposition för ett statiskt hinder samt tunna med dess interpolerade ritposition;
- ett golvprov genom spelarens position och, när en lutning skär provet, lutningsnodens identitet och transform;
- CPU-tid för bakgrundens och banans canvas-kommandon, tydligt åtskild från fysisk bildpresentation.

Den ordinarie spelvägen utför ingen extra frame-mätning när inspelningen är avstängd. Bufferten är fortsatt begränsad till 4 096 frames och exporten återanvänder den befintliga storleksbegränsade JSON-exportören.

## Kontroller och begränsningar

- Unified presentation-, race-course presentation-, multiplayer match presentation-, V2 course-flow trace-, V2 contract- och diagnostics-export-tester passerade.
- Native grafiskt test gav en sammanhängande tio sekunders fångst med synliga statiska/rörliga hinder och marklutning. En andra körning bekräftade samma fysikstatus på gemensamma tickar.
- Den nya Web-exporten byggdes och laddades i Codex In-app Browser från en lokal HTTP-server; huvudmenyn och en vanlig singleplayerrunda renderades. Den slumpade banan avslutade rundan innan pausmenyn kunde öppnas, så den nya diagnostikvägen och en lång browserfångst verifierades inte där. Den tidigare publicerade versionens befintliga diagnostik exporterade en faktisk fil med 1,547 sekunders data.
- Ingen Chrome Performance-inspelning, 60 Hz-maskin, annan skärm eller treseparata-identiteter-V2-körning var tillgänglig i denna utredning. Inga multiplayer-spelvägar ändrades.
- Exportens lockning testades inte med en stor browserrapport i denna utredning; det är en separat verifierad exportfix och inte bevis för bättre frame pacing.

Nästa kunskapslucka är faktisk visnings-/compositor-timing i browsermiljön där fart–broms–fart märks, särskilt vid en uppmätt annan renderfrekvens. Underlaget motiverar ännu inte en spelkodfix eller en FPS-/kamerainställning.
