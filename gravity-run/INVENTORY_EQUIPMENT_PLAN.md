# Inventory, utrustning, karaktärsvy och shop

## Mål och beslutad första version

Bygg ett kontobundet inventory med en karaktärsvy inspirerad av klassiska RPG-spel: figur i mitten, tydliga utrustningsplatser, en väska med föremålsikoner, en panel med stats och detaljer om valt föremål. Börja med **hjälm** och **skor**. Det ska gå att köpa föremål för kontots coins och ibland hitta ett föremål i en runda. Rarity i första katalogen: `common`, `uncommon` (grön), `rare` (blå), `epic` (lila). Förbered även `legendary` i modellen, men skapa inget sådant föremål förrän det behövs.

Första publicerbara katalogen får gärna ha fyra till sex handgjorda föremål med fasta egenskaper och egen ikon. De behöver ännu inte ändra spelreglerna. Visa inga fiktiva `+1 Speed` eller `+1 HP` om effekten inte faktiskt finns. Implementera däremot en testad, datadriven beräkning av utrustningsbonusar och tydliga integrationspunkter för framtida effekter.

Konton äger föremål. Gäster kan spela som nu, men får inga persistenta föremålsfynd och kan inte handla eller utrusta. Karaktärsvyn kan visa grundstats och en kort uppmaning att logga in. Ingen gästinventarie eller tyst sammanslagning vid inloggning ingår.

## Läget i koden och viktiga kopplingar

- `main.gd` startar rundan i `_start_run()`, flyttar världens objekt i `_physics_process()` och avslutar via `RunState.finish_run()`. `RunState` skickar redan rundans coins och resultat till `AccountProgress`.
- `AccountProgress` köar avslutade rundor med ett `run_id` och återförsöker kontosparning. `record_player_run(...)` i senaste SQL-migrationen uppdaterar plånbok, distans och achievements atomärt och idempotent per `(user_id, run_id)`.
- `PauseMenu` är en `CanvasLayer` som processar även vid paus. Den använder redan `SceneTree.paused`, men porträttläge i webben ändrar samma booleska värde. Detta måste samordnas innan inventory kan öppnas/stängas tillförlitligt.
- `Player` har fasta värden för vertikal fart, gravitation och cooldown. Den nuvarande `main.gd::_run_speed()` flyttar banan förbi en X-låst spelare; det är en simuleringsdetalj, inte den avsedda betydelsen av löphastighet. Utrustningens fartstat ska motsvara spelarens hastighet genom spelvärlden och efter singleplayer-refaktorn påverka spelarens `world_x` medan kameran följer. Generatorns nuvarande fartantagande är en planeringsbegränsning som ska testas/justeras, inte ett skäl att göra statbonusen meningslös.
- Utmaningskoder bygger på deterministisk ban-generering. Coins ligger redan utanför likvärdighetsgarantin. Föremålsfynd ska också ligga på ett separat slumpflöde och får inte förbruka `CourseGenerator`-slump eller ändra hinderplacering.
- `main_menu.gd` bygger menyer i kod och har redan konto, achievements och utmaningar. Lägg inte all inventory-, shop- och karaktärslogik i denna stora fil; låt en separat spelhubb och återanvändbara vyer äga spelrelaterade skärmar.

## Navigation: huvudmeny → spelhub → runda

Huvudmenyn är ingången **till** spelet och samlar sådant som gäller appen/kontot: **Spela**, **Konto**, **Inställningar** och **Avsluta** (på webben en kort stängningshjälp). Flytta spelrelaterade val från den långa knappstapeln till en separat **spelhub** efter Spela. En inloggad användare och en gäst kommer till samma hub; kontobundna funktioner visar inloggningskrav utan att gästen hindras från att starta en runda. Behåll eventuell demobakgrund om den fungerar visuellt, men skapa en tydlig scen-/vygräns (`game_hub.tscn`/`game_hub.gd`) i stället för fler paneler i `main_menu.gd`.

