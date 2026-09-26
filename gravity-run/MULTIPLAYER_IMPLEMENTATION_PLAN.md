# Multiplayer med lobby och gemensam bana – genomförandeplan

## Syfte och första spelbara version

Spelare på olika enheter ska kunna skapa eller gå med i en privat lobby med kod, invänta varandra och starta en samtidig runda på **en och samma ändliga bana**. Banan ska vara färdigplanerad i lobbyn och levererad samt verifierad av alla anslutna klienter innan nedräkningen får börja. Varje spelare ser sin egen helskärmsvy, sin gubbe och andra spelares gubbar när de är inom kamerans område; HUD visar placering och avstånd även när de inte syns i bild.

**Beslutat för första versionen:** den ska fungera över internet i webbläsare på både dator och mobil, ha en ändlig bana och avgöras av vem som kommer först i mål. Planens föreslagna startvärden är 2–4 spelare, privat rumskod och en död som innebär utslagning ur den rundan. **Vald första arkitektur:** ingen egen ständigt körande Godot-server och inget TURN-relä. En spelare är värd för sin match; Supabase sköter enbart lobby och WebRTC-signalering. WebRTC försöker ansluta direkt med STUN som hjälp. Om direktanslutning misslyckas kan den spelarkombinationen inte starta en match i första versionen.

Första versionen har inga varv, respawn, liv, PvP-föremål, boosts, publikt matchmakingflöde, kontokrav eller permanenta multiplayerresultat. Dessa får däremot tydliga modellgränser så de kan läggas till utan att lobby-, ban- och nätverksprotokollet måste skrivas om.

## Varför arbetet inte kan läggas direkt i `main.gd`

- `main.gd::_physics_process()` ökar `course_distance` för **en** spelare, flyttar hinder/terräng åt vänster och håller spelaren vid `PLAYER_X`. Det är ett kameratrick för singleplayer, inte en gemensam världskoordinat. `main.gd::_run_speed()` använder redan `player.get_speed_multiplier()`, så befintliga fartökningar får banan att rulla förbi snabbare. Men en spelare kan inte springa ifrån en annan i en gemensam värld så länge de saknar varsin absolut X-position. **Bygg därför om singleplayer först:** spelaren får `world_x` som faktisk position, hinder/terräng ligger kvar vid absoluta X-positioner och kameran följer spelaren. Samma rörelsemodell återanvänds sedan i multiplayer. Renderad X-position för en annan spelare kan vara `PLAYER_X + other.world_x - local_player.world_x`.
- `CourseGenerator` planerar redan deterministiska event med fast referensgeometri. `CourseRunDefinition` binder seed, generatorversion och regler. Återanvänd dessa för att bygga en ändlig manifestfil i lobbyn. Nuvarande generatorversion i kod är **3**; äldre anteckningar om `GR2` får inte användas som hårdkodat multiplayerkontrakt.
- `main.gd::_sync_screen_size()` skalar terräng och spelarens Y efter skärmhöjd. Det kan göra kollisioner olika på mobil och dator. Auktoritativ simulering måste använda en fast världsgeometri som är oberoende av skärmstorlek; viewportstorlek får bara påverka kamera, skalning och UI. Detta är också en singleplayerförbättring och ska ingå i refaktoreringen innan multiplayer byggs.
- `_spawn_ledge()` och `_spawn_course_slope()` härleder faktiska Y-nivåer från tidigare terräng och `screen_height`. Manifestet måste därför innehålla **slutligt lösta** terräng- och hinderkoordinater i en fast spelvärld, inte bara råa RNG-event. Två klienter med olika skärmformat ska aldrig beräkna olika kollisionsgeometri.
- `main.gd::_spawn_coin_row()` har ett annat slumpflöde än hinderplaneringen. Stäng av coins och belöningar i den första tävlingsrundan tills deras ägande och validering har egna regler.
- Menyn i `ui/main_menu.gd` är redan stor. Multiplayer ska få egna scener och en liten ingång från huvudmenyn. Singleplayer och seed-utmaningar ska fortsätta använda sina befintliga vägar.

