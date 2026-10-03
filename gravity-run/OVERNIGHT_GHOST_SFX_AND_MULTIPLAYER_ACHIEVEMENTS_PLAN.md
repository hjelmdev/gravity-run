# Spökhinder, utbytbara ljudeffekter och multiplayer-achievements

Datum: 2026-10-03. Beställare har godkänt samtliga tre delar. Luna implementerar; root hjälper vid blockerare och gör slutgranskning före publicering. Ingen lyssningskontroll från beställaren krävs för första leveransen.

## Gemensamma ramar

- Samma gameplaymodell, scener, presentation och inställningar används i singleplayer och multiplayer. Nätverket förmedlar tillstånd/händelser; det ska inte innehålla en andra version av spökets beteende, ljud eller effekter.
- Grafik och ljud ska kunna bytas via resurser/filer utan ändring i collision, generation, nätprotokoll eller achievements. Kosmetisk slump får aldrig påverka banans deterministiska slumpgenerator.
- Baslinjen är publicerad generator 10, manifest 5, API-version 2.1.20261003.6, källkod 848fcac med efterföljande rapportcommit def2663. Kontrollera dessa värden före ändring. Historiska generatorer och deras banhashar/beteenden ska behållas.
- Nytt spökhinder införs under en ny generatorversion, normalt 11. Versionsgrind, klient och migration ska överensstämma. Höj manifestformat endast om formatet ändras; dokumentera beslutet. Använd ett ledigt migrationsnummer, aldrig ändra redan applicerade migrationer.
- Behåll färdiga förbättringar för myntprediktion, half embedded såg, biomer, musik, HUD och lobby. Ingen ny nätverkstopologi, FPS-inställning eller diagnostikinsamling per frame behövs.
- Arbetskatalogen innehåller andra pågående ändringar. Inventera diffen innan implementation och stagea endast egna hunks/filer. Särskilt main.gd och ui/main_menu.gd har redan orelaterade ändringar. Exportera slutligen från ett rent arkiv av den exakta källcommitten.

## Del 1: Ett faktiskt spökhinder i spökbiomen

### Spelbeteende

Första varianten är ett förutsägbart spöke som materialiseras på en i förväg bestämd sida, golv eller tak. Det jagar inte spelaren och byter inte mål efter spelarens gravitationsbyte. Ett tydligt byte till motsatta sidan ska räcka för att undvika det.

1. Generatorn väljer position, sida och stabilt entity-id deterministiskt. Spöket förekommer bara i haunted-biomen och får inte ersätta dess dekorativa bakgrundsfigurer.
2. Gemensam modell har explicit vilande, varning, farlig och avklingande fas. Varnings- och aktiveringstid utgår från banans tick/tidsmodell, inte en lokal scen-timer som kan skilja mellan SP och MP.
3. Ge tillräcklig förvarning vid både normal och itemförändrad hastighet. Utgå från befintlig cooldown för gravitationsbyte och verklig korsningstid mellan sidorna. Kontrollera minst 250, 500 och 750 px/s. Spöket får inte bli farligt inne i en spelare utan föregående möjlighet att reagera.
4. Varning visar tydligt vilken sida som blir farlig. Farlig fas har en tydlig kropp och kontaktgräns; avklingande fas är ofarlig och visuellt annorlunda. Undvik blinkande otydlig collision och stroboskopiska effekter.
5. Placering utesluter omöjliga kombinationer med motsatta sidans spikes, såg, permanent sten och hål. Återanvänd banans säkerhetsregler och utöka dem där det behövs. Målet är kontrollerbar variation, inte ett krav på att varje bana innehåller ett spöke.

### Implementation

Inventera befintliga shared hazard scenes, course generator, shared world model, race course presentation och biome-definitioner. Inför en gemensam spökscen med egen presentation och utbytbar textur/resurs. Modellen äger faser, position och collision; scenen får kosmetiskt sväva utan att flytta den logiska kontaktgränsen. SP och MP använder samma anpassning mellan modell och scen, inklusive spectating.

