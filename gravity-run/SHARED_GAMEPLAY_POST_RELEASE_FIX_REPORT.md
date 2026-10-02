# Shared coin feedback and HUD alignment release

Datum: 2026-10-02. Ändringen är presentationsbegränsad: spelregler, 120 ms coin-claim-fönster, deterministisk värdvalidering, ledger/wallet-belöning och v8-kursgenerator lämnas oförändrade. Ny synlig buildversion: `2026.10.02-shared-coin-hud-feedback`.

## Ändringar

- En lokal spelare får nu coinens befintliga insamlingsburst direkt vid en verklig svept kroppskontakt, innan WORLD_INTERACTION skickas. Predictionen är knuten till request, runda, entity och incarnation; den rör inte coin-ledger, HUD-räknare eller reward-signal. Värdens beslut förblir auktoritativt. En godkänd/annan spelares commit bekräftar den pågående effekten utan att starta om den. Ett avslag återställer bara en coin som lokalt fortfarande är aktiv och vars avslagsorsak inte säger att den redan vunnits. Dubletter, sena svar, redan tagna coins och ny-runda reset skapar inte extra burst eller reward.
- MP:s menu-knapp, speaker och volympil delar nu samma beräknade vertikala toolbarlinje. Speaker-hover och speakerfokus öppnar inte volympanelen; speakerklick togglar `music_enabled`. Endast sliderpilen öppnar panelen via hover/klick, och panelen hålls öppen vid pointerhandoff. SP och MP använder fortsatt samma musikkomponent.

## Verifiering

- `tools/multiplayer_v2/coin_match_commit_integration_test.tscn`: PASS. Testet skapar en riktig svept kontakt genom matchens `_submit_coin_claims`, startar presentationen i samma tick, kör service-arbitreringen efter 420 ms (120 ms claim-window plus 300 ms lokal väntetid), och bekräftar commit genom serviceevent och matchcallback. Det täcker ook aktiv coin efter nekad claim, en annan spelares vinnande commit, `already_collected` utan lokal commit, sen/duplicerad bekräftelse, baseline med aktiv coin, round reset och att ingen visual prediction emitterar SP:s `collected`-reward-signal.
- `tools/shared_run_hud_scene_test.tscn`: PASS på faktiska SP/MP HUD-scener och MP-layout vid 960×540 och 540×960; MP menu/speaker/sliderpil har samma mittlinje.
- `tools/music_quick_control_layout_test.gd`: PASS för speaker-hover/fokus, mute-klick, sliderpil-hover, handoff till panel, stängning, touch expansion och volymändring. Testmiljön nekade skrivning av settingsfilen (Godot error 12), så beständig lagring verifieras inte här.
- Godot 4.7.2 headless körning rapporterade Windows CA-store och `user://logs/godot.log` åtkomstvarningar. De riktade testerna slutfördes med PASS.

## Begränsningar

420 ms väntan i coin-testet simulerar sen bekräftelse lokalt; den är inte ett uppmätt nätverkspaket över faktisk browser/WebRTC och testar inte GoTrue-/walletflödet. En andra spelares klient får fortsatt burst när den auktoritativa värdcommiten anländer. Den lokala spelaren får omedelbar feedback utan att påverka tävlingsutfallet. Ingen faktisk browser-session med två konton eller användarstudie genomfördes.

## Publicering

Azure `codex/current-prototype` och GitHub Pages `main` publiceras efter testkörningen. Aktiv Pages-root är [https://hjelmdev.github.io/gravity-run/](https://hjelmdev.github.io/gravity-run/). Slutliga source-/Pages-commits, workflowstatus, build-ID och publikt PCK-hash dokumenteras när deployment är klart.

## Användarprov

1. Öppna root-länken och kontrollera buildversionen `2026.10.02-shared-coin-hud-feedback`.
2. I MP, spring genom en coin och kontrollera att effekten börjar vid kontakt före hostbekräftelsen. Låt sedan två spelare tävla om samma coin; bara värdens utsedda vinnare ska få belöningen.
3. Hovra över speakerikonen: volympanelen ska förbli stängd. Klicka speaker för mute/unmute; öppna reglaget med pilen. Prova samma beteende i SP och MP.
4. Kontrollera att MP menu-knapp och speaker/pil ligger på samma horisontella linje i liggande och stående format.