## Arkitektur och förstudie utan egen matchserver

**Målalternativ A – värdspelare + WebRTC:** varje kompisgäng har sitt eget rum. En spelare i rummet är auktoritativ värd, genererar banan, simulerar matchen och skickar snapshots till övriga. Supabase lagrar kortlivad lobbyinformation och vidarebefordrar WebRTC:s offer/answer/ICE under anslutningen; speltrafiken går sedan över WebRTC-data channels mellan värden och varje klient. Godot 4.7 har `WebRTCMultiplayerPeer.create_server()`/`create_client()` för denna topologi i webbläsaren. Ingen Godot-process behöver hållas igång av oss. Detta är **P2P med en spelare som värd**, inte att varje klient själv får bestämma sitt resultat.

**Ej valt för första implementationen – Supabase Broadcast för all speltrafik:** samma auktoritativa värd men alla snapshots går via Supabase Realtime. Det kan fungera som prototyp, men varje meddelande går via tjänsten och räknas per leverans. Exempel: en värd sänder ett samlat snapshot 15 gånger/s i ett rum med fyra spelare; en sändning plus tre mottagningar ger ungefär 60 Realtime-händelser/s för **ett** rum, innan input och lobbytrafik. Två sådana rum kan därmed passera Supabases dokumenterade Free-gräns på 100 meddelanden/s för hela projektet. Detta är en beräkning utifrån deras räkneregel, inte ett uppmätt resultat. Håll därför spelpositioner utanför Supabase i första versionen.

**Kostnadsbild (kontrollerad 2026-09-26):** Supabase Free inkluderar 2 miljoner Realtime-meddelanden per månad och 200 samtidiga anslutningar, utöver gränsen på 100 meddelanden/s. Vid ovanstående *illustrativa* 60 meddelanden/s skulle 2 miljoner räcka ungefär 9,3 timmars sammanlagd aktiv matchtid per månad, före övrig trafik. Den valda signaleringsvägen använder däremot meddelanden främst vid lobbyanslutning; mät faktiskt antal i prototypen. Free har ingen debiterad överanvändning, men funktionen kan begränsas eller få fel när gränserna nås. Ingen TURN-tjänst ska konfigureras i första versionen.

**Reservalternativ C – egen dedikerad matchserver:** om WebRTC inte fungerar tillförlitligt bakom vanliga hem-/mobilnät, om TURN-relä blir nödvändigt i stor omfattning, eller om värdens frånkoppling/fusk blir ett kravproblem. En serverprocess kan hålla **många separata rum och matcher samtidigt** i minnet, med ett `MatchRoom` per rum; man behöver inte en server per kompisgäng. Två eller tre gäng betyder normalt två eller tre rum i samma process. Antal servrar styrs först av mätt kapacitet, geografisk latens och driftsäkerhet, inte av antalet rum ett till ett.

Med reserv C ansluter alla webbläsare utåt till serverns `wss://`-adress. Då används inte WebRTC mellan spelarna och därmed behövs varken dess offer/answer-signalering, STUN eller TURN för matchtrafiken. Servern löser däremot inte all latens: trafik tar en omväg via servern, WebSocket använder tillförlitlig TCP och servern måste drivas, övervakas och kunna nås. För en framtida dedikerad browser-server är WebSocket/WSS ett möjligt första val; ENet/UDP är inte direkt tillgängligt för Godots webbexport.

**Första tekniska grind:** bygg en liten webbaserad tvåspelarprototyp som använder Supabase för rums-/signalmeddelanden och WebRTC-data channel utan TURN. Testa olika nät: två hemnät, mobilnät ↔ hemnät, mobilnät ↔ mobilnät. Mät andelen lyckade anslutningar, uppkopplingstid, RTT och jitter. Dokumentera vilka nätkombinationer som inte fungerar, men fortsätt med vald arkitektur så länge den ger ett användbart första vänläge. Om misslyckandena blir för många tas ett nytt produktbeslut om TURN eller dedikerad server; ingen sådan tjänst införs automatiskt.

