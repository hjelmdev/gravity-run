# Meny, grottflimmer, gemensamt kameraankare och lavavulkan

Användarfeedback 2026-10-05 efter Gen14-release. Implementera samtliga punkter enligt etablerat Luna/root-upplägg: Luna bygger och verifierar, root granskar verklig diff och bildsekvenser, rättningar före ordinarie Azure/migration/Web/Pages-publicering.

## Baslinje och skydd

- Senaste gameplay 3f48788, dokumentation310ae8c; Gen14/API2.1.20261005.10/manifest7. Bekräfta HEAD. Public build lava-rhythm-demo-fix-3f48788-20261005.
- Bevara touchfix, inspelat dödsljud, mynt/SFX-idempotens och orelaterad dirty capture/menu/main/pacing. Scoped staging av hunks i main.gd, aldrig bred add.
- Skriv GEN14_VISUAL_FEEDBACK_AND_LAVA_FAN_FIX_STATUS.md tidigt med verklig fas och evidens. Återanvänd befintlig agent, starta inte konkurrerande implementation.

## 1. Kompakt Game Hub

- Behåll seedfältet och valideringsfel, men ta bort den permanenta tekniska optional-seed-raden. Använd kort lokaliserad placeholder, exempelvis Seed (tomt = slump), och eventuell tooltip för GR-koder.
- Dölj rutintexten Inloggad · väskan är synkad. Visa relevanta fel/inloggningsbehov/synkproblem när de faktiskt behövs; tom/dold statusrad ska inte reservera höjd.
- Minska mellanrum och stora ikonytor/marginaler, behåll tydliga tryckytor och läsbara etiketter. Justera responsivt så alla huvudsakliga knappar inklusive Till huvudmenyn ryms på användarens typiska desktop/liggande vy utan scroll. Behåll scroll som fallback på verkligt små/tall-font-vyer; dölj inte innehåll genom att bara stänga av scroll.
- Seedfält fortfarande dolt/låst vid aktiv challenge. Kontrollera seedfel, tabbfokus, tangentbord, touch och layout vid minst960x540/1280x720 samt smal vy.

## 2. Grottbiomens kraftiga flimmer

- Användarbilden visar grottans blå ridge-lager och rapporterar flimmer främst till höger i MP; SP kan också påverkas. Orsaken är inte bekräftad. Läs befintligt cave-renderarbete innan ändring.
- Reproducera via faktiska SP- och MP-presentationer i rörelse och vid biomegränser. Fånga många efterföljande GPU-renderframes, kontrollera SCRIPT/triangulation-errors och jämför samma världspunkter efter kompensation för parallax/kamera.
- Granska _draw_cave_backdrop: sortering/klippning av ridge-punkter, fragmentkanter, sista sample och polygoner. Uteslut självkorsning/degenerata segment vid sample- och biomegränser. Undvik fragmentberoende omgenerering av mönster och hårda fasbyten. Verifiera även alternativa bakgrundstexturlager om de används i aktuell resurs.
- Gemensam fix i BiomeRenderer för SP/MP. Behåll resurs/asset-utbytbarhet. Ändra inte hazardseed/RNG för en ren renderfix.
- Visa bildsekvens eller kort video och kvantifierad temporal kontroll av främst höger skärmhalva. En parse och en stillbild är inte bevis att flimmer försvunnit. Redovisa om ingen repro kan fås; påstå inte verifierad fix utan evidens.

## 3. Gemensam synlig runnerplacering från preparing till start

- Bekräftad kodskillnad: main använderPLAYER_X180, MP CAMERA_PLAYER_X250 med max(cameraLeft,0). StartworldX180 innebär därför bakre placering i pre-race och därefter glidning mot250. Använd samma gemensamma kameraankare som SP (180 världspixlar) i normal follow och spectator, så ingen särskild förflyttning introduceras vid START.
- Lägg ankardefinitionen i gemensam kamera/presentationkonfiguration i stället för fortsatt två godtyckliga tal. Behåll verklig seed/startworldX och simulerade runnerpositioner; ingen falsk multiplayerförsprång/offset. Samma värld-till-skärm transform för hinder/spelare.
- Jämför normaliserad synlig position vid samma viewport/zoom och faktisk kamerascale. Ingen oombedd total MP viewport/portrait-ombyggnad, men redovisa och rätta om olika befintliga transforms fortfarande ger olika ankare.
- Test preparing→countdown→START med sub-tick/renderfraktioner, frame efter start och följande löpning. Ingen abrupt ankarskillnad. Egen figur överst vid överlappning, remote sampling och spectatorregler bevaras.

