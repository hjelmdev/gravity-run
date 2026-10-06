# Spökvarianter, tydligare svårighet och fria startbiomer

Användarens uppdrag 2026-10-06: senare spökvarning, fler skins inklusive ett läskigare spöke med samma beteende, klart fler hinder/svårare banor samt slumpad startbiom i fria SP/MP-rundor. Root samordnar befintlig Luna och slutgranskar före ordinarie release.

## Baslinje och omfattning

- Bekräfta HEAD; senaste gameplay 74a838b, rapport 6f150ba. Gen15 och den nyligen verifierade gemensamma grottfixen är baslinje.
- Bevara orelaterade dirty hunks, touchfix, dödsljud, capturefeature och fungerande mynt/ljuddedup. Inga konkurrerande implementationer. Dokumentera fas och nästa steg i tillhörande STATUS.
- Återanvänd gemensamma scener, modeller och generator. Nya assets ska kunna ersättas som resurser utan ändrade spelregler.

## 1. Spökvarning och skins

- Inventera skillnaden mellan aktivering, HUD-varning, synlig warningfas och dödlig fas. Senare varning ska faktiskt synas/höras närmare mötet, inte oavsiktligt låta spöket försvinna före kontakt eller börja dödlig fas inne i spelaren.
- Mät nuvarande tid/distans till kontakt vid 250/500/750 px/s. Sikta på cirka 0.8–1.2 sekunders begriplig varning där det går; använd säker reaktionsmarginal och dokumentera slutliga värden. Fördröj enbart presentation om spelregler inte behöver ändras; versionera alla ändrade gameplaytider.
- Behåll befintligt skin och lägg till minst två tydligt olika skins, varav ett med mörka ögon/arg eller kuslig min. Befintliga SVG-resurser är lämpliga; ingen ny bitmap-pipeline behövs.
- Gemensam GhostHazard-scen väljer utbytbar visuell resurs deterministiskt per event. Samma event visar samma skin i SP, host, gäst, retry och spectator. Samma hitbox, faser, svävning och beteende för alla skins; ingen global render-RNG.
- Spara faktiska gameplaybilder med varianterna för rootgranskning.

## 2. Märkbart högre hindertäthet

- Mät före/efter flera seeds och samtliga biomer: accepterade faktiska hinder per distans, tomma luckor, förkastade kandidater och myntbudget. Bara högre vikter är inte tillräckligt om säkerhetsfilter ändå tar bort dem.
- För ny generator sikta initialt på 35–50 procent fler verkliga möten per distans efter den korta säkra starten. Kortare mellanrum och fler befintliga spikar/tunnor/stenar/sågar/spöken/lava där biome och nåbarhet tillåter.
- Behåll kort startmarginal, men undvik lång tom första biom. Tätare utmaning och viss återhämtning, inga osynliga eller omöjliga kombinationer. Begränsa samtidiga effekter/projektiler.
- Kör fullmanifest-rutter med riktig simtid för relevanta hastigheter och eruptionfaser; kontrollera stöd/hål, flipcooldown, spiktunna/block, fallande objekt och frivilliga mynt. Sänk inte säkerhetsmarginaler blint för att uppnå procentmålet.
- Kontobelöningar och idempotens ska fortsätta använda befintlig gemensam väg. Ingen extra walletimplementation eller oavsiktlig myntinflation.

## 3. Seedstyrd fri startbiom

- Nya fria SP/MP-rundor väljer bland classic/cave/haunted/lava deterministiskt från seed, med rimlig fördelning över en seedkohort. Ingen lokal slump vid start eller rendering.
- Använd ett gemensamt biome-schema/offset för generator, hazardurval, riskmynt, bakgrund, mark/tak och diagnostik. MP preparing/countdown/START får inte byta biom, ankare eller teleportera scenen.
- Samma seed/version/lägesregler ger samma bana och biom i SP/MP. Retry behåller startbiom, ny slumpbana kan välja en annan. Bevara parallax och nyligen lagad floatklippning genom alla gränser och portrait.
- Respektera sparade challenges och äldre seeds. Förbered en enkel explicit policypunkt för framtida fast campaign-värld; implementera ingen campaign nu.

## Versioner, granskning och publicering

- Frys Gen15 representativa manifest/biome/mynt/trajectoryhashar före ändring. Nya regler kräver förväntat Gen16; äldre Gen15 och tidigare måste behålla exakt generering och presentation där versionerad.
- Audita versionsallowlists/defaults, seedparsning, manifestvalidering och backendgrindar. Ändra API/manifest bara vid faktisk kontraktsändring. Nödvändig migration ska vara scoped och granskas av root före live.
- REVIEW_READY ska innehålla faktisk diff, före/efterstatistik, dokumenterade korta seeds för alla fyra startbiomer, senare spökvarning och samtliga skins, GPU/gameplaybilder samt relevanta tester med begränsningar.
- Root granskar och låter Luna rätta konkreta fynd. Efter rootapproval: scoped Azure push, nödvändiga granskade migrations med linked history, rent exakt-commit Webbygge/Pagesrootpublicering. Verifiera workflow/head, båda BUILD_ID/loaders och oberoende offentlig PCKhash.
- Kör seriella bounded Godottester med egna PID/barncleanup; bevara användarens editor och andras processer. Vid capacityfailure dokumentera durable checkpoint så root kan slutföra. Återförsök inte nekad livehandling utan relevant faktisk auktorisation.