Godots WebRTC i webben finns inbyggt; en framtida native-export behöver separat WebRTC-GDExtension. Första versionen använder signalering via Supabase och STUN för direktanslutning, **utan TURN**. Använd ett versionssatt protokoll oberoende av vald transport, så banmanifest och matchregler inte behöver skrivas om vid ett senare byte. En mobil webbläsare kan pausa en bakgrundsflik; testa därför särskilt vad som händer när **värdens** telefon låses eller appen byts under en match.

**Begrepp:** STUN hjälper webbläsaren att upptäcka vilken extern nätadress den kan nås via. TURN är en mellanhand som vidarebefordrar själva spelpaketen när en direkt WebRTC-väg inte går att få fram. TURN är alltså inte matchens auktoritet och kör ingen Godot-fysik; värdspelaren gör fortfarande det. Relätrafik kan ge extra fördröjning och separat trafikkostnad. En dedikerad Godot-server är i stället själv matchens auktoritet och destination för alla klienter.

### Systemdelar som implementatören ska skapa

| Del | Ansvar |
| --- | --- |
| `MultiplayerService` autoload | Anslutning, protokollversion, återanslutningsstatus, rumstillstånd och signaler till UI. |
| `MultiplayerLobby` scen | Skapa/gå med via kod, spelarlista, banförberedelse, redo-status, start/avbryt och felmeddelanden. |
| `MultiplayerMatch` scen | Lokal input, rendering av alla gubbar, kamera, HUD och resultat; ingen direkt databaslogik. |
| `LobbyProvider`/Supabase-RPC | Atomiskt skapa/gå med/lämna rum, rumskod, ägaridentitet, kapacitet, TTL och versionskontroll. |
| `SignalingTransport` | Utbyte av WebRTC offer/answer/ICE via ett rumsspecifikt Realtime-ämne; får inte användas för fysikpositioner i alternativ A. |
| `WebRTCMatchTransport` | En värd som peer 1, klienter som övriga peers, tillförlitlig kanal för banmanifest/händelser och lågfördröjd kanal för snapshots/input. |
| `MatchRoom` | Logisk lobbyfas, ägare/värd, spelare, fryst banmanifest, nedräkning, matchtillstånd och slutresultat. Körs hos värden; Supabase håller bara kortlivad upptäckt/medlemskap. |
| `CourseManifestBuilder` | Tar ett `CourseRunDefinition` plus banlängd och bygger ordnade statiska banevent, start och mållinje. |
| `MultiplayerSimulation` | Världskoordinater, spelarinput, rörelse, kollisioner, död och mål i fast tick hos värden; utan HUD/kamera. |
| `NetworkPlayerView` | Interpolerar andra spelare och visar dem relativt lokal kamera. |

### Vad signalering betyder i denna plan

WebRTC vet inte automatiskt hur två webbläsare hittar varandra. I ett rum skickar den anslutande spelaren ett **offer** till värden via Supabase Broadcast; värden skickar ett **answer** tillbaka; båda skickar därefter sina **ICE-kandidater** via samma kanal. Kandidaterna beskriver möjliga direkta nätverksvägar, med STUN som hjälp; ingen TURN-kandidat konfigureras. När WebRTC:s data channel är öppen går banmanifest och spelmeddelanden där, inte via Supabase. Signalmeddelanden ska adresseras till ett bestämt peer-ID och innehålla rums-/match-ID, anslutningsförsökets ID, avsändaridentitet, typ och utgångstid; gamla eller främmande meddelanden ignoreras. Detta kan byggas i Godot och Supabase utan en egen alltid påslagen signalserver, förutsatt att rumsbehörighet och protokolltesterna lyckas.

## Bannivå och leverans före start