Första grafiken kan vara en egen enkel SVG med tydlig siluett, ögon och transparent svans, med separata färger/alpha för varning och farlig fas. Resursens storlek/origin ska vara dokumenterad så en framtida sprite/animation kan ersätta den. Dekorativa spöken ska inte se identiska ut med farliga.

Lägg stabil hazardtyp i diagnostik och gemensam encounter-tracker. Registrera endast faktiskt passerade/upplevda hinder, inte alla förgenererade objekt. Nya tillstånd ska fungera vid omstart, sena snapshots och återanslutning; ingen lokal fade får återaktivera ett redan avslutat spöke.

### Klart när

- Samma seed/tick ger samma spökfas, position och collision i SP/MP.
- Båda sidorna förekommer; en rimlig gravitationsmanöver undviker isolerat spöke vid de tre hastigheterna och kombinationsregler verifieras över ett avgränsat seedurval.
- Äldre generatorer behåller låsta hash-fixturer och tidigare såg/stenbeteenden.
- Faktiska scener granskas visuellt i landscape och portrait. Ingen varning täcks av HUD och spöket går att skilja från bakgrunden.

## Del 2: Gemensamma ljudeffekter som kan bytas fil för fil

### Filer och kopplingar

Starta med myntupptagning, gravitationsbyte, tunnförstörelse och stennedslag. Spökets varning kan få en kort diskret effekt om det kan göras inom samma lösning. Ingen kontinuerlig sågloop krävs i denna leverans.

Det finns syntetiska utkast i ../.codex-sfx-preview: coin.wav, gravity_flip.wav, rock_impact.wav och generate_previews.py. Flytta användbara utkast till vanliga spelassets och komplettera med tunnljud via ett deterministiskt offlineverktyg. Behåll genereringsverktyget så utkasten kan reproduceras. Generera inte samples i spelens frame-loop.

Inför en liten gemensam ljudbank med stabila eventnamn och AudioStream-resurser. Filbyte/import eller byte av resursreferens räcker för nya ljud. Dokumentera format, ungefärlig längd, loudness/peak och eventuell normalisering. Första ljuden ska vara korta och försiktiga i nivå, utan klick vid början/slut.

### Uppspelning och nätverk

- En gemensam SFX-controller/bus används för SP/MP; musikkontrollern fortsätter äga musik.
- Myntljud startar tillsammans med myntets befintliga visuella pickup-animation. collect()/animate_collection()/begin_visual_prediction() ska inte ge flera ljud för samma pickup. Bekräftelse efter prediktion och duplicerade nätmeddelanden får inte spela om ljudet.
- Stabil eventnyckel inkluderar runda och entity-id där tillämpligt. Om en prediktion avvisas återställs myntet med befintlig mekanism; rensa dedup-tillstånd korrekt för ett senare riktigt upptag. Ingen wallet eller achievement tilldelas av ett kosmetiskt ljud.
- Flip hörs en gång vid accepterad lokal flip, inte varje gång en snapshot innehåller samma gravitation. Kosmetiskt remote-ljud får endast spela för en faktiskt presenterad övergång, utan dubbletter.
- Tunn-/steneffekter knyts till gemensam scenhändelse/övergång. Ingen ljudstorm från förgenererade hinder, initiala snapshots, gamla impacts eller offscreen-spelare. Bestäm och dokumentera audibility utifrån aktiv kamera/presenterad figur, även vid spectating.
- Begränsa samtidiga röster med en liten återanvändbar pool och prioritering. Profilera att en tät myntsekvens inte blockerar spelet. Rensa aktiva röster och eventnycklar vid scen-/rundbyte.
- Verklig mute stoppar SFX och nya uppspelningar. Paus får inte köa ljud som spelas upp i en klump efteråt. Webbläsarens ljudlås respekteras; använd befintlig användargest och köa inte gamla händelser till upplåsning.

