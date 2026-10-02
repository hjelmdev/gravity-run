# Gemensam gameplay- och HUD-fix efter release

## Genomförda ändringar

MP:s `WORLD_COMMIT`-väg applicerade först committen i serviceägd `WorldSimulation` och skickade sedan signalen till matchscenen. Matchen såg därför `duplicate`, trots att det var den aktuella auktoritativa coin-awarden. Matchen animerade bara `applied`, så den delade coin-noden försvann utan insamlingsanimation. Den nya presentationroutern accepterar den bekräftade `applied`/`duplicate`-vägen och återanvänder `Coin.animate_collection()`. Dedupe ligger kvar på eventnoden; bildpresentationen ändrar inte vinnare, ledger eller kontobelöning. Baseline och reconnect fortsätter dölja gamla insamlade mynt utan att skapa en ny animation.

SP och MP använder nu samma `ui/shared_run_hud.tscn` för titel, spelarnamn, myntikon/-tal och musikreglage. SP behåller distansfältet och sina marknads-, inventory- och pausknappar. MP döljer distans och behåller sin separata nätverksstatus-/menyfunktion utan SP:s marknad, inventory eller pausmeny. Ljudkontrollen finns i den gemensamma HUD-scenen. Expanderpilen ritas som vektorgrafik i stället för ett fonttecken. En responsiv offset skickas nu genom kontrollens layoutmetod; den tidigare propertyuppdateringen flyttade aldrig MP-knapparna och orsakade överlapp med menyn. De tomma seed-rankingtexterna är borttagna; faktiska seedresultat visas fortfarande.

## Mätningar och avgränsningar

`shared_coin_mode_parity_test.gd` jämförde faktiskt SP endless-regelset med MP-manifest och MP-presentation på v8, 45 000 px, tre seeds som accepteras av menyn:

| Seed | Planerade/SP-streamade | MP-manifest | MP-visningsnoder | SP/MP hazardhändelser | Största myntgap i exemplet |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100000014 | 198 | 198 | 198 | 48 / 48 | 1 250 px |
| 100000042 | 174 | 174 | 174 | 59 / 59 | 4 942,9 px |
| 100001918 | 180 | 180 | 180 | 52 / 52 | 5 092,1 px |

SP plannerades i 5 173 px-strömningsbitar och mynt-ID, placering och antal matchade MP:s fulla manifest exakt i de här proven. Räknarna avser genererade/presenterade mynt, inte sådana som en viss spelare lyckas plocka upp; de kan därför inte förklara eller motbevisa ett personligt resultat på åtta insamlade mynt. De visar att kursen inte genererar eller presenterar endast åtta objekt. Hazardtätheten var också identisk i de här tre seedparen, så inga generatorvärden eller versionsidentiteter ändrades.

Stenens v8-data från båda kursvägarna anger 104 varningsteg (1,73 s vid 60 Hz) och 42 fallsteg (0,70 s). SP:s verkliga scenprov observerade vilande, varning, fall och permanent nedgrävd fas för `GR8-100000000`. MP:s host/guest-simulering passerade samma tick 169 med identisk permanent hitbox. Det verifierar delade tickparametrar och fasövergångar; det är inte en mätning av faktisk bildfrekvens eller subjektiv hastighet i webbläsaren.

## Verifiering

- `coin_match_commit_integration_test.tscn`: faktisk service-handler för gästpaketet → servicecommit → `world_event_committed` → riktig matchcallback → gemensam coin-scen. Bevisar att matchens andra apply-resultat är `duplicate`, att animationen startar, att upprepad commit inte startar om den och att ledgerns winner/value förblir oförändrade.
- `shared_coin_mode_parity_test.gd`: SP streaming/MP manifest/presentationjämförelsen och kursräkningarna i tabellen.
- `shared_run_hud_scene_test.tscn`: faktisk SP-huvudscen och samma delade HUD-komponent i 960×540 och 540×960; kontrollerar synliga kontrollområden, SP:s menyknappar samt MP:s ljud-, meny- och statusområden.
- `music_quick_control_layout_test.gd`: mute/ON, bevarad volym, hover, pekarövergång till slider, sliderdrag, touch-expander och tangentbordsfokus.
- `singleplayer_rock_v8_runtime_test.gd` och `multiplayer_v2/shared_rock_v8_tick_parity_test.gd`: SP-faser och MP tick-/hitboxparitet.

Headless körmiljö rapporterade att `user://logs/godot.log` och systemets certifikatbutik inte var tillgängliga. Tester som skriver musikinställningar fick även fel 12 vid diskpersistens; kontrollerna och runtimevärdena testades, men denna körning verifierade inte en sparad inställningsfil. Jag gjorde ingen verklig webbläsar-/ljuduppspelning eller livekonto-match. Inga backendmigrationer behövdes eftersom inga genereringsregler eller fysik ändrades.

Käll- och Pages-commits, exportens build-ID/hash samt publicerad URL fylls i efter den scoped releasen.