## 4. Sprickor och flera eldklot i solfjäder

- Sprickan ska visuellt sträcka sig djupare ner i golvet (spegelvänd mot taket) med glödande förgreningar. Dekor under stödytan får ökas utan att träffytan osynligt växer upp i korridoren.
- Användaren vill också bredare/längre dödlig sträcka. Öka försiktigt och versionera gameplaybredd, threatintervall, resolver, validator, safe-route och myntfiltrering tillsammans. Visa exakt visuell het sträcka; stödytan får inte försvinna om ingen hålregel beställts.
- Vulkanen ska kasta fler än dagens två klot: exempelvis tre tydliga ballistiska bågar åt vardera sidan per utbrott, sex eldklot totalt, med olika horizontal/vertical speed. Efter test kan antalet anpassas, men två ensamma cirklar uppfyller inte önskemålet.
- Eldklot ska ritas med ljus kärna, oregelbunden flamsiluett och kort svans orienterad efter faktisk projektilhastighet. De ska visuellt komma ur kratern. Kosmetisk svans har inte egen osynlig kollision. Utbytbara scene/resurser, samma SP/MP-ritning.
- Ingen separat förvarnings-HUD beställd. Förutsägbar seed/tickbaserad eruption och tillgänglig takpassage kvarstår. Ingen stråle som fyller hela korridoren.
- Modellera flera bågar i den gemensamma LavaHazardModel, med stabil projectile-ID(burst/båge/riktning), bounds/lifetime och samma endpoint+swept kontakt i SP/MP. Endast gemensamt manifestdata/fast tick, aldrig lokal klocka/renderFPS. API/baseline får inte tappa trajectorydata. Render interpolation och kollision använder samma bana.
- Gemensamt konservativt collision-envelope används av validator, myntfilter, projektil-/bodykontakt och hotprognos. Alla tillåtna bågar ska lämna runnerstorlek+marginal till takets faktiska stöd över projektilernas hela spann, inte endast ceiling_y vid vulkanens mitt om terrängen förändras.
- Begränsa samtidiga eldklot, eventuell debris och ljud. Behåll lokal visuell ljudtiming/dedup; ingen extra ljudspam per renderframe eller gamla eruptionljud från baseline.

## Versionering och verifiering

- Bredd/fler projektiler ändrar gameplay: använd ny explicit generatorversion (förväntat15) för nya banor, bevara Gen14 och äldre seed/manifester/trajectorys exakt. Frys minst5 Gen14 event-/mynt-/manifesthashar före ändringen och verifiera också Gen13 och tidigare kompatibilitet.
- Legacy Gen14-vulkaner ska fortfarande ha sina två gamla trajectories. En kosmetisk förbättrad sprite får appliceras där utan att ändra contacts/timing. Introduktionsversioner får inte bindas till CURRENT så äldre nya hazards plötsligt försvinner.
- Uppdatera nödvändiga validator-, manifest-, parser-, provider- och backendgrindar med unik scoped migration. Inget nytt walletflöde eller avsiktlig myntbudgetökning. Granska local authenticated-role gate/receipt- och linked-history före live.
- Testa riktiga full-manifest RunnerMotion-rutter vid250/500/750px/s, relevanta cooldowns och eruptionfaser. Sätt simtid till riktig ankomst/phase, assert aktiva projektiler. Både säker väg och frivilliga riskmynt; kontrollera gränser/understöd, kropp, varje båge och bred spricka.
- Faktisk main-scen och MP-match/presentation testas; faktiska GPU-bilder för lava och meny samt tidssekvens för cave/ankare. Fixture är inte ansluten MP-session; redovisa skillnaden.
- Egna Godot-processer körs seriellt med tidsgräns och PID/barncleanup. Bevara användarens editor. Inga runtimeSCRIPTerrors får avfärdas som miljövarningar.
- REVIEW_READY: verklig diff, scoped migration, relevanta tester och bildsekvenser, fördelning/projektilmax, testseed+avstånd. Root granskar och Luna rättar. Efter approval scoped Azurepush, nödvändiga granskade migrations, rent exakt-commit Webbygge/Pages-root, workflow/rätthead, bådaBUILD_ID/root/loader och offentlig nedladdad PCK-hash.
- Återförsök inte nekad livehandling utan relevant faktisk användarauktorisation. Slutrapport är sanningsenlig om live gameplay begränsningar. Ingen återgång till endast dokumentation när implementationen är beställd.