Hubben är spelarens förberedelseläge. Den har **Starta runda** som tydlig huvudhandling och ett val för **Challenges**. **Längst ner i hubbens menypanel** ligger en egen rad med två **fyrkantiga ikonknappar**: **Karaktär/Väska** (figur- eller ryggsäckssymbol) och **Butik** (klassisk marknads-/ståndsymbol). De ska ha samma storlek och tydlig aktiv/fokusmarkering. Visa en kort etikett under symbolen och tooltip/tillgängligt namn så betydelsen inte hänger på bilden ensam. Använd enkla, konsekventa platshållarsymboler i första versionen; byt till riktiga pixelikoner när sådana assets har skapats, utan att behöva bygga om layouten. **Achievements** och **Topplistor** hör också till spelhubben, men kan ligga i en sekundär rad eller flik för progression/tävling; de ska inte bli en ny vertikal lista av likvärdiga huvudknappar. Placera saldot nära butikens ingång och visa kontostatus diskret. Karaktärsvyn kan använda hubben som bakgrund och återvända dit utan scenbyte; samma sak gäller shoppen.

Översikt över flöden:

```text
Start/Huvudmeny ── Spela ──> Spelhub ── Starta runda ──> Aktiv runda
   ├─ Konto/Inställningar      ├─ Karaktär/Väska                   ├─ Karaktär/Väska (paus)
   └─ Avsluta                  ├─ Butik                             ├─ Butik (paus)
                              ├─ Challenges                       ├─ Pausmeny
                              └─ Achievements/Topplistor          └─ Slutvy ──> Spelhub/Spela igen
```

Ändra normal återgång från pausens ”Quit to main menu” och slutvyn till **Till spelhubben**; behåll en väg vidare till start-/huvudmenyn från hubben. ”Spela igen” startar samma typ av runda som nyss, inklusive vald challenge när det är avsikten. Befintliga challenge-länkar och koder ska fortfarande fungera: öppna hubben med aktuell challenge förvald och dess detaljer synliga, sedan startar spelaren den därifrån. Tappa inte skapade/sparade challenges eller leaderboard-navigering när knappar flyttas.

Detta är en navigationsändring, inte bara en omflyttning av knappar. Inför ett litet `RunSelection`/intent-objekt eller använd `ChallengeService` konsekvent för vald normal/challenge-runda så hubb, retry och direktlänk inte råkar starta olika lägen. Gör hubben till enda vanliga startpunkt för nya rundor; befintliga direkta scenväxlingar i `main_menu.gd` behöver därför ses över.

## Spelregler och UI-beteende

1. Hubben har separata, fyrkantiga ikonknappar för **Karaktär/Väska** och **Butik** längst ner i menypanelen. Karaktärsvyn innehåller flikar eller tydliga sektioner för Character och Inventory. Under en aktiv runda finns samma två symboler i HUD:en, samlade med pausknappen utan att skymma spelplanen. `I` öppnar karaktär/inventory på desktop. Båda vyerna pausar rundan; pausmenyn har samma två genvägar. Ingen extra likvärdig Character-/Shop-knapp läggs i huvudmenyn.
2. Under en runda är **utrustningsbyte låst**. Karaktärens aktiva stats visar rundans start-snapshot; väskan kan visa aktuellt kontoägande med tydlig markering om ett köp görs under pausen. Butiken får användas under pausen med redan serverbekräftade coins, men inköpet påverkar inte den pågående rundan och får utrustas först i hubben. Visa ”Ny utrustning gäller nästa runda”. Ett fynd från aktuell runda är väntande tills servern har sparat rundan och kan därför inte köpas/utrustas som om det redan ägdes.
3. Escape/Back från karaktär eller butik återgår till föregående vy: till spelet om ikonen öppnades direkt under rundan, till pausmenyn om den öppnades därifrån, eller till spelhubben om den öppnades därifrån. Stängning får inte råka återuppta spelet när porträttläge fortfarande kräver paus.
4. Väska: rutnät med 24 synliga celler per sida, paginering eller scroll vid fler föremål, sortering efter slot/rarity/namn, tydlig markerad vald ikon. Ingen lagringsgräns i version 1; de 24 cellerna är presentation, inte ett servervärde. Utrustade föremål visas i sina slots och kan även listas med en ”equipped”-markering.
5. Välj ett föremål för namn, rarity, slot, beskrivning och faktiska statbonusar. Knappen Equip/Unequip gör en serverbegäran; UI visar vänteläge, dubbelklick skickar inte dubbla begäranden och misslyckande återställer föregående läge med begripligt fel. Dra och släpp kan läggas till senare genom samma serviceanrop.
6. Shop visar ikon, rarity, pris, ägd-status och coin-saldo. Köp kräver inloggning och tillräckligt **bekräftat** saldo. Visa pris och saldo före bekräftelse; serverns transaktionsresultat är avgörande. Köp kan göras från hubben eller medan rundan är pausad, men aldrig ändra rundans loadout. Visa resultatet i väskan utan att byta aktiva stats.
7. Ikoner är lokala Godot-resurser. Databasen lagrar ett kort `icon_key`; klienten mappar en tillåten nyckel till `res://assets/items/...`. Okända nycklar visar en säker standardikon. Namn och beskrivningar är lokaliserade med nycklar i `sv.po` och engelsk grundtext. Färger får stöd av utskrivet rarity-namn och ram/ikon så de inte är enda signalen.
8. Layouten ska fungera vid projektets 960×540 och smal mobilvy. Figur och slots kan gå ovanför väskan på mobil. Ha tydliga tryckytor och tangentbordsfokus. Figurförhandsvisningen kan först återanvända befintlig spelarsprite; rustningsdelar behöver inte ritas på figuren i denna etapp.

