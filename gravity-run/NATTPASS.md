# Nattpass – instruktioner för schemalagda körningar

Den här filen styr Claudes schemalagda arbetspass på Gravity Run. Varje körning startar
utan minne av tidigare chattar. Läs därför den här filen och `NATTLOGG.md` först och
fortsätt där förra passet slutade.

## Roller och modeller

- **Opus är orkestrerare, granskare och tar de svåra bitarna:** arkitektur, bosslogik,
  generatornära saker, felsökning och slutgranskning av allt som committas.
- **Delegera rutinkod till billigare modeller** med Agent-verktyget:
  - `model: "sonnet"` för vanlig implementation: katalogdata, UI, utseende,
    skriptade inslag, tester, översättningar och ljud- och bildgeneratorer.
  - `model: "haiku"` för enkla, mekaniska jobb: sv.po-poster, sök-och-ersätt,
    dokumentationsuppdateringar, att läsa testloggar och sammanfatta dem.
- Ge varje agent en avgränsad uppgift med filer, mål och vilket test som ska passera.
  Granska diffen innan den committas.

## Ordning (en punkt i taget, committa varje fungerande steg)

1. **Värld 2 – Grottan** enligt `WORLD2_CAVE_PLAN.md`. Steg 1 (katalog, seeds, stjärnor)
   kommer först, så att världen blir spelbar tidigt.
2. **Värld 3 – Spökskogen** enligt `WORLD3_HAUNTED_PLAN.md`. Följ planens förval där Adam
   inte har bestämt något.
3. **Utrustning och shop** enligt `EQUIPMENT_AND_SHOP_PLAN.md`. Börja med bubbelhjälmen,
   spikplattan och myntmagneten.
4. **Småsaker** i `BACKLOG_20261008.md` avsnitt 8: konfetti och målljud, skor i
   karaktärsvyn, ta bort "32x32 pixlar", pausmeny utan scroll, Rullaren som kastar tunnor.
   Ta dem när en större punkt väntar på något, eller sist.

## Regler

- Arbeta i worktreen `E:\Utveckling\Gravity Run\.claude-worktrees\analys`, gren
  `claude/analys-och-forbattringar`. Godot-projektet ligger i `gravity-run/`.
  - Klona inte repot någon annanstans.
  - `docs/` i Pages-klonen är bara publiceringsmål.
- Commits görs med `git -c core.autocrlf=true`. Avsluta meddelandet med
  Co-Authored-By-raden för modellen och sessionslänken.
- **Ändra inte generatorn för befintliga versioner.** Nya hinder ska vara skriptade
  inslag i kampanjen. `tools/generator_equivalence_dump.gd` ska ge identiskt resultat.
- Efter varje steg körs headless:
  - `tools/campaign/campaign_runtime_test.tscn`
  - regressionssviterna
  Kända fel sedan tidigare: gen19_fallback, biome_gen17 och singleplayer_ghost.
  `gen20_coin_replan_cost_test` är tidskänsligt under last.
  Kör aldrig två Godot-processer i samma projektmapp.
- Pusha inte till Azure DevOps.
- Ta skärmdumpar med xvfb-run (`--rendering-driver opengl3 --resolution 960x540`) och titta
  på dem innan något visuellt räknas som klart.

## Teknik som en ny session behöver

- **Datorn nås via enhetsbryggan** (device_bash). Mapparna ligger i
  `$HOME/mnt/Gravity Run` och `$HOME/mnt/gravity-run-pages`. Enhetens VM når inte GitHub.
- **Arbetsflöde:**
  1. Kopiera `gravity-run/` (utan `.godot`) till molnets scratch.
  2. Redigera och testa där.
  3. Packa de ändrade filerna med tar till `/mnt/user-data/outputs`.
  4. Skriv tillbaka med `device_commit_files`, packa upp i worktreen och committa.
  5. Använd ett nytt filnamn varje gång. Samma sökväg kan ge en gammal kopia.
- **Godot 4.7 och 4.7.2 för Linux** laddas ner från GitHub-releaser i molnet. För webbexport
  behövs web_nothreads-mallarna (release och debug) i
  `~/.local/share/godot/export_templates/4.7.2.stable/`. Hämta dem ur tpz-filen med
  HTTP range-anrop.
- **Publicering till Pages** (`hjelmdev/gravity-run`, `main`, spelet ligger i `docs/game/`):
  1. Exportera med Godot 4.7.2. Bara PCK-filen brukar ändras.
  2. Kopiera `index.<BUILD>.pck` och `index.pck`.
  3. Uppdatera `fileSizes` och `mainPack` i `docs/game/index.html`.
  4. Uppdatera `'build'` och `BUILD_ID` i `docs/` och `docs/game/`.
  5. Committa som "Adam Hjelm <hjelm.adam@gmail.com>".
  6. Skapa en bundle med `git bundle create x.bundle origin/main..main`.
  7. Hämta in den med `device_stage_files`.
  8. Pusha via en temporär bare-relay i molnet.
  9. Kör `git update-ref refs/remotes/origin/main` i Pages-klonen.
  Publicera bara när testerna är gröna.

## Logg

Efter varje avslutat steg och innan ett pass tar slut: skriv i `NATTLOGG.md` vad som är
klart (med commit), vad som pågår, nästa steg och vilka val du gjort. Committa loggen. Om
användningen tar slut mitt i ett steg ska loggen räcka för att nästa pass kan fortsätta.
