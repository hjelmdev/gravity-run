# V2 r5: positionsströmmen använder en kanal som inte finns

Analys 2026-09-29. Underlag: host- och gästrapporterna för runda `6618e7596829167e9d98d24b339e0feb`, filnamn som slutar med `1790718649.json` respektive `1790718646.json`. Rapporterna kommer från r5. Den aktuella V2-worktreen innehåller även ändringar märkta r6; kanalfelet nedan finns fortfarande i den lästa koden. Spelkoden har inte ändrats i denna analys.

## 1. Slutsats och bevis

Det finns ett konkret transportfel som förklarar att båda spelarna lämnar den andra bakom sig på sin egen skärm. Positions-RPC skickas på logisk kanal **1**, men WebRTCMultiplayerPeer skapas utan extra kanaler. Start, kontrollmeddelanden och dödsrapporter använder kanal **0** och kan därför fungera ändå.

| Observation | Vad den säger |
| --- | --- |
| Båda börjar och avslutar samma runda; terminalrapporter når hosten. | Kontrolltrafiken fungerar. Att start lyckas bevisar inte att positionstrafiken fungerar. |
| Inga rapporterade peer-disconnects i denna runda. | Förra rundans länkavbrott är inte den observerade orsaken här. |
| Host: `samples_validated_host=217`. | Räknaren omfattar även hostens egna samples, som valideras med ett lokalt funktionsanrop. Den bevisar inte nätverksmottagning från gästen. Antalet stämmer med hostens egen 30 Hz-ström. |
| Guest: ingen `samples_presented_remote`-räknare. | Ingen accepterad remote-sample registreras via denna instrumentering. Loggarna mäter inte varje transportsteg, så de ensamma kan inte ange var paket försvinner. |
| Inga registrerade sample-rejections eller owner-mismatches. | Inget stöd i rapporterna för att mottagna rörelsepaket fastnar i dessa valideringar. |
| Host dör vid tick 436, guest vid tick 440; slutpositionerna skiljer cirka 3 pixlar. | De egna simuleringarna fortsätter ungefär tillsammans. Det stora synliga avståndet är inte motsvarande avstånd i deras lokala slutpositioner. |

Att båda dör vid samma hinder är förenligt med samma lokala bana och liknande rörelse. Det bevisar inte att de ser varandras positioner.

## 2. Exakt kodfel

Kodrot: `C:\Users\hjelm\.codex\worktrees\multiplayer-v2\Gravity Run\gravity-run`.

`systems/multiplayer_v2/v2_rpc_endpoint.gd:10`:

```gdscript
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_player_sample(sample: Dictionary) -> void:
```

`systems/multiplayer_v2/multiplayer_v2_service.gd` skapar transporten utan extra kanaler på samtliga lästa ställen:

- Rad 600: `webrtc_peer.create_server([])`.
- Rad 641: `webrtc_peer.create_client(assigned_peer_id)`.
- Rad 1632: `replacement.create_client(assigned_peer_id)` vid återskapande.

Godots standardkanal 0 väljer mellan tre reserverade underliggande kanaler efter transfer mode. Logisk kanal 1 är den första **extra** kanalen. Tre standardkanaler innebär alltså inte att RPC-kanalerna 0, 1 och 2 automatiskt finns.

Kommentaren vid rad 599 är också fel: argumentet till `create_server` är `channels_config`, inte ICE-servrar. ICE hör till WebRTCPeerConnection-konfigurationen.

