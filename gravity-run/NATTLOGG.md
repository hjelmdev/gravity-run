# Nattlogg

Förloppet för de schemalagda passen (se NATTPASS.md). Nyast överst.

## 2026-10-09 08:00 – pass 2 slut
- Klart: sista regressionskörningen på allt är grön mot gamla bygget (enda skillnaden är
  `death_result_audio_test`, som är instabil även på gamla bygget). Webbexporten
  `campaign7-worlds23-20261009` är byggd och provstartad i Chromium.
- Publiceringen är committad i Pages-klonen (de51838, som Adam Hjelm) men INTE pushad:
  pushen till GitHub stoppades av behörighetsspärren (räknas som produktionsdriftsättning).
  Kvar: kör `git push` i `E:\Utveckling\gravity-run-pages`.
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
