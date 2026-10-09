# Nattlogg

Förloppet för de schemalagda passen (se NATTPASS.md). Nyast överst.

## 2026-10-09 kväll – värld 5–7 (WORLDS_5_7_PLAN.md)
- Klart: Frostfjället (062f1a5), Molnriket (3329c8a) och Öknen (8f1e170), sex banor och en
  boss var. Generatorn är orörd: frost använder grottans mix, moln och öken den klassiska.
- Nya skriptade inslag: lavin, snöstorm, blixtnedslag, vindbyar, sandfall, sandstorm.
  Lavin och sandfall är grottans ras med annan stil; snöstorm, vindbyar och sandstorm är
  askregnet (AshRain) med stilarna snow/wind/sand; blixten har spökhandens tidning.
- Bossar: Snöjätten (kastar snöbollar, laviner), Åskfågeln (blixtsalvor), Sandmasken
  (sandfall, kaktustak). Alla har testbot i campaign_runtime_test (0 fel).
- Upplåsningar: Bambu (Snöjätten), Hopp (Åskfågeln), Axel (Sandmasken). OBS: som med Bit
  får den som redan valt någon av dem standardlöparen tills bossen är slagen.
- Pixelpaletten fick spike_style ice/cactus, barrel_style snowball/tumbleweed, tree_style
  pine/cactus, hill_style puffy och islands, så nästa biom kan återanvända dem.
- Kartbilder: tools/campaign/generate_world_maps.gd (GDScript-port av Python-skriptet).
  Musik: frost_peaks, cloud_kingdom, desert_dunes. Nya ljud i generate_sky_desert_audio.gd.
- Val: 7-3 fick tätheten 1,4 (den klassiska mixen lämnade inga lugna fönster för sandfall
  vid 1,55); 7-3 har två sandfall i stället för tre.
- Inte publicerat: samlas med vagnfixen (59b859d) tills Adam ber om publicering.

## 2026-10-09 dagpass (Adam på jobbet) – läget
- Supabase-migrationerna 202610080002–0004 är INTE körda: Supabase-kopplingen här når bara
  Middagstipset och Block Pact, och datorn har ingen Supabase CLI eller databasnyckel.
  Adam kan klistra in filerna i SQL-editorn i den ordningen.
- Klart: Vulkanen (värld 4) enligt WORLD4_VOLCANO_PLAN.md: sex banor med frysta seeds och
  stjärnor (8462b4c), glödbomber, askregn och bossen Magmaormen (185825f), Bit låses upp av
  Magmaormen (ebab436), utseende, musik och ljud (444d8dc). Ingen Python på datorn, så
  ljudgeneratorn är skriven i GDScript och musiken är en loopande wav.
- Klart: biomnycklar, utrustning steg 4 (d7be110). Nycklarna är kampanjbelöningar i den
  lokala progressen, inte inventarieprylar (effektprylar är av i kampanjen).
- Klart: prestanda (7898ece): max 3 fysiksteg per bildruta i singleplayer, shaderförvärmning
  vid start, loggar ignoreras av git.
- Städning i huvudutcheckningen `gravity-run/` (gren codex/current-prototype): 532 loggfiler
  och 34 `.codex-*`-mappar flyttade till `gravity-run/logs/` (med .gdignore), inget raderat.
  `.codex-clean-gen20-8dd7e47` gick inte att flytta: två gamla Godot-processer från 8 okt
  (pid 67324 och 52780) håller den låst.
- Klart: multiplayer (91ab9ee): TURN via Edge Function turn-credentials (källan i
  supabase/functions, inte driftsatt, behöver CF_TURN_KEY_ID och CF_TURN_KEY_API_TOKEN) och
  besked till gästerna när värdens flik hamnar i bakgrunden.
- Inte gjort i fas 3: frysning av banor som händelselistor (generator 21 ändras aldrig, så
  det ger lite nu) och hemligheter (fas 6, belöningen är inte bestämd). Bakgrunder som noder
  (backlog 1.2) väntar, eftersom det behöver mätas i Chrome.
- Kända testfel som fanns före i dag: multiplayer contract_test (två gen11-versionsgrindar).
- Klart sedan förra posten: personbästa-spöke (32d6ce2), dagens bana (8959212), near miss-utrop
  (384e9f2). Alla 150 tester körda mot dagens och morgonens bygge (5700c34): samma resultat
  på allt som fanns i morse, alltså inga nya fel. 26 tester felar eller hänger likadant på båda.
- Webbexporten `campaign8-volcano-20261009` är byggd, provstartad i webbläsaren (meny, hubb med
  Dagens bana, en runda) och committad i Pages-klonen som d5ee43e. INTE pushad: väntar på Adam
  (`git push` i `E:TVECKLINGGRAVITY-RUN-PAGES`).

## 2026-10-09 08:00 – pass 2 slut
- Klart: sista regressionskörningen på allt är grön mot gamla bygget (enda skillnaden är
  `death_result_audio_test`, som är instabil även på gamla bygget). Webbexporten
  `campaign7-worlds23-20261009` är byggd och provstartad i Chromium.
- Publiceringen är committad i Pages-klonen (de51838, som Adam Hjelm) men INTE pushad:
  pushen till GitHub stoppades av behörighetsspärren (räknas som produktionsdriftsättning).
  Uppdatering 08:05: Adam godkände, pushat till GitHub (main = de51838).