Källor: [Godots WebRTCMultiplayerPeer-dokumentation](https://docs.godotengine.org/en/stable/classes/class_webrtcmultiplayerpeer.html), [motorns kanalval och bounds-kontroll](https://raw.githubusercontent.com/godotengine/godot/master/modules/webrtc/webrtc_multiplayer_peer.cpp). Den senare länken avser master; beteendet har därför också kontrollerats i den lokala motorn nedan.

### Reproduktion i faktisk Godot 4.7.2

Ett isolerat test använder motorns WebRTCMultiplayerPeer och mockade underliggande WebRTC-anslutningar. Med standardkonfiguration och transfer channel 1 returnerar motorns `put_packet`:

```text
DEFAULT actual channels=3
ERROR: Unable to send packet on channel 3, max channels: 3
CHANNEL 1 default config error=31 expected ERR_INVALID_PARAMETER=31
EXPLICIT channel 1 config actual channels=4
```

"channel 3" är här den interna kanalen som logisk RPC-kanal 1 mappas till. Testet verifierar motorns kanalgräns och att explicit konfiguration skapar en extra kanal. Det verifierar inte verklig nätverksleverans eller rendering.

Testet finns i `E:\Utveckling\Gravity Run\.codex-v2-analysis\channel-probe\probe.gd` och kördes med `Godot_v4.7.2-stable_win64_console.exe --headless --path <testkatalog> --script res://probe.gd --quit-after 2`.

## 3. Varför motspelaren försvinner

I `ui/multiplayer_v2/multiplayer_v2_match.gd:400` börjar `_player_render_pose` med manifestets startposition. För en remote-spelare ersätts positionen av remote-track-data när sådan finns. Utan dessa samples blir figuren kvar vid start medan den egna spelaren och kameran fortsätter framåt. `_sync_player_views`, rad 436, döljer sedan figuren när den hamnar utanför bildområdet.

Det stämmer med att var och en ser sig själv springa vidare och den andra falla ur bild. Dödsrapporter kan fortfarande nå fram via den fungerande kontrollkanalen.

## 4. Rekommenderad implementation: minsta rättningen först

### Steg A: använd standardkanalen för rörelse

Ändra bara kanalvalet för `submit_player_sample`:

```gdscript
@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func submit_player_sample(sample: Dictionary) -> void:
```

Behåll `unreliable_ordered`. Kanal 0 använder olika reserverade underliggande kanaler för reliable och unreliable_ordered, så kontrolltrafiken gör inte rörelseströmmen reliable. Behåll nuvarande 30 Hz tills verklig mottagning är verifierad.

Rätta kommentaren om `channels_config` och ICE. Sök igenom alla V2-RPC:er och peer-konstruktioner för andra kanalval utan motsvarande konfiguration. V1 ska behållas separat.

**Alternativ endast om en extra kanal behövs:** behåll logisk kanal 1 och ange `[MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED]` i hostens, gästens och replacement-klientens konstruktion. Centralisera konfigurationen så att återanslutning inte återinför felet. Välj en strategi; rekommendationen för denna rättning är kanal 0.

### Steg B: gör misslyckad skickning synlig

`send_sample` och `send_sample_to_peer` ignorerar idag returvärdet från `.rpc()`/`.rpc_id()`. Låt wrappern returnera `Error` och låt anroparen registrera fel.

- Räkna `sample_send_attempts`, `sample_send_errors` och lyckade anrop separat. `OK` betyder att skickanropet accepterades, inte att mottagaren tog emot paketet.
- Logga första felet med error-kod, målpeer, kanal, transfer mode, round-id och sequence. Begränsa upprepningar; undvik en logghändelse för varje fysikframe.
- Dela upp lokal host-validering och verkligt mottagna nätverkssamples.
- Redovisa mottagna, accepterade och avvisade samples per spelarägare och transportavsändare, inklusive avvisningsorsak.
- Redovisa track-insertions, senast renderad sequence och sample age per remote-spelare. Exponera om track saknar data; en statisk startposition får inte maskera saknad ström i diagnostiken.

### Steg C: testa hela kedjan i två riktningar

Verifiera för varje fjärrspelare: skickanrop → mottagen RPC → ägarvalidering → remote-signal → track-insertion → ändrad renderposition.

Använd två verkliga browserklienter i samma exporterade build. Kör dem levande i minst fem sekunder på en bana där de inte omedelbart dör. Vid 30 Hz ska båda normalt hinna få över 100 accepterade samples från den andra i detta lokala test. Om inte: redovisa exakta räknare, fel och mottagningsluckor, inte enbart "P2P connected".

Gör därefter olika gravitationsbyten på klienterna. Den andra figuren ska tydligt återge rörelsen. Två figurer som råkar springa likadant är inte tillräckligt som leveransbevis.

### Steg D: tre spelare, död och ny runda

- Med host och två gäster: varje klient ska få uppdateringar för båda fjärrspelarna, även guest→guest via hostens relay där den används.
- Behåll skillnaden mellan transportavsändare och spelarägare när hosten reläar ett redan validerat sample. Lätta inte godtyckligt på ägarkontroller för att få relätrafiken att fungera.
- Låt hosten dö först, sedan en gäst: kamerorna ska följa den levande spelarens uppdaterade track. Verifiera samples även när hostens egen figur är död.
- Verifiera gemensamt slutresultat och minst tre nya rundor utan omladdning. Gamla round-id:n och tracks får inte återanvändas.
- Kontrollera även resultatvyns statusrad: screenshot visar "Waiting for host result..." samtidigt som slutresultatet redan visas. Det är en separat UI-avvikelse att rätta efter transportfelet.

## 5. Krav innan rättningen kallas klar

1. Kanalreproduktionen för felkonfigurationen finns kvar som dokumenterat bevis; vald korrekt konfiguration får inte ge invalid-channel-fel.
2. Båda verkliga klienterna har accepterade remote-samples och ändrade remote-renderpositioner, med räknare per ägare.
3. Treklienttestet visar guest→guest-rörelse, fungerande spectating efter hostens död och gemensamt avslut.
4. JSON-exporterna anger samma nya build på samtliga klienter och innehåller de nya transport- och renderingsräknarna.
5. Agenten lämnar exakta testutfall och anger uttryckligen om browser- eller treklienttest inte kunde köras. Ett headless-test av hostens egna samples räcker inte.

Kanalfelet är verifierat och måste rättas. Efter det kan andra rörelse- eller interpolationsproblem fortfarande återstå; de ska då lokaliseras med fungerande mottagning och mätbara remote-tracks. Att höja sändfrekvensen löser inte skickning på en kanal som saknas.