1. När ett rum skapas väljer värdspelaren ett `CourseRunDefinition` med seed, aktuell generatorversion och tillåtet multiplayerregelpaket, plus en fast `course_length_px`. Lås regelpaketets fingerprint och en separat `match_rules_version`. Supabase lagrar identiteten och statusen för upptäckt; värden äger matchens exakta innehåll.
2. Värden bygger banan i bakgrunden medan lobbyn visas. Börja med ett kort, fast målspann som ger ungefär 60–90 sekunders körning i normalfart; kalibrera exakt pixelvärde efter speltest. Använd samma befintliga `CourseGenerator`, men tillåt i första omgången en begränsad uppsättning **statiska** event som är meningsfulla i tävling. Rörliga tunnor, coins, slumpade belöningar och föremål väntar tills värden kan äga deras tillstånd.
3. Byggaren producerar ett **kanoniskt manifest**: protokoll-/banformatversion, `course_identity`, banlängd, fasta världs-/fysikmått, ordnade event med stabila `event_id`, typ, absolut X/Y, lösta terrängytor, mått och nödvändiga parametrar. Begränsa antal event och meddelandestorlek. Hasha en dokumenterad kanonisk serialisering, inte osorterad `Dictionary`-JSON.
4. Värden sänder hela manifestet till varje spelare över en tillförlitlig WebRTC-kanal, vid behov i numrerade delar med totalstorlek, delantal och hash. Klienten assemblerar, kontrollerar storlek/schema/version/hash och bygger lokal terräng och kollisionsvärld. Klienten returnerar `course_loaded(match_id, manifest_hash)` först när scenen är färdig. Ett matchande seed är alltså **inte** det enda startvillkoret; leverans och faktisk laddning kvitteras.
5. Nya spelare får gå med medan rummet är öppet och får samma frysta manifest. Om banregler eller längd ändras före start skapas ett nytt manifest-ID; alla gamla `ready` och `course_loaded` blir ogiltiga. Ingen sen anslutning efter att nedräkningen låsts i första versionen.
6. Värden godtar `start_request` endast från rummets ägare, med minst två spelare och när alla anslutna har kvitterat **samma** manifest och markerat sig redo. Värden skickar en tidsstämplad starttick/nedräkning. Klienternas lokala knapptryck startar aldrig matchen direkt.

Även om värden skickar hela manifestet är seed, generatorversion och regler värdefulla: de beskriver hur den gemensamma banan skapades, möjliggör reproduktion och ger en stabil identitet. Under själva rundan är det värdens **frysta manifest** och auktoritativa tillstånd som gäller.

## Lobbyflöde och tillståndsmaskin

`CREATED → PREPARING_COURSE → OPEN → COUNTDOWN → RUNNING → FINISHED → CLOSED`.

- **Create:** en atomisk Supabase-RPC reserverar en svårgissad rumskod, ägaridentitet och TTL. Visa kod och kopierbar inbjudan; dela inte interna anslutnings-ID i UI. Samma kod får inte krocka med aktivt rum.
- **Join:** klienten anger kod och visningsnamn. Supabase-RPC kontrollerar kod, fas, kapacitet, protokoll-/spel-/generatorversion och namnformat; värden godkänner peer-anslutningen mot rumsmedlemskapet. Gäster får spela; konton kan mappas senare utan att nickname blir säker identitet.
- **Preparing/Open:** visa vilka som är anslutna, vem som har laddat banan, vem som är redo och eventuella fel. Supabase-medlemskapet används för upptäckt, men värden bekräftar den faktiska WebRTC-anslutningen och redo-statusen. Endast ägaren kan starta eller ändra inställningar. Spelare kan lämna frivilligt.
- **Misslyckad direktanslutning:** försök igen en begränsad gång med nytt WebRTC-anslutningsförsök. Om data channel fortfarande inte öppnas får spelaren ett begripligt besked, exempelvis ”Kunde inte ansluta direkt till värden från det här nätverket”, och kan prova ett annat nät eller låta en annan vän skapa rummet. Visa inte spelaren som redo och starta inte en match som saknar en förväntad peer. Logga anonym teknisk felkod för felsökning.
- **Countdown:** lås medlemslista och manifest. Om en spelare försvinner före start avbryts nedräkningen och rummet återgår till `OPEN`; alla återstående behåller samma manifest men måste bekräfta sin redo-status på nytt.
- **Running:** sen join avvisas. Vid klientfrånkoppling får spelaren en kort återanslutningsfrist knuten till sin rumsidentitet; annars räknas spelaren som bruten/utslagen. Ingen annan kan ta platsen under pågående runda. **Om värden försvinner avslutas första versionens match för alla med tydligt felmeddelande och utan officiellt resultat.** Värdmigrering är en senare funktion, inte ett dolt antagande.
- **Finished/Closed:** värden skickar slutlig ordning och orsak per spelare. Lobbyn kan välja `spela igen` genom ett nytt match-ID och nytt manifest; gamla meddelanden får inte påverka nästa runda. Tomma rum och gamla tokens rensas med TTL.

