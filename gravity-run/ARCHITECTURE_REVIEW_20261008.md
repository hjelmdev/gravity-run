# Gravity Run – arkitekturgranskning 2026-10-08

Gjord på `codex/current-prototype` @ `64edf30` (Gen21). Ändringarna ligger på branchen
`claude/analys-och-forbattringar` i worktreet `.claude-worktrees/analys`.
Mätningarna är gjorda headless med Godot 4.7 på en vanlig x86-CPU. I webbläsaren
(wasm, en tråd) blir motsvarande tider normalt 2–4 gånger längre.

## 1. Laggspikarna i webben: huvudorsaken är hittad

Spikarna växer med hur länge rundan har pågått. Det är inte slumpmässigt hack.

Singleplayer bygger banan löpande i `_physics_process`:

1. `CourseGenerator._append_feasible_event()` provar upp till 64 × 128 kandidater per hinder.
   För varje kandidat gjordes `_events.duplicate()` och sedan `is_plan_solvable()`. Den byggde
   om och sorterade **alla kanthändelser sedan rundans start** med en GDScript-lambda.
   Kostnaden per kandidat växte alltså med rundans längd.
2. `_spawn_shared_coins()` (var 250 px ≈ 0,5 s) och varje spawn av såg, spöke, sten och lava
   anropar `CourseManifestBuilder.resolve_runtime_events()` över **hela banans historik**.
   Inuti var både `_surface_y_at()` och `CourseSurfaceIndex._build_profile()` kvadratiska.
   Den sista skannade alla händelser för varje gränsintervall.

När en sådan frame tar 50–200 ms kör Godot ikapp upp till 8 fysiksteg (standardvärdet för
`max_physics_steps_per_frame`) i nästa frame. Ett enskilt hack blir därför en serie
segframes, vilket är exakt det "saktar ner till några få frames" som syns i spelet.

### Uppmätt (seed 100000042, Gen21, 500 px/s, värsta tick per minut)

| Minut i rundan | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Generator + resolve, före | 18,8 ms | 57,8 ms | 89,1 ms | 144,8 ms | 215,8 ms |
| Generator + resolve, efter | 8,0 ms | 23,7 ms | 33,2 ms | 35,6 ms | 72,0 ms |
| Bara generatorn, före | 13,4 ms | 15,2 ms | 25,6 ms | 50,5 ms | 66,5 ms |
| Bara generatorn, efter | 2,6 ms | 5,7 ms | 6,2 ms | 15,0 ms | 6,9 ms |

`resolve_runtime_events` vid 150 000 px: själva resolve 73 → 25 ms och varje säkerhetsfilter 17–19 → 6–7 ms.

### Vad som är ändrat (resultatet är bevisat identiskt)

- `course_generator.gd`: lösbarhetskontrollen är inkrementell. Kantlistan för den redan
  accepterade planen sorteras en gång per accepterat hinder, och svepets tillstånd sparas per
  x-grupp. En kandidat sveps bara från den sista gruppen före kandidatens första kant. Svepet
  beror bara på de sorterade x-värdena och vilka kanter som finns i varje x-grupp, så
  resultatet blir detsamma. Det publika `is_plan_solvable()` fungerar som förut.
- `course_manifest_builder.gd` och `course_surface_index.gd`: ytuppslagen skannar bara
  step-, slope- och gap-poster för rätt fil, i samma ordning. Det ger samma svar, men utan att
  gå igenom varje hinder.
- Verifiering:
  - `tools/generator_equivalence_dump.gd` gav identiska hashar (planer, generator-statistik,
    runtime-resolves och MP-manifest) för generatorversion 5–21 × 8 seeds vid 40 000 px och vid 110 000 px.
  - Händelseström tick för tick (8,33 px/tick, 90 000 px) var identisk för version 16/18/20/21 × 3 seeds.
  - Befintliga tester (freeze, cohort, coin stream parity, pursuit och liknande) gav samma
    resultat före och efter. `course_manifest_test` misslyckas redan på basen.