## Data- och statmodell

### Katalog och ägda instanser

Skilj **föremålsdefinition** från **ägd instans**. Definitionen beskriver samma modell för alla spelare; instansen ägs av ett konto och kan senare få rollade bonusar, level, durability eller kosmetiskt utseende utan att katalogen behöver dupliceras.

| Fält | Definition (`item_definitions`) | Ägd instans (`player_items`) |
| --- | --- | --- |
| Identitet | Stabil `item_id` som `boots_canvas_01` | UUID `instance_id` |
| Typ | `slot_type`: `boots` eller `helmet` | `user_id`, `item_id` |
| Presentation | `name_key`, `description_key`, `icon_key`, `rarity` | `acquired_at`, `source` |
| Speldata | `stat_modifiers` JSONB och framtida `effect_ids` | Framtida instansdata/version |
| Ekonomi | `shop_price`, `shop_enabled`, `drop_enabled`, aktiv-status | Utrustad slot i separat tabell |

Använd stabila engelska maskin-ID:n i databasen och lokalisera endast presentationen. Rarity är ett definierat värde på katalogposten, inte något klienten skickar vid köp eller loot. Ingen fri kod/skriptnamn får komma från databasen och exekveras som effekt.

För version 1 är varje katalogföremål unikt per konto (`unique(user_id, item_id)`). Dubbla lootutfall ger inget nytt exemplar och ingen automatisk coin-ersättning. UI visar tydligt ”Redan ägd”. Ta bort denna begränsning först när spelet faktiskt får flera exemplar eller rollade egenskaper.

### Slots och beräknade stats

- Använd ett slot-register med stabila nycklar (`helmet`, `boots`) och koppling till tillåtna föremålstyper. Lägg till nya slots via register, UI-layout och databasens tillåtna värden; skriv inga separata equip-flöden per slot.
- Grundstats hämtas från en central `CharacterStats`/`EquipmentStats`-modul och summeras med modifierare från utrustade definitioner i bestämd ordning: basvärde → additioner → multiplikatorer → clamp/validering. Returnera både total och uppdelning per källa för UI och felsökning.
- Ha ett **register över tillåtna stat-ID:n och enheter**, till exempel `run_speed_percent`, `max_health`, `flip_cooldown_percent`. Registrera bara sådant som har definierad betydelse. `+1 speed` är annars tvetydigt: procent, px/s eller poäng. Beräkningen ska avvisa okända ID:n, fel datatyp och värden utanför rimliga gränser. Använd heltal/basis points i lagrad data där precision och balans spelar roll.
- Visa i första vyn endast mekaniker som verkligen finns: exempelvis startfart, ”träffar till död: 1” och gravitations-cooldown. Om de första föremålen saknar bonusar visas ”Inga statbonusar”. Testfixturer får ha modifierare för att bevisa att summering, uppdelning och UI fungerar, men de ska inte säljas.
- Skapa ett `RunLoadoutSnapshot` vid `_start_run()`: instans-ID:n, definition-/balansversion och beräknade värden. Rundan läser bara denna snapshot. Framtida gameplay-adaptrar i `main.gd`, `player.gd` och skadesystemet kan konsumera namngivna värden. Ingen generisk ”effektkod” i JSON.
- När fart eller liv faktiskt aktiveras måste ändringen gå genom explicita adaptrar och tester: farten måste hålla sig inom generatorns säkerhetsgräns eller banplaneraren uppdateras; fler liv kräver skadetillstånd, invulnerability-ramar, UI och regler för fall utanför banan. Dokumentera varje sådan ändring som en egen feature.

## Databas, RPC och synk

Lägg till en framåtriktad migration efter nuvarande `202609260006`. Föreslagen form:

1. `item_definitions`: `item_id` primärnyckel, slot, rarity, lokaliseringsnycklar, ikonnyckel, `stat_modifiers jsonb`, `effect_ids jsonb`, pris, shop/drop-flaggor, `catalog_version`, `active`. Check constraints på slot/rarity/pris/JSON-struktur. Seed endast handgjorda katalogposter.
2. `player_items`: `instance_id uuid` primärnyckel, `user_id` FK `auth.users` med cascade, `item_id` FK, källa (`shop`, `run_drop`, senare `achievement`), `acquired_at`, unik `(user_id,item_id)` i första versionen.
3. `player_equipment`: `(user_id, slot_type)` primärnyckel, `instance_id` unik FK till `player_items`, `updated_at`. Serverfunktionen verifierar att instansen ägs av samma `auth.uid()` och att katalogens slot matchar. Utrustning tas bort eller byts atomärt.
4. `shop_purchases`: `(user_id, request_id)` unik för återförsök samt `item_id`, pris vid köp och tidsstämpel. Priset läses på servern från katalogen och dras från `player_progress.wallet_coins` i samma transaktion som instansen skapas. En upprepad `request_id` returnerar samma resultat. Två samtidiga köp måste serialiseras via lås på plånboksraden; saldo får aldrig bli negativt.
5. `run_item_claims`: `(user_id, run_id, pickup_index)` unik, med resultatet av loot-roll och eventuell `instance_id`. Ger idempotens när en avslutad runda återförsöks. Behåll claim även när spelaren redan äger utfallet.

Behåll samma säkerhetsmönster som övriga migrationer: RLS på kontotabeller, inga direkta skrivgrants för klienten, smala `SECURITY DEFINER`-RPC:er med `set search_path = ''`, uttryckliga schemanamn och `auth.uid()` för ägare. Grant endast nödvändiga RPC:er till `authenticated`; `anon` får ingen inventory-åtkomst. Läsfunktioner ska returnera katalog, instanser, utrustning och saldo i ett konsistent svar. Föreslagna RPC:er: `get_my_inventory_state`, `purchase_item(p_item_id,p_request_id)`, `equip_item(p_instance_id,p_slot_type)`, `unequip_item(p_slot_type)`.

Gör **servern auktoritativ för köp, ägande och utrustning**. Klienten får cachea senaste bekräftade state per `user_id` för snabb visning, men cache är aldrig grund för köp eller equip. Vid inloggning, utloggning och kontobyte töms in-memory-state omedelbart innan nästa användares data hämtas. Vid nätfel visas ”Kan inte synka inventory” och ändringsknappar stängs av; senast bekräftade innehåll får visas som inaktuellt med märkning. Ingen optimistisk ägandeförändring.

Skapa en separat `InventoryService` autoload och en `SupabaseInventoryProvider` med egna `HTTPRequest`-objekt per läs-/skrivkanal eller en serialiserad begärandekö. Se till att de fortsätter processa när spelet är pausat. De ska använda befintlig `AuthService`-token och samma fel-/kontokontextskydd som `AccountProgress`. Efter köp uppdateras `AccountProgress.wallet_coins` från serverns svar via en tydlig metod eller gemensam progress-refresh, så saldot i konto-, shop- och karaktärsvy är identiskt.

### Fynd i rundor

Version 1 har en **generisk fynd-ikon/kista** på banan, inte ett klientvalt föremål. En separat `LootSpawnPlanner` får run-seed och egen salt/version. Den planerar sällsynta tillfällen enligt dataregler (till exempel tidigast efter 600 m, högst ett försök per 600–900 m, max två per runda). Den konsumerar aldrig `CourseGenerator`-RNG. Placera bara fynd där det inte överlappar hinder och där spelaren kan nå det; en misslyckad plats hoppas över. Ingen loot i demobakgrund eller gästrundor.

När spelaren tar ett fynd registrerar `RunState` ett index för den planerade pickupen. Visa ”Fynd väntar på sparning” under rundan. Vid run end skickas indexen i samma permanenta pending-run-post som redan innehåller `run_id`, distans och coins. Utöka run-RPC:n med ett versionssatt kontrakt, exempelvis `record_player_run_v2`, så coins, achievements och loot-claims sparas i **en transaktion**. Migrera den aktuella SQL-funktionens logik från `202609260006` utan att tappa hazard-/achievement-fälten. Ändra inte den gamla signaturen slarvigt så att PostgREST får tvetydiga överlagringar. Vanliga runddrops är tills vidare avstängda i spelklienten och dropptabellen; behåll stödet för framtida special-/eventfynd.