Alla meddelanden ska innehålla `protocol_version`, `room_id`, `match_id` där relevant, `sequence` eller tick för ordning och ett uttryckligt fel-ID vid avslag. Hantera dubbla/omordnade meddelanden idempotent. Versionsfel ska få en begriplig uppdateringsuppmaning. En gissad rumskod får inte ensam ge rätt att skicka WebRTC-signaler eller matchinput som någon annan spelare.

## Spelsimulering och realtidsuppdatering

- Kör matchen hos värden i en **fast fysiktick**. Värden äger starttick, absolut X/Y, hastighet, gravitationsriktning, cooldown, status (`active`, `dead`, `finished`, `disconnected`) och eventuell framtida effektlista. Klienten skickar *avsikt* (`flip_up`, `flip_down`) med inputsekvens och tick, aldrig påstådd position, död eller målgång.
- Extrahera rörelse- och kollisionsregler ur `main.gd`/`player.gd` så värd och klient använder samma formler. All auktoritativ kollision beräknas i fasta världskoordinater och referensmått, oberoende av mobilens aspect ratio. Inga viewportbaserade y-skalningar får ändra banans fysik.
- Värden skickar kompakta snapshots med tick, spelarnas `world_x`, Y, vertikal fart, gravitationsriktning, status och aktiva effekter. Börja med mätbara 10–20 snapshots/s och 60 simuleringstick/s, men gör talen konfigurerbara. Skicka diskreta händelser (död, mål, banändring) på tillförlitlig kanal eller i återkommande state tills mottagna.
- Lokal spelare ska få omedelbar respons på input med klientprediktion, sedan korrigeras mjukt mot värdens bekräftade tick. Andra gubbar interpoleras mellan snapshots med liten buffert; extrapolera kort och stoppa därefter i stället för att låta dem springa iväg. Lägg in utvecklaroverlay för RTT, snapshotålder, korrigeringar och anslutningsfel.
- Klienten renderar världen med en lokal kamera relativt **sin egen** `world_x`; andra spelare ritas vid deras absoluta koordinater. Spelare utanför bild visas med avstånd/placering i HUD. Ingen delad skärm krävs på separata enheter.
- Värden validerar inputfrekvens, cooldown, maxfart och möjliga tillståndsövergångar. Andra klienter får inte bestämma slutresultat. **Värden kan själv fuska eller rapportera ett falskt resultat**; därför är första versionens utfall ett vänskapsresultat utan belöningar, publika topplistor eller kontoekonomi. Mät CPU, bandbredd och fördröjning innan snapshotfrekvens eller transport byts.

### Matchregler i första versionen

Rekommenderad enkel regel: alla startar samtidigt vid samma startlinje; första **levande** spelaren som når mållinjen vinner, övriga kan få placering när de når mål. Död utan liv ger status `dead` och ingen respawn. Matchen slutar när alla har nått mål/dött/brutits eller en tydlig sluttidsgräns uppnås. Om alla dör före mål visas `ingen vinnare`. Separera denna logik i en `RaceRules`-klass från generering och nätverkskod.

