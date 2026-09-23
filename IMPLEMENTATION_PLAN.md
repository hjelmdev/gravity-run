# Gravity Run – implementationsplan

Det här dokumentet beskriver den första spelbara versionen av Gravity Run. Målet är att snabbt få fram en liten prototyp där gravitationsmekaniken kan testas innan vi bygger mer innehåll.

## Förberedelser

1. Installera Godot 4.x.
2. Starta Godot Project Manager.
3. Skapa ett nytt projekt med namnet `Gravity Run`.
4. Välj projektmappen: den här projektmappen.
5. Använd standardrenderer till att börja med.
6. Skapa och öppna projektet.

## Milstolpe 1 – Grundläggande spelare

1. Skapa en huvudscen för spelet.
2. Skapa en spelarscen med en enkel färgad rektangel eller figur.
3. Lägg till fysik så att spelaren påverkas av gravitation.
4. Lägg till ett golv och ett tak.
5. Få spelaren att röra sig automatiskt åt höger.
6. Lägg till kamera som följer spelaren.

**Klart när:** en enkel figur springer framåt mellan golv och tak.

## Milstolpe 2 – Gravitationsbyte

1. Lägg till input actions för `gravity_up` och `gravity_down`.
2. Koppla upp/ned-tangenterna till dessa actions.
3. Låt spelaren byta gravitationsriktning mellan golv och tak.
4. Förhindra ett nytt byte medan spelaren är i luften.
5. Lägg till en kort cooldown.
6. Visa cooldown med enkel text eller färgindikator.

**Klart när:** spelaren kan växla mellan golv och tak med timing som känns kontrollerad.

## Milstolpe 3 – Första hinder och game over

1. Skapa ett enkelt hinder.
2. Lägg till kollision mellan spelare och hinder.
3. Avsluta rundan vid kollision.
4. Visa distansen spelaren nådde.
5. Lägg till en restart-knapp.
6. Lägg till enkel start- och game-over-text.

**Klart när:** spelet har en komplett loop: starta, spring, träffa hinder, försök igen.

## Milstolpe 4 – Första powerup

1. Skapa powerupen `Air Flip`.
2. Låt spelaren samla upp den.
3. Tillåt ett gravitationsbyte i luften.
4. Begränsa powerupen till en användning.
5. Visa tydligt när powerupen är tillgänglig.
6. Lägg till ett enkelt ljud eller visuellt resultat.

**Klart när:** powerupen skapar nya möjligheter utan att göra grundmekaniken otydlig.

## Milstolpe 5 – Spelbar prototyp

1. Lägg till flera hinder med olika placeringar.
2. Skapa en enkel svårighetskurva.
3. Öka hastigheten gradvis.
4. Lägg till poäng och high score lokalt.
5. Lägg till enkel bakgrund och tillfällig grafik.
6. Testa spelet med tangentbord.

## Mobilstöd senare

När tangentbordsprototypen fungerar:

1. Lägg till swipe upp och swipe ner.
2. Koppla swipe till samma input actions som tangentbordet.
3. Anpassa UI för touchskärm.
4. Testa olika skärmformat.

## Framtida banor och hinder-spawning

Sandbox/testbanan används för att prova hinder och banformer. När ett hinder fungerar bra görs det till en återanvändbar Godot-scen som kan placeras i flera banor.

Banor ska kunna genereras löpande under spelningen, särskilt i endless mode, i stället för att hela den långa banan skapas eller hålls aktiv från start. Spelet håller ett begränsat område med bansegment och hinder framför spelaren, och frigör eller återanvänder sådant som passerats. Nya delar förbereds i god tid före spelaren för att undvika märkbara laddningsstopp eller lagg.

Campaign och endless ska på sikt kunna välja hinder dynamiskt med viktad slumpning:

- I campaign kan vikterna påverkas av banans nivå eller kapitel.
- I endless kan vikterna påverkas av distans, speltid eller aktuell svårighetsfas.
- Nya eller svårare hinder blir gradvis mer sannolika, men ska inte vara garanterade i varje bana eller spawnsekvens.
- Spawnlogiken ska också ta hänsyn till kombinationer och mellanrum så att slumpen skapar utmanande men möjliga situationer.
- Samma löpande genereringssystem kan användas i campaign, men med kontrollerade sekvenser och introduktion av hinder i lagom takt.

Tekniskt kan detta senare byggas med återanvändbara bansegment/hinderscener, förhands-spawning utanför skärmen och återanvändning av objekt (pooling) där det behövs. Genereringen bör ske stegvis och förutsägbart nog att spelet kan kontrollera att sekvensen går att klara.

Detta är en framtida systemdesign och ska inte byggas in i den första mekanikprototypen.

## Framtida utmaningslägen och delbara seeds

- Ett asynkront utmaningsläge kan låta en spelare dela sin run med en vän: "Här är banan och mitt resultat – kan du slå det?" Vännen spelar samma genererade sekvens och försöker nå längre eller få bättre resultat.
- En seed kan återskapa samma procedurgenererade bana, så länge spelet även använder samma generatorversion, regler och relevanta run-inställningar. Seed ensam är inte tillräckligt om generationen ändras i en senare uppdatering.
- Använd en separat, seedad slumptalskälla för baninnehåll så att exempelvis en ny slumpmässig coin-effekt inte råkar ändra vilka hinder som skapas senare i banan.
- En delbar utmaning kan innehålla seed, generator-/regelversion, målresultat och eventuellt begränsningar för karaktär, talents och equipment. För rättvis jämförelse kan utmaningsruns använda en standardiserad loadout.
- En länk kan öppna utmaningen direkt i webbläsaren. På desktop/mobil kan samma utmaningskod eller länk öppnas i spelet. Exakt länkhantering beror på plattform och kan planeras senare.
- Börja med asynkron "slå mitt rekord"-utmaning. Det är mycket enklare än samtidig multiplayer och passar seedad generation. Live-versus kan utvärderas separat senare.
- Om generatorformatet ändras behöver äldre seeds antingen behålla sin gamla generatorversion eller markeras som inkompatibla; annars kan vännen få en annan bana än utmanaren.

## Banform: skarpa kanter och höjdskillnader

- Förutom slopes kan golv och tak ha skarpa nivåskiften, vertikala kanter och utskjutande steg, med eller utan spikes. Bilden är en referens för denna typ av mer blockig banprofil.
- Håll terrängens form och farliga hinder som separata begrepp: en kant kan vara en solid/blockerande yta utan att automatiskt vara dödlig, medan spikes på kanten är en tydlig lethal hazard.
- Sandbox-regel: ospikade hårda terrängkanter blockerar scrollen tills spelaren byter sida och kommer loss; spikes på den vertikala kanten är dödliga vid kontakt.
- En hård kant är en permanent profiländring: golvets eller takets höjd ändras abrupt och den nya nivån fortsätter efter kanten tills en senare slope eller hård kant ändrar den igen. Separata små blockhinder finns kvar.
- Under blockeringen står banan och vanliga hinder stilla, men tunnor fortsätter rulla. En tunna ska inte passera genom en solid terrängkant.
- Första prototypen varierar nivåskiftets storlek och avståndet till nästa hårda kant. Spikes sitter på den vertikala framkanten och pekar mot spelaren.
- Skarpa nivåskillnader kan vara campaign-specifika och introduceras med tydlig visuell förvarning. Procedurgenerering måste kontrollera att kombinationen av kanter, gravitationsbyten och hinder fortfarande är möjlig.

## Framtida collectibles och belöningar

- Vanliga coins kan samlas under en runda. De kan bidra med en mindre poängbonus och sparas som valuta till framtida kosmetiska upplåsningar/shop.
- High score bör i första hand baseras på överlevd distans, så att valutan inte kan farmas på ett sätt som gör topplistan missvisande.
- Varje campaign-bana kan ha tre särskilda collectibles, inspirerade av samlaruppdrag som bokstavsserier eller en unik ban-trofé.
- De tre banföremålen är skilda från vanliga coins och powerups. Att hitta alla tre kan ge en completion-belöning, achievement eller kosmetisk upplåsning.
- I campaign kan collectibles placeras i utmanande men avsiktliga sektioner. Om banor genereras dynamiskt ska genereringen garantera att de tre föremålen finns i nåbara delar av banan.
- Endless behöver inte ha exakt tre föremål per bana; där kan coins och särskilda distans-/milestone-collectibles passa bättre.