### Inställningar och HUD

Separat beständig SFX-volym och enabled/mute i PlayerProfile och en egen SFX-bus. Behåll musikens låga gainkurva och fungerande paus/resume. Börja med försiktig SFX-standardnivå, exempelvis 25 procent med mjuk gainkurva; inställningen kan finjusteras senare.

Återanvänd gemensam HUD/popover och Options. Lägg musik- och ljudeffektskontroller i samma ljudpanel, tydligt märkta och med separata muteval. Ändra inte högtalarknappens etablerade musikmute-beteende utan tydlig anledning. Högtalarhover får fortfarande inte öppna slidern; öppning går via pilen. Använd riktiga ritade ikoner, inte fonttecken. Desktop, touch och tangentbordsfokus måste fungera och menyn behålla mellanrum samt linjering.

### Klart när

Automatiska kontroller visar en pickup-animation/en ljudstart för prediction+confirmation, separata rundor tillåter samma entity-id, mute håller röster stoppade, settings överlever omstart och musikvolym påverkas inte. Kontrollera WAV-filer, poolgräns och faktisk Web-start/paus/resume. Ange ärligt att beställaren ännu inte lyssnat och att den konstnärliga ljudbedömningen återstår.

## Del 3: Multiplayer använder befintliga achievements och kontoprogression

### Viktig nulägeslucka

SP använder AchievementService och AccountProgress.record_completed_run med distans, flips och hazards. Den befintliga SP-RPC:n ger även wallet-mynt. MP använder redan en separat gemensam coin award-ledger och settle_my_pending_multiplayer_coin_awards, som återför walletbalance. Att skicka MP-resultatet till SP-RPC:n med mynt skulle därför kunna ge dubbla pengar. Lös detta uttryckligen.

### Server och identitet

1. Behåll befintliga achievement-definitioner och belöningar som källa till sanning. Inför inte nya trösklar eller en separat MP-katalog i klienten.
2. Ge avslutad spelares MP-mätvärden ett stabilt kvitto bundet till backend-runda, nätverksslot och inloggat konto. Använd sparad round/member/account-link och auth.uid(), aldrig visningsnamn eller klientens valfria konto-id som behörighet.
3. En särskild MP-progress-RPC registrerar distans, bästa löpdistans, accepterade gravity flips och mötta hazardtyper exakt en gång. Den ger inga wallet-mynt och lägger inte MP-rundor i SP:s seed-specifika leaderboard.
4. Myntens total_coins_earned uppdateras från ledgerns faktiskt nytillkomna settlement-delta, exakt en gång i samma transaktion som settlement. Sena awardbatcher kan ge ytterligare delta; upprepade requests ska ge noll extra. Metrics-RPC:n får inte lägga till samma mynt igen.
5. Återanvänd befintlig achievement-utvärdering för både metrics och coin-settlement och returnera aktuell achievement-state samt nya unlocks. Var försiktig med återanvändning av SP-funktioner som också mintar wallet/rewards.
6. Validera terminalstatus, startad runda, medlemskap och rimliga/icke-negativa mätvärden. Dokumentera befintlig P2P-tillit; påstå inte serververifierad anti-cheat om det inte finns. Gäster får spela men deras gästresultat ska inte senare importeras till ett inloggat konto.
7. RLS/grants och SECURITY DEFINER följer projektets härdade mönster. Nya tabeller är inte direkt skrivbara av klienten. Migration är framåtriktad, med unikt ledigt nummer och regression för befintliga SP-funktioner.

### Klient och gemensam presentation

Använd samma run-metric/encounterlogik i SP och MP där det är möjligt. Distans/flips/hazards gäller egen spelares riktiga runda, aldrig den som kameran senare spectatar. Begin vid verklig loppstart, inte preparing. Frys egna terminalvärden vid bekräftat resultat och lämna dem kopplade till rundans identitet.