## Utbyggnad som modellen ska tåla

- **Flera liv/respawn:** lägg `lives_remaining`, respawnpunkt, respawn-tick och invulnerabilitet i auktoritativt spelartillstånd. Död är då en händelse, inte alltid matchslut. Respawnpunkt ska väljas från säkra, definierade positioner i manifestet.
- **Boosts och bromsar:** representera dem som tidsbegränsade, identifierade `StatusEffect` med källa, starttick, sluttick och modifierare. Värden räknar fram fart; banplanerarens maxfart/säkerhetsmarginal måste ta hänsyn till högsta tillåtna boost.
- **PvP-föremål:** separera `ItemDefinition` från värdstyrd `ItemInstance`/pickup. Projektiler/fällor får stabilt entity-ID, ägare, position, utlösningstid och träffhändelse. Banan är fortfarande samma för alla, men dynamiska föremål måste synkas från värden. Ingen klient får skapa en träff eller ett bananskal genom att bara rapportera den som sann.
- **Alternativa vinnarmål:** regelklass/versionssatt `MatchRules` för `first_to_finish`, `last_alive`, `laps` etc. HUD och resultat använder regeln och hårdkodar inte bara distans.
- **Varv/loop:** om samma sekvens ska upprepas, använd `lap_index` plus position inom varvet och en monoton totaldistans. Manifestet behöver definiera säker övergång från mål till start; loopa inte bara renderade sprites.
- **Bestående resultat:** läggs till först när en betrodd auktoritet kan verifiera matchen. En P2P-värd är en vanlig spelklient och kan inte själv ge ett fuskresistent officiellt resultat. Återanvänd inte klientens seed-score-RPC som auktoritativ multiplayerplacering.

## Genomförandeordning för implementationsagent

1. **Nätverksförstudie utan TURN:** bygg ett tunt WebRTC-experiment i Godot-webbexport med en värd och en klient; använd Supabase Broadcast enbart som offer/answer/ICE-kanal. Testa minst två separata hemnät samt mobilnät. Dokumentera anslutningsgrad, uppkopplingstid, RTT, jitter, felorsaker och Supabase-händelser/s med två och tre samtidiga rum. Om vissa nätpar inte ansluter, dokumentera begränsningen och den begripliga UI-felvägen; inför inte TURN eller server i detta steg.
2. **Singleplayer med verklig framåtposition – obligatorisk före matchimplementation:** bryt ut bana, rörelse och kollision från skärmförflyttningen. Låt `player.world_x` öka med faktisk fart och speed multiplier; placera hinder och terräng på absoluta X-koordinater, och låt kameran följa i stället för att flytta fysikvärlden. Behåll samma upplevda spelkänsla, hinderavstånd, distansmätning och touchstyrning. Testa en vanlig runda och en fartboost: gubben ska nå ett fast hinder/mål snabbare med boost, medan hindret har samma världsposition. Testa samma kollisionsfall i 960×540 och mobilformat.
3. **Kontraktsprototyp:** skapa `MatchRules`/`CourseManifest` och en deterministisk manifestbyggare för en kort bana. Kör samma definition två gånger, kontrollera samma event/hashes, olika seed → annat manifest, och verifiera begränsade regler. Bestäm första tillåtna eventtyperna genom speltest.
4. **Lobby och behörighet:** skapa Supabase-migration/RPC för rum och medlemskap med atomisk kapacitetskontroll, kortlivade poster, TTL och host-ägarskap. Gör privat Realtime-signalering som bara rumsmedlemmar kan läsa/skriva. Gästidentitet kräver ett medvetet val: Supabase anonym Auth kan ge stabilt `auth.uid()` för rummet, men påverkar befintliga RLS-regler eftersom sådana användare får rollen `authenticated`; granska alla befintliga policyer före aktivering. Testa att en obehörig klient inte kan lyssna, gå med eller spoofa värden.
5. **WebRTC-anslutning och manifest:** värd `create_server()`, klient `create_client()`, Supabase-signalering, STUN-konfiguration **utan TURN**, säkra och begränsade återförsök, chunkad manifestöverföring, hashkontroll, `course_loaded`, redo och värdstyrd start. Start ska nekas om en enda klient saknar rätt manifest eller direkt WebRTC-anslutning.
6. **Match med två spelare:** fast värdtick, input, snapshots, lokal prediktion, interpolerade motståndare, kamerarelativ rendering, död, mål och resultat. Testa först två webbläsarfönster och sedan två verkliga enheter på olika nät.
7. **Internetverifikation och justering:** webbläsare på dator och mobil, olika aspektförhållanden, mobilnät/Wi-Fi, tre/fyra spelare, hög RTT och jitter, anslutning som tappas före/under match, bakgrundslagd flik/låst telefon hos värden, **tre samtidiga rum**, olika klientversioner samt omspel. Kontrollera att alla anslutna ser samma manifest, hinder, gubbar och slutresultat. Dokumentera andelen nätkombinationer som inte kan ansluta utan TURN och mät Supabase-användningen före publik lansering.