## Hinderinteraktioner – designanteckningar

- Vanlig tunna som träffar en låda: både tunnan och lådan går sönder.
- I campaign kan vissa avsiktligt placerade lådor innehålla ett av banans tre särskilda collectibles. Spelaren kan behöva tajma gravitationsbytet och låta tunnan slå sönder lådan för att komma åt föremålet. Det ska vara en planerad belöning, inte något som slumpmässigt försvinner.
- Spiktunna: en tyngre/specialtunna som slår sönder lådan men själv fortsätter rulla.
- Gummitunna: studsar eller ändrar riktning vid träff; varken tunnan eller hindret går sönder.
- Framtida bollar kan få egna rörelseregler som studs eller riktningsbyten. Hinderinteraktioner bör styras per hinder-typ, inte vara en generell regel för allt.
- I sandbox-prototypen testas först den vanliga tunnans lådkollision; specialtunnor och collectible-belöningar kommer senare.

## Karaktärer, talents, XP och equipment – idébank

Det här är framtida progression, inte något som behövs för att validera grundmekaniken. Börja med en standardkaraktär och lägg till systemen först när gravitationsbytet, hindren och rundloopen känns roliga.

### Upplåsbara karaktärer och skills

- Karaktärer kan låsas upp och ha en tydlig signaturförmåga, till exempel kortare cooldown, två gravitationsvändningar i följd, en projektil som förstör ett hinder eller en aktiverbar sköld under ett kort antal frames.
- Håll varje karaktärs identitet enkel att förstå: en passiv styrka eller en aktiv förmåga, snarare än många specialregler på samma karaktär.
- Förmågor som förstör hinder eller ger odödlighet behöver tydliga cooldowns, begränsningar och visuella signaler. De ska skapa olika spelstilar utan att göra vissa karaktärer självklart bäst.
- I framtida versus-lägen kan karaktärsbonusar behöva balanseras eller begränsas; tävlingslägen kan också erbjuda ett separat standardiserat regelset.

### Talents och spelarbyggen

- Överväg ett gemensamt talent-träd eller urval som spelaren bygger sin karaktär med, i stället för att behöva uppfinna många helt unika talenter för varje figur.
- Spelaren ska inte kunna köpa/låsa upp allt till samma build. Använd begränsade poäng, förgreningar, nivåtak eller val mellan ömsesidigt uteslutande uppgraderingar.
- Möjliga riktningar: högre löphastighet, snabbare gravitationsvändning/kortare cooldown, extra vändning i luften eller förstärkt powerup-effekt.
- Varje talent bör ha en tydlig fördel och gärna en kostnad eller alternativkostnad. Testa först ett litet antal talenter och se om de ger meningsfulla val.

### XP och nivåer

- XP kan komma från genomförd distans, avslutade banor, coins, förstörda hinder och särskilda mål.
- Låt distans och banframsteg vara stabila huvudkällor. Coins och förstörda hinder kan ge bonus-XP, men bör inte gå att farmas genom att stanna eller upprepa en riskfri handling.
- Ren speltid kan belönas sparsamt eller begränsas per runda, så att aktivt spel och skicklighet fortfarande känns viktigare än att bara låta spelet stå på.
- Spelarnivåer kan ge talent-poäng, men undvik att nivåer automatiskt gör spelaren så mycket starkare att äldre banor eller topplistor blir obalanserade.

### Equipment, slots och loadouts