Utöka AccountProgress med beständig retrykö för MP-kvitton utan att byta id varje försök. Gamla SP-köposter ska fortsatt fungera. Kontoändring, sen respons från föregående runda, lobbybesök, rematch och reconnect ska inte tilldela fel konto eller dubbla metricvärden. Failed preparing ger ingen avslutad löpdistans. Redan intjänade coin awards följer befintlig settlementväg även om ett senare UI-/nätfel inträffar.

AchievementService används för gemensamma toasts/resultat. Undvik dubbelräkning när bekräftade mynt flyttas från provisoriska run-metrics till serverns total under pågående runda. Visa samma achievement-presentation som SP, utan interna texter om pending RPC, sparade kontomynt eller gemensamma mynt i HUD. Nya hazardtyper rock/saw/ghost ska kunna registreras genom samma stabila allowlist/catalogmönster som äldre typer.

### Klart när

Lokala SQL-fixturer verifierar normal slutföring, duplicerat/anropskonkurrerande kvitto, sen settlement-delta, account/slot-förfalskning, gästanrop, preparing-abort och befintlig SP-award. Varje godkänt mynt ger en wallet-credit och en total-coins-credit; metrics-retry ger inga pengar. Klienttester verifierar rematch, spectating, kontoändring och pending-queue-omstart. Testa mot syntetiska lokala användare, inte riktiga konton med fabricerade belöningar.

## Införande, granskning och release

1. Luna dokumenterar baslinje/dirty-hunks och status. Implementera del 1, 2 och 3 med avgränsade commits och meningsfulla tester. Rapportera blockerare till root; undvik att fylla kvoten med oförändrade omkörningar.
2. Kör befintliga berörda presentation-, shared-world-, coin prediction-, start/lobby- och kontrakttester. Gör ett avgränsat seedurval, normalt cirka 120, samt flera rematch/reconnect-sekvenser med fördröjda/duplicerade gamla events. Inget ändlöst soakjobb.
3. Leverera implementationsrapport med faktiskt körda kommandon/resultat, migrationsdiff, beteendebeslut, screenshots och kända begränsningar. Root granskar shared architecture, collision/timing, dubbla wallet/unlocks/ljud, HUD och selektiv staging. Vid fynd rättar Luna och kör de berörda kontrollerna igen.
4. Efter rootgodkännande: commit/push till Azure, skapa rent arkiv av exakt gameplaycommit. Import/parse och faktisk SP-start ska lyckas i arkivet; bygg sedan Web därifrån. Aldrig bygga publiceringen från den blandade arbetskatalogen.
5. Applicera nödvändiga granskade live-migrationer via projektets befintliga Supabase-väg. Kontrollera migrationshistorik och versionsgrind innan Pages. Följ verktygens godkännandegranskning; vid avslag lämnas det färdiga paketet orört och den exakta blockeraren rapporteras till root. Tid eller quotareset är inte ny auktorisation.
6. Publicera befintlig Pages-root, invänta workflow success, verifiera loaderns build-id och publicerad PCK-hash mot det rena paketet samt verklig browserladdning. Ingen andra publik spel-URL eller synligt V2-namn införs.
7. Slutrapport anger Azure-/Pages-commits, build/länk, migrationsstatus, utförda tester och vad som återstår att manuellt uppleva. Root återkopplar när Luna och granskningen är klara, inte endast när någon frågar efter status.

## Kort manuell kontroll efter leverans

- SP och MP: haunted-spökets förvarning går att förstå och undvika; samma fas/hastighet på båda.
- Mynt, flip, tunna och sten ger korta diskreta ljud; mute/volym är separata från musik och håller efter paus/rematch.
- Gemensam HUD har kvar korrekt ikon/menu-layout och pilen öppnar ljudpanelen.
- Inloggad MP-spelare får befintliga achievements/progression; reconnect/rematch ger inget dubbelt och spectating räknar inte annan spelares löpning.
- Gamla seed/generatorvarianter fungerar fortfarande.