## Godkännandekriterier

- Två till fyra vänner kan skapa/gå med i ett privat rum via kod från separata enheter, se varandra i lobbyn och markera redo.
- Värden väljer **ett** banmanifest. Varje klient måste ladda och kvittera samma hash innan ägaren kan starta; fel hash/version stoppar start med begripligt fel.
- Start/nedräkning kommer från värden. Alla ser samma banhinder på samma absoluta positioner trots olika skärmstorlek.
- Varje spelare styr sin egen gubbe. Andra spelare syns i banan när de är inom kameran; HUD visar övriga när de är utanför bild.
- Värden avgör död, mål och slutordning. Alla klienter visar samma slutresultat. Ett rums frånkoppling eller ogiltig input får inte stoppa andra rum.
- Singleplayer använder verklig framåtposition även utan nätverk. En speed multiplier ändrar spelarens hastighet mot fasta banpositioner och inte bara visuell scroll. Singleplayer, seed-utmaningar och nuvarande webbexport fungerar fortfarande efter refaktoreringen.

## Öppna beslut innan implementation låses

1. **Beslutat:** första leveransen ska kunna spelas över internet i webbläsare på mobil och dator. LAN är bara första tekniska testmiljö.
2. **Beslutat:** första rundan har ändlig bana och vinnaren är först i mål. Antalet liv före utslagning är ett separat, senare regelval; planen föreslår ett liv initialt.
3. **Beslutat:** första versionen konfigurerar ingen TURN-tjänst. Mät vilka hem- och mobilnät som inte kan etablera en direkt WebRTC-anslutning trots STUN. Dessa användare får ett tydligt anslutningsfel och kan prova att byta nät eller värd.
4. **Reservdrift:** om en dedikerad server senare behövs, välj leverantör först då. En process kan driva många `MatchRoom`-instanser; kapacitet och geografisk latens avgör när fler instanser krävs.

## Källor

- Godot 4.7, [high-level multiplayer och säkerhetsmodell](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html).
- Godot 4.7, [WebSocket i webb- och native-exporter](https://docs.godotengine.org/en/4.7/tutorials/networking/websocket.html) och [WebSocketMultiplayerPeer](https://docs.godotengine.org/en/4.7/classes/class_websocketmultiplayerpeer.html).
- Godot, [headless/dedikerad server](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html).
- Godot, [WebRTC och signalering](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html).
- Godot 4.7, [WebRTCMultiplayerPeer server-/klientlägen](https://docs.godotengine.org/en/4.7/classes/class_webrtcmultiplayerpeer.html).
- Supabase, [Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast), [gränser](https://supabase.com/docs/guides/realtime/limits), [auktorisering](https://supabase.com/docs/guides/realtime/authorization) och [anonym Auth](https://supabase.com/docs/guides/auth/auth-anonymous).