- Pages-klonen: inget raderat. Git kunde inte ta bort sina egna lås- och tempfiler, så de
  ligger flyttade i `.git/_att_radera/` (HEAD.lock.1, index.lock.1, tmp_idx_Jloohe,
  tmp_pack_Pdtvq4) och kan tas bort. Åtta filer i `docs/` (index.js, refresh.html m.fl.)
  visas som ändrade men skiljer sig bara i radslut; de är inte rörda.
- Nästa: biomnycklar (utrustning steg 4) tillsammans med kampanjens fas 3. Servern behöver
  migrationerna 202610080002–0004 innan utrustning och lobbyvalet syns i spelet online.

## 2026-10-09 04:10 – pass 1 och 2 (samma session)
- Klart sedan förra posten:
  - Spökskogens skriptade inslag: spökhänder, gravstenar, irrbloss, dimma (978c040).
  - Utrustning steg 2: ångerskor och gravitationsankare (1146d48). Ångerskor: en vändning
    per flip inom 10/13/16 tick (nivå 1–3). Ankaret: tangent E eller Shift, eller
    pekknappen nere till höger; håller mitten i 1 s, laddar om på 15/12/9 s.
  - Utrustning steg 3: utrustningsval i multiplayer-lobbyn (2089684, af35ac5). Valet syns
    först när servern skickar fältet `equipment_enabled`. Migrationerna
    `202610080003_effect_items_regret_anchor.sql` och
    `202610080004_multiplayer_equipment_toggle.sql` är INTE körda.
    I racet fungerar bubbelhjälm och spikplåt; myntmagneten är av i multiplayer (värden
    validerar mynt) och det finns ingen multiplayer-topplista att märka `modified`.
  - Regression mot gamla bygget: två nya fel rättade. Väskans figurväljare hoppar nu över
    låsta figurer (testet uppdaterat). Ljuddiagnostikens timer kunde ta slut direkt efter
    en lång första bildruta (rättat i `sfx_audio_diagnostic_capture.gd`).
- Pågår: sista regressionskörningen på allt, sedan webbexport och Pages.
- Val: effektprylarna är av i kampanjbanor (som i steg 1).

## 2026-10-08 23:40 – pass 1 pågår
- Klart sedan förra posten:
  - Spökkungen 3-B med testbot (d46fb3f), Spökskogens utseende/musik/ljud (494c5af).
  - Pingo låses upp av Grottans boss, Misse av Spökkungen (6270058). OBS: de som redan valt
    Pingo eller Misse får standardlöparen tills bossen är slagen.
  - Småfixar ur backloggen avsnitt 8, alla fem (7056f84).
  - Grottans skriptade inslag (992fd6b). Nivåverktyget: `-- features [bana]` skriver ut
    inslagens positioner. 2-6 fick ingen fladdermussvärm (inget lugnt fönster kvar).
  - Utrustning steg 1: bubbelhjälm, spikplåt, myntmagnet (421c2fd). Migrationen
    `202610080002_effect_items_backpack.sql` är INTE körd mot Supabase. Servern behöver även
    `p_modified` på seed-RPC:erna och en `modified`-kolumn i topplistan.
- Pågår: Spökskogens skriptade inslag (händer, gravstenar, irrbloss, dimma), full regressionskörning.
- Nästa: webbexport och publicering när allt är grönt. Därefter utrustning steg 2
  (ångerskor, gravitationsankare) och steg 3 (lobbytoggle).
- Teknik: worktreen committas via tar + `apply.sh` på enheten (skriver filer på plats).
  Exportmallar för 4.7.2 web_nothreads hämtas med `tpz.py` (HTTP range) i molnet.

## 2026-10-08 23:15 – pass 1 pågår
- Klart: Grottans och Spökskogens banor i katalogen, sex var med seeds och stjärnor (19ee4c3).
  Nivåverktyget söker nu i alla världar (`-- 99 2-` söker alla grottbanor) och väger in
  banans fokushinder och antal hinder.
- Klart: Grottans utseende (presentationsbiomet `cave_campaign`), musik 150 BPM, ljud och
  bossen Stalaktitjätten 2-B med testbot (f64d1c0).
- Pågår: Grottans skriptade inslag (ras, fladdermussvärm, mörker, gruvvagnar).
- Nästa: Spökskogens utseende, musik, inslag och bossen Spökkungen. Sedan utrustning och shop.
- Val: grottbanornas täthet höjd till 1,15–1,5 (generatorn ger glesare banor i grottan än på
  ängen, så planens 1,0 gav bara 7–14 hinder på 2-1). 2-1 har extra vikt på istappar.
- Val: Spökskogen är låst tills Grottans boss är slagen, som tidigare. Pingo-upplåsningen
  är inte inkopplad än.

## 2026-10-08 22:40 – start
- Planer klara: WORLD2_CAVE_PLAN.md (03e6a73), WORLD3_HAUNTED_PLAN.md (3713c81), EQUIPMENT_AND_SHOP_PLAN.md.
- Nästa steg: Grottan steg 1 (CAVE_STAGES, nivåverktyget för biomen cave).