Observera att generatorns händelser innehåller `"profile": <Resource#id>`. JSON-hashar av råa
generatorhändelser varierar därför mellan processer. Manifesthasharna påverkas inte.

### Kvar att göra (förslag)

Resolve-kostnaden växer fortfarande linjärt, eftersom hela historiken resolvas om var 0,5 s
(cirka 70 ms efter 5 minuter på desktop). Den riktiga lösningen är en **strömmande
runtime-manifest**: cacha det resolvade prefixet bakom ett säkerhetsfönster, till exempel
6 000 px bakom horisonten, och resolva bara svansen. Filtren tittar framåt (pursuit-rutter
upp till ungefär 3 000 px), så det kräver ett paritetstest mot nuvarande
`gen20_coin_stream_parity_test` innan det tas i bruk. Det är nästa steg jag föreslår.

Billiga skydd under tiden:
- `physics/common/max_physics_steps_per_frame = 3` för singleplayer. Ett hack blir då en kort
  inbromsning i stället för en spiral. MP-klockan måste kontrolleras först.
- `main.gd` gör `get_planned_events()` (en kopia av alla händelser) varje fysiktick, plus en
  full resolve per spawnat hinder. Båda kan hållas inom ett fönster.

## 2. Arkitektur i dag

- `main.gd` (1 851 rader) är både simulering, spawn, kollision, debug-diagnostik och rendering
  av singleplayer. Världen flyttas mot en fast spelare, och varje nod flyttas med `.call()`
  på strängnamn varje tick.
- Multiplayer v2: `multiplayer_v2_service.gd` (3 121 rader) innehåller lobby, signalering,
  WebRTC, rundkoordinering, värdregler, coin-backend och diagnostik.
  `multiplayer_v2_match.gd` (2 118 rader) är motsvarande för presentationen.
- Rendering: bakgrund, banytor, väder och varningar ritas om med `draw_*` i `_draw()` **varje frame**
  (antialiaserade linjer, cirklar, `draw_colored_polygon` med triangulering), plus en
  `Callable` per tile för yt-y. Det är en jämn CPU-kostnad som inte går att batcha.
- UI: alla skärmar byggs i kod med cirka 220 inline-`add_theme_*`-överskrivningar. Det fanns
  inget tema och ingen font, så knappar var Godots grå standard.
- Repot: roten av `gravity-run/` innehåller cirka 400 loggfiler och kontroll-
  `.codex-*`-mappar ligger i arbetsträdet. Editorns filskanning blir långsam och diffar blir
  svåra att läsa. `haunted_*.svg.import` saknades i git. De ligger nu på branchen, eftersom en
  ren checkout annars ger "Failed loading resource" vid första importen.

## 3. Multiplayer jämfört med block-pact

Block-pact använder deterministisk lockstep med input-bitmasker. Det passar ett pusselspel
men **inte** en runner, där varje spelare vill ha omedelbar respons. Gravity Runs modell, där
varje klient äger sin egen löpare och en värd avgör delade världshändelser, är rätt i grunden.
Det som är värt att ta med sig från block-pact:

1. **RoomHost-mönstret.** Lyft ut värdlogiken (round coordinator, world simulation, event
   ledger, validation, destructible rules) till en `V2RoomHost`-nod utan UI- och
   auth-beroenden. Spelaren-som-värd och en headless-server kan då köra samma klass, och
   `server/server_main.tscn` kör N rum. Det är förutsättningen för en headless server.
   Uppskattning: medelstort jobb, i steg.
2. **TURN.** Spelet har bara Google STUN. Spelare på mobilnät eller företags-wifi kan då
   misslyckas med att koppla upp. Block-pact hämtar kortlivade Cloudflare TURN-uppgifter via
   Edge Function `turn-credentials`. Den kan kopieras till Gravity Runs Supabase-projekt.
3. **Bakgrundsflik.** En värd i en dold flik fryser världshändelserna för alla. Block-pact
   skickar ett meddelande synkront på `visibilitychange` och lämnar över platsen. Här finns
   bara fokus-hantering för touch.