Servern validerar max antal, att pickup-index är unika och ligger inom rapporterad distans, samt rullar föremål från en serverägd drop-tabell med vikt/rarity och `drop_enabled`. Klienten skickar aldrig `item_id` eller rarity som belöning. Samma `(user_id, run_id, pickup_index)` ska ge samma svar vid återförsök och inte skapa dubletter. Om katalogföremålet redan ägs returneras `already_owned`. Vid misslyckad run-save ligger fyndet kvar som väntande, inte som användbart föremål. Återförsöket efter omstart måste hantera gamla köposter utan lootfält.

Nuvarande spelet litar redan på klientens rapporterade distans och coins. Denna första version kan validera ett rapporterat pickup-index men kan inte kryptografiskt bevisa att spelaren faktiskt rörde ikonen utan serverstyrd ban-/kollisionssimulering. Begränsningar och revisionsspår är tillräckliga för prototypen; tävlings-/ekonomibalansering kan kräva starkare servervalidering senare.

## Paus, spelinput och tävlingsregler

- Inför en liten pauskoordinator eller en mängd pausorsaker (`manual`, `character`, `shop`, `portrait`) i `PauseMenu`/ett gemensamt system. `get_tree().paused` blir sant om någon orsak finns. Porträttkontrollen tar bara bort sin egen orsak när telefonen roteras; den får inte återuppta en öppnad karaktärs- eller butiksvy. `PauseMenu` och båda overlays processar `ALWAYS`, spelvärlden fortsätter vara pausad. Bara en fullskärmsvy är aktiv åt gången; byte mellan Character och Shop behåller pausen och rätt återvändningspunkt.
- Stäng eller konsumera UI-input innan `Player._unhandled_input` kan tolka touch/klick som gravitationsbyte. Nuvarande `_is_pause_button_position()` är hårdkodad för en knapp; ersätt med faktisk UI-hitbox eller generell inputspärr för öppna overlays och de tre toppknapparna. Testa särskilt touch-`tap` och musstyrning.
- Inga utrustningsändringar under rundan. Snapshot sparas även som enkel `loadout_signature`/regelversion i lokal run-metadata. När modifierare väl påverkar fart/överlevnad ska publika topplistor och seed-utmaningar antingen använda standardiserad utrustning eller tydligt skilja resultat per regelklass. Rekommendation: håll tävlingsresultat standardiserade tills separata leaderboard-regler finns. Första neutrala föremålen påverkar inte jämförbarheten.
- Loot-fynd påverkar inte banans hinder eller seed-kodens reproducerbarhet. Coin-/lootutfall kan skilja mellan spelare även på samma kod och är inte del av distansjämförelsen.

## Genomförandeordning för en implementerande agent

1. **Grundmodeller och kontrakt:** dokumentera slot-/rarity-/stat-ID, skapa katalog och stat-resolver i GDScript med handgjorda fixtureföremål. Skriv meningsfulla tester för summor, ogiltiga modifierare och run-snapshot. Kör Godot-parser/testhubb innan UI byggs vidare.
2. **Databasmigration och API:** tabeller, constraints, RLS/grants, seeddata samt läs-, köp- och equip-RPC. Testa två olika konton, för lite coins, dubbla klick/samma `request_id`, två samtidiga köp, fel slot, främmande instans och utloggning under begäran. Uppdatera migrationsordning och installationsanvisning.
3. **Klientservice:** `InventoryService` + provider, autentiseringsväxling, laddnings-/felstatus, saldokoppling till `AccountProgress`, cache med kontokontext. Ett misslyckat nätanrop får inte ge lokalt ägande.
4. **Navigation och spelhub:** skapa en separat hubb efter Spela, flytta Challenges/Achievements/Topplistor dit, ge Starta runda visuell prioritet och placera två lika stora fyrkantiga ikonknappar för Character/Inventory och Shop längst ner i menypanelen. Använd utbytbara platshållarsymboler tills riktiga assets finns. Behåll direktlänkar till challenges och tydlig återgång från paus/slutvy. Provkör både gäst och inloggat konto så vägen till en vanlig runda inte blir längre än nödvändigt.
5. **Character/Inventory UI:** separata återanvändbara scener, ikon- och rarityvisning, statpanel, två utrustningsslots, 24-cells rutnät, val/equip/unequip i hubben, svensk/engelsk text och mobil-/desktoplayout. Verifiera visuellt vid 960×540 och smal mobilvy.
6. **Pausintegration:** karaktärs- och butiksikon i run-HUD, `I`, pausmenygenvägar och pausorsaker. Verifiera att run-timer, hinder, coins, `RunState`, spelaranimation och touchkontroller står still när en vy är öppen, medan HTTP-svar fortfarande kommer fram.
7. **Shop:** egen vy som delar katalog och itemkort med inventory, atomärt köp, saldouppdatering, ägd-status och felhantering. Samma vy fungerar i hubben och under paus; köp under paus ändrar inte aktiv run-snapshot. Provkör offline-/återförsök och byte mellan två konton.
8. **Fynd:** separat lootplanerare, pickupscen, pending-run-format, ny run-RPC med idempotent server-roll och UI för väntande/bekräftat fynd. Regressionstesta att samma seed ger exakt samma hindersekvens med och utan lootfunktionen.
9. **Slutkontroll:** Godot headless/parser och relevanta tester; SQL-migration på testdatabas; två konton, offline/online, dubbelpostad runda, logout mitt under kö/HTTP, desktop/mobil och seed-utmaning. Granska diffen så befintliga osparade projektändringar inte skrivs över.

