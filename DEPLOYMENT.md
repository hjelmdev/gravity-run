# Gravity Run web deployment

The Godot source project is in `gravity-run/` and is pushed to the Azure DevOps repository. The public GitHub Pages repository is a separate, export-only repo: `https://github.com/hjelmdev/gravity-run.git`.

The shared source branch is `codex/current-prototype`. Singleplayer, Multiplayer V1 and Multiplayer V2 are menu choices in one build at `https://hjelmdev.github.io/gravity-run/`. The `game-v2` export directory is historical naming; it contains all three modes. The old `multiplayer-v2/` entry redirects to the root.

Keep the persistent local clone of the Pages repo at `E:\Utveckling\gravity-run-pages` (branch `main`), outside the user's profile and separate from the Azure source repo. Do not use a Temp/AppData clone as the working copy. Older clean deployment clones, if retained, belong under `E:\Utveckling\gravity-run-pages-archive`.

## Publish a web build

1. Export the `Web` preset from `gravity-run/project.godot` to a temporary folder **outside the Azure source repo**. With this machine's Godot install, the command is:

   ```powershell
   & 'E:\Utveckling\Godot_v4.7.2-stable_win64.exe' --headless --path 'E:\Utveckling\Gravity Run\gravity-run' --export-release Web '<temporary-export-folder>\index.html'
   ```

2. Clone or update `hjelmdev/gravity-run` on branch `main`, then copy the exported files into that clone's `docs/game-v2/` folder.
3. Preserve the Pages shell at `docs/index.html`. It supplies the orientation prompt, OAuth callback, mobile text entry and cache refresh, and loads `docs/game-v2/index.html` in an iframe. Do not replace it with Godot's generated HTML. Keep shell/manifest icons pointed at the current export. The unified release may update these integration files and the old V2 redirects; a normal game-only export changes only `docs/game-v2/`.
4. Give the PCK a unique release filename (for example `index.unified-<source-sha>.pck`) and update both `mainPack` and `fileSizes` in the exported HTML config. Keep `index.pck` as a compatibility copy. This prevents a cached prior PCK being combined with a new HTML loader. Verify sizes and SHA-256 after copying.
5. Stage the game export and verify the staged paths before committing:

   ```powershell
   git add -- docs/game-v2
   git diff --cached --name-only
   ```

   For a normal export every staged path must start with `docs/game-v2/`. For the unified release explicitly stage and review any required `docs/index.html`, `docs/gravity-run.manifest.json` and `docs/multiplayer-v2/` redirect changes separately. Preserve unrelated paths. Commit and push `main` to `origin`; never force-push.
6. If Git has no configured identity, the Pages repo's existing commit identity is `Adam Hjelm <hjelm.adam@gmail.com>`. Apply it only to the deploy commit with `git -c user.name=... -c user.email=...`; do not change global Git configuration.

No cache-busting `?v=` URL is needed: the shell retires old workers and the PCK filename identifies its release. Verify the actual Pages deployment SHA and loaded PCK at the normal root URL. Test both multiplayer menu choices and singleplayer in that same browser instance. Keep full authenticated multiplayer lifecycle testing distinct from standalone WebRTC/scene tests.

## Apply Supabase migrations

The project is linked at `gravity-run/supabase/.temp/project-ref`. Do not assume
that `supabase` is on `PATH`: on this workstation the CLI has been run from a
temporary directory using the official Supabase GitHub release matching the
version recorded in `gravity-run/supabase/.temp/cli-latest`.

1. From the source repo, inspect the linked database before changing anything:

   ```powershell
   supabase migration list --linked --workdir 'E:\Utveckling\Gravity Run\gravity-run'
   ```

   Compare local and remote versions. Each migration timestamp must be unique
   locally, and all already-applied remote migrations should have their matching
   local files. Never run `db reset` against the linked production project.
2. If a new migration collides with an already-used timestamp, give it a new,
   unused timestamp before proceeding. If the remote has migrations that are
   absent locally, stop and reconcile the history first; do not blindly run
   `migration repair` or push duplicate SQL.
3. Preview the exact work, then apply only pending migrations:

   ```powershell
   supabase db push --linked --dry-run --workdir 'E:\Utveckling\Gravity Run\gravity-run'
   supabase db push --linked --workdir 'E:\Utveckling\Gravity Run\gravity-run'
   supabase migration list --linked --workdir 'E:\Utveckling\Gravity Run\gravity-run'
   ```

   Confirm the final listing shows the new migration on both local and remote.
   The CLI may be invoked by its full path when it is only unpacked in `%TEMP%`;
   do not install or change global PATH just for a deployment.

## Source and web release checklist

1. Run the relevant headless Godot tests and `git diff --check`. Review
   `git status`; do not stage user-created untracked files or generated scratch
   files. Commit the intended source files and migration on the current source
   branch, then push that branch to Azure `origin` (never force-push).
2. Export the Web preset to a fresh temporary directory outside the source repo.
   Godot's exit code alone is not enough: verify the export contains non-empty
   `index.html`, `index.js`, `index.wasm`, and `index.pck`. If Godot reports the
   export templates cannot be opened under AppData, rerun the export with access
   to the installed Godot 4.7.2 templates; do not publish an incomplete folder.
3. Verify the Pages clone at `E:\Utveckling\gravity-run-pages` is on `main` and
   clean before copying. Copy the export contents into `docs/game-v2/`, preserving
   root-shell features and unrelated Pages paths. For a planned integration change, review the specific shell/manifest/redirect edits before staging them.
4. Stage `docs/game-v2` and any explicitly reviewed integration paths, inspect
   `git diff --cached --name-only`, and verify the exact allowlist. Commit and push `main` to Pages
   `origin` without force-pushing. Verify the deployment at
   `https://hjelmdev.github.io/gravity-run/` after Pages finishes publishing.