- Boots kan förändra rörelsekänslan: mjukare/lägre gravitationsvändning, mycket snabb vertikal acceleration, högre fart eller en aktiverbar dash.
- En dash som passerar genom hinder och en dash som förstör hinder bör ses som olika effekter; båda behöver tydliga begränsningar och kan passa olika boots.
- Andra möjliga slotar: hjälm för längre powerup-varaktighet eller bättre förvarning om hinder; handskar för projektil, interaktion med lådor eller längre sköld; rygg-/verktygsslot för en aktiv gadget.
- Första versionen bör ha få slots och tydliga effekter. Boots påverkar själva kärnmekaniken mest, så testa dem separat innan flera equipment-effekter staplas.
- Rekommenderad modell att utvärdera: permanenta föremål låses upp eller hittas och sparas i ett inventory/stash; spelaren väljer en begränsad loadout före rundan. Förbrukningsvaror kan vara tillfälliga och köpas/hittas separat.
- Shop kan vara ett sätt att välja vad spelaren låser upp, men banor och särskilda mål kan också ge unika föremål. Undvik att slumpmässiga drops krävs för att klara campaign.
- Skilj gärna kosmetiska val från gameplay-equipment, särskilt om topplistor eller versus blir viktiga.

### Föreslagen ordning när progression blir aktuell

1. En enkel XP-källa och spelarnivåer.
2. Ett litet gemensamt talent-urval med begränsade poäng.
3. Några tydligt olika karaktärsförmågor.
4. Inventory, loadouts och ett fåtal equipment-slotar.
5. Shop, fler föremål och balansregler för tävlingslägen.

## Viktiga designprinciper

- Mekaniken ska kännas responsiv och förutsägbar.
- Spelaren ska normalt inte kunna byta gravitation mitt i luften.
- Powerups ska bryta regeln tillfälligt, inte ersätta den.
- Vi prioriterar spelkänsla framför grafik i första versionen.
- Multiplayer, kosmetik och topplistor väntar tills singleplayer-loopen fungerar.

## Nästa konkreta steg

När Godot är installerat börjar vi med Milstolpe 1, steg 1: skapa huvudscenen och spelarscenen.

## Sandbox – aktuella experiment

- Hinder är separata återanvändbara scener: spikes, block och tunna.
- Coins spawnar i små grupper på olika höjder i spelområdet och räknas per runda. Shop, sparad valuta och banornas tre särskilda collectibles är framtida arbete.
- Återanvändbara ramper kan ändra golvets eller takets höjd; den nya nivån består tills en senare ramp ändrar den igen. Gravitationen förblir lodrät.
- Testa coin-gruppernas spridning och rampsekvensernas riktning/frekvens innan vi bestämmer slutliga regler eller bygger campaignbanor.
- En del tunnspawns parar nu en tunna med en låda framför. Vid kollision går båda sönder; det provar grundregeln för framtida låda-collectible-sektioner.
- Hårda terrängskiften testas från både golv och tak med varierad nivåskillnad och varierat avstånd mellan skiften. Den nya ytan består efter kanten; ospikade kanter blockerar scrollen tills spelaren byter sida och spikar på framkanten är dödliga. Små block är fortsatt separata hinder. Kontrollera särskilt samspelet med slopes och tunnor.

## Kodstruktur – första uppdelning

- `Player`-scenen äger rörelse, gravitationsbyte och spelarens presentation.
- `PlayerEffects` är komponenten för tidsbegränsade spelareffekter som fartbonus och spikeskydd.
- `RunState` äger distans och coins för den aktiva rundan och skickar signaler när värden ändras.
- `PlayerProfile` är en Autoload som sparar plånbok och bästa distans mellan rundor.
- `HUD` lyssnar på `RunState` och spelarens status via signaler, och visar värdena.
- Coin-scenen skickar `collected(value)`; rundans coin-räknare och profilen uppdateras utanför coin-scenen.
- Hinderscener äger sin egen förstörningsanimation och livscykel. De skickar `destruction_started` när effekten börjar och `destroyed` när den är färdig; spelvärlden hanterar interaktionsregler (t.ex. tunna mot låda) och kan lyssna på signalerna för ljud, poäng eller annan respons.