## Klara acceptanskriterier

- Ett inloggat konto kan köpa en hjälm och ett par skor, se ikoner/rarity, utrusta dem och hitta samma state efter omstart och på en andra enhet.
- Ett annat konto ser inte, kan inte utrusta och kan inte köpa med det första kontots föremål eller coins. Dubbla köp och nätåterförsök drar coins högst en gång.
- Character visar korrekta grundstats och utrustningsbonusar enligt resolver; första katalogen påstår inte att neutral utrustning ger spelbonus.
- Inventory från en aktiv runda stoppar all gameplay och kan stängas utan att pausläget tappas. Utrustningen som rundan startade med är oföränderlig under rundan.
- Huvudmenyn är kort och leder via Spela till hubben. Hubben har separata, begripliga ikoner för karaktär/väska och butik. Båda kan också öppnas från rundans HUD; ett köp där ändrar bara kommande rundor. Vanliga rundor, challenge-länkar, retry och återgång från slutvyn når rätt läge.
- Ett fynd ger högst en serverbekräftad belöning per run/pickup-index även om samma avslutade runda skickas flera gånger. Väntande fynd hanteras efter nätavbrott.
- Samma seed och generatorversion ger samma hinder- och terränghändelser som före lootfunktionen. Publika resultat påverkas inte av de första neutrala föremålen.

## Medvetet senare arbete

Fler slots, drag och släpp, flera exemplar av samma föremål, procedurgenererade affixer, försäljning, crafting, förbrukningsvaror, visuell rustning på figur, achievement-belöningar och aktiva stat-/specialeffekter. De kan byggas ovanpå definition/instans/slot/stat-snapshot utan att ändra första versionens ägandeflöde.

### Parkerad idé: shop-progression och upplåsningar

Shoppen behåller tills vidare sitt nuvarande gemensamma utbud för alla spelare. Ändra inte köpflöde eller katalog som del av denna idélista. När shop-progression prioriteras, undersök ett datadrivet upplåsningssystem där nya föremål eller sortiment kan styras av flera typer av spelarframsteg:

- Hur mycket spelaren totalt har spenderat i shoppen.
- Försäljning av föremål tillbaka till shoppen, med en tydlig återköps-/guld-ekonomi.
- Roterande utbud, potentiellt med en tidsperiod eller annan bestämd rotationsregel.
- Uppnådda achievements.
- Löpframsteg, exempelvis längsta/totala distans eller sammanlagd tid i rörelse.
- Ytterligare upplåsningsvillkor som kan kombineras, så att nya items kan ha olika krav.

Börja med att bestämma om upplåsningar gäller per spelare och om rotationen är personlig eller gemensam. Visa låsta föremål och deras krav tydligt; servern ska vara auktoritativ för upplåsning, köp, försäljning och valuta. Ingen av punkterna ovan är implementerad eller ett krav för den nuvarande inventory-versionen.

## Referenser

- Tidigare idéer: `GAMEPLAY_IDEAS_AND_SEED_CHALLENGE.md` och `../IMPLEMENTATION_PLAN.md`.
- Godot, paus och process mode: https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html
- Supabase, RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase, databasfunktioner och `security definer`: https://supabase.com/docs/guides/database/functions