4. **Desync-skydd.** Hasha ledger- och världsstatus var N:e tick och jämför hos värden, så
   att sync-buggar syns direkt i stället för som "konstigt beteende".
5. **Kompaktare positionspaket.** Positionspaketen skickas i dag som Dictionary 30 gånger
   per sekund. Ett PackedByteArray med fasta fält ger mindre paket och mindre parsning.
6. **Verifierade highscores.** Seedade SP-rundor är deterministiska. Att ladda upp input per
   tick och spela upp dem headless (som block-pacts `ScoreVerifier`) gör topplistan fuskfri.

## 4. Grafik och känsla

- **Stilkrock.** Pixelart-löparen är 44 px och skalas ×1,5, alltså icke-heltal, vilket ger
  ojämna pixlar. Bakgrunden är antialiaserad vektor ritad i kod, ytorna är atlas-tiles och
  den hemsökta biomen är SVG. Välj en riktning. Antingen pixel (heltalsskala ×2, nearest,
  pixel-snap, hinder och bakgrunder som sprites) eller ren vektor (löparen i högre upplösning).
  Eftersom assets ska bytas senare bör en `GameAssets`-resurs som i block-pact skapas nu, så
  att bytet blir datadrivet.
- **Bakgrunder.** Statiska lager bör vara `Parallax2D` med texturer, och vädret
  `CPUParticles2D`. Det sänker CPU-tiden per frame, vilket ger marginal mot hack.
- **Menyer.** Gjort på branchen: ett globalt tema (`ui/theme/gravity_theme.tres`, genereras av
  `tools/build_ui_theme.gd`) som ger knappar, fält, reglage, rullister och tooltips samma
  marin/turkos stil som panelerna, plus en fade när en menyskärm byts.
  Förslag härnäst:
  - en riktig font. `Font/Ubuntu-Regular.ttf` finns redan i gamla roten, men en display-font
    till rubriker lyfter mer.
  - klickljud för UI
  - en `MenuPage`-bas och router som i block-pact i stället för att varje skärm bygger egen layout
  - tydligare hierarki i hubben, med en stor "Starta"-knapp och resten sekundärt

## 5. Roliga tillägg (sorterade efter hur enkla de är)

1. **Utseende i singleplayer.** Gjort: väljaren i hubben (en animerad löpare med < >) sparas
   lokalt, används i SP-rundor och föreslås automatiskt i MP-lobbyn. Autoplay-bakgrunden i
   menyn får ett slumpat utseende. Fler än 4 utseenden kräver en migration, eftersom lobbyns
   RPC och tabellen kontrollerar `skin_id between 0 and 3`.
2. **Spöke av ditt personbästa.** Seedade rundor är deterministiska. Spara flip-input per tick
   och spela upp dem som en halvgenomskinlig löpare.
3. **Dagens bana.** Samma seed för alla under ett dygn, med egen topplista. ChallengeService
   finns redan.
4. **Utrop och "near miss"-bonus.** Ge ett utrop när du flippar precis förbi ett hinder
   (bara presentation, som block-pacts `board_callouts`).
5. **Avatarer i topplistor och lobby.** Pixelavatarer färgade i spelarens skin-färg (`AvatarView`).
6. **Emotes i lobbyn och på resultatskärmen** via Realtime broadcast, vid sidan av spellogiken.
7. **Spår eller efterbild vid flip** som kosmetisk upplåsning i shoppen.

## 6. Övrigt

- Gravity Runs Supabase-projekt (`qtuyiammppulmxhyaesh`) syns inte via Supabase-kopplingen
  i Claude. Där syns bara "Block pact". Databas- och auth-ändringar för Gravity Run kan jag
  därför inte göra därifrån förrän rätt organisation är kopplad.
- Webbexporten saknar trådar (`thread_support=false`). Det är rätt för GitHub Pages, men
  betyder att allt tungt arbete måste hållas utanför enskilda frames.
