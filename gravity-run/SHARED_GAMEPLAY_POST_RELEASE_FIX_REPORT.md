# Shared gameplay follow-up release report

Datum: 2026-10-02. Feature implementation: `fa57a86`. Synlig projektversion: `2026.10.02-shared-run-hud-fix` (`b497622`). Ingen generator-, physics- eller backendversion ändrades i denna release.

## Ändringar

- Multiplayercoins delas nu mellan den faktiska service-/world-ledgerkedjan och presentationen. När servicen redan har applicerat en bekräftad WORLD_COMMIT får matchvyn ändå spela den befintliga coin-insamlingseffekten för `duplicate`-resultatet. Leveransdubletter animeras inte igen. Ingen extra wallet-/ledgerutbetalning görs av presentationen.
- SP:s streamingplan och MP:s manifest använder samma v8-regler och coinplanner. Mätningen hittade ingen skillnad i genererade eller presenterade coins/hazards; därför ändrades inte täthetsvärden.
- SP och MP använder samma `SharedRunHud`-scen för namn, mynt och musikreglage. SP behåller distans och sina befintliga menyåtgärder; MP döljer distans och behåller nätverks-/resultatfunktioner. Det tomma seed-/leaderboard-meddelandet är borttaget. Volymreglagets expanderikon ritas som vektor och har inte längre beroende av en teckenglyf.
- Diagnostikexportens kompakta kurssnapshot rapporterar generator/version, räknare för planerade och presenterade objekt, coinernas synlighet och upp till 12 stenars kursposition samt varnings-/falltick. Snapshot tas endast vid export, inte per frame.

## Riktad verifiering

- `coin_match_commit_integration_test.tscn`: PASS. Testet driver gästens riktiga servicehantering av WORLD_COMMIT vidare genom servicesignal, matchens commit callback och den verkliga coin-scenen. Samma insamlingseffekt spelas efter service-side `duplicate`-applicering, men inte igen för duplicerad commit; winner-/ledgerdata ändras inte av effekten.
- `shared_coin_mode_parity_test.gd`: PASS över 45 000 px med inkrementella SP-chunks och MP:s riktiga manifest/presentation:

  | Seed | Planerade/presenterande coins SP=MP | Hazards SP=MP | Längsta coin-gap |
  |---:|---:|---:|---:|
  | 100000014 | 198 | 48 | 1 250 px |
  | 100000042 | 174 | 59 | 4 942,9 px |
  | 100001918 | 180 | 52 | 5 092,1 px |

- `singleplayer_rock_v8_runtime_test.gd`: PASS genom riktiga SP-scenen; challenge `GR8-100000000` visade dormant, warning, falling och buried och stenen låg kvar som hinder.
- `shared_rock_v8_tick_parity_test.gd`: PASS. Host och guest nådde buried vid samma tick (169) med samma permanenta hitbox. V8-eventet har `warning_ticks=104` (1,73 s) och `fall_ticks=42` (0,70 s); renderade inställningar kommer från gemensamt event, inte lokal MP-fysik.
- `shared_run_hud_scene_test.tscn`: PASS i SP- och MP-konfiguration vid 960×540 och 540×960; testet jämför faktiska kontrollrektanglar och åtkomst till musikreglaget.
- `music_quick_control_layout_test.gd`: PASS för hover, tangentbord, touch, mute och volymreglage. Profilens filskrivning blockerades av testmiljöns sandbox, så beständighet till disk verifierades inte av detta prov.
- Godot 4.7.2 Web-export lyckades från en ren snapshot efter versionsetikettcommitten. PCK är 2 773 856 byte.

## Begränsningar

Seedmätningen bekräftar att åtta coins inte orsakas av SP/MP-planeringsskillnad: de tre seedsen gav 174–198 planerade och presenterade coins vardera före insamling. Den bevisar inte vad som hände i användarens enskilda lopp; kamera-/kurssträcka, faktiskt insamlade coins och eventuell synlighet måste jämföras i diagnostiken för just den rundan. Seed 100000042 och 100001918 har långa coin-gap, cirka 4 943 respektive 5 092 px; ingen ytterligare täthetsjustering gjordes eftersom systemen redan matchar och en höjning skulle ändra kursinnehållet.

Tester kördes lokalt. Denna release har inte verifierats i ett inloggat GoTrue/PostgREST-myntlopp eller med en mänsklig hörsel-/autoplay-session i den publicerade webbläsaren. Tidigare browser WebRTC-kompaktbaseline-provet gällde loopbackklienter och är inte bevis på ett live wallet-lopp. Musikpersistens till settingsfil behöver separat manuellt/browserprov.

## Publicering

- Azure source branch: `codex/current-prototype`; implementation `fa57a86`, visible version metadata `b497622`, and subsequent report-only commits `a0304ba` and `b15ba8d`.
- GitHub Pages commit `0347442` publicerade aktiv root `https://hjelmdev.github.io/gravity-run/` och bundle under `docs/game/`. Actions workflow avslutades med `success` ([workflow](https://github.com/hjelmdev/gravity-run/actions/runs/37046825559)). Root-loader och game-loader svarade HTTP 200 och pekar på build `shared-run-hud-b497622-20261002`. Publikt nedladdad PCK och Pages-repots PCK matchade byte för byte: 2 773 856 byte, SHA-256 `4ADC3189BD7EB77253292195C1748E455C8DF2B9D500FCAB7B9D9D494D13EAA4`. Den paketerade appkoden byggdes från `b497622`; `a0304ba` innehåller endast den slutliga rapporten.

## Användarprov

1. Öppna [Gravity Run](https://hjelmdev.github.io/gravity-run/) och kontrollera att titel-/versionstext visar `2026.10.02-shared-run-hud-fix`.
2. Starta ett SP-lopp och ett MP-lopp. Bekräfta att coin-HUD och ljudkontroll har samma utseende, att MP saknar SP-distans och att en coin som vinns i MP spelar samma korta insamlingseffekt som i SP.
3. Prova musikreglaget med hover/klick på dator och expanderareglaget på touch. Bekräfta att mute verkligen stänger av musiken.
4. För jämförelse av sten, seed `GR8-100000000` kan användas i vanlig challenge-inmatning (seed `100000000`). Observera varning, fall och att stenen stannar som hinder efter nedslag.
5. Om ett lopp fortfarande visar få coins, spara diagnostik för den rundan så planerade, presenterade, synliga och insamlade objekt kan skiljas åt.


