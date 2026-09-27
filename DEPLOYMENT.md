# Gravity Run web deployment

The Godot source project is in `gravity-run/` and is pushed to the Azure DevOps repository. The public GitHub Pages repository is a separate, export-only repo: `https://github.com/hjelmdev/gravity-run.git`.

Keep the persistent local clone of the Pages repo at `E:\Utveckling\gravity-run-pages` (branch `main`), outside the user's profile and separate from the Azure source repo. Do not use a Temp/AppData clone as the working copy. Older clean deployment clones, if retained, belong under `E:\Utveckling\gravity-run-pages-archive`.

## Publish a web build

1. Export the `Web` preset from `gravity-run/project.godot` to a temporary folder **outside the Azure source repo**. With this machine's Godot install, the command is:

   ```powershell
   & 'E:\Utveckling\Godot_v4.7.2-stable_win64.exe' --headless --path 'E:\Utveckling\Gravity Run\gravity-run' --export-release Web '<temporary-export-folder>\index.html'
   ```

2. Clone or update `hjelmdev/gravity-run` on branch `main`, then copy the exported files into that clone's `docs/game-v2/` folder.
3. Keep the Pages shell at `docs/index.html` intact. It supplies the orientation prompt/cache refresh and loads `docs/game-v2/index.html` in an iframe. Do not replace the shell with Godot's generated `index.html`; do not alter `docs/game/` or other Pages files for a normal game export.
4. Stage only the game export and verify the staged paths before committing:

   ```powershell
   git add -- docs/game-v2
   git diff --cached --name-only
   ```

   Every staged path must start with `docs/game-v2/`. Commit and push `main` to `origin`; never force-push.
5. If Git has no configured identity, the Pages repo's existing commit identity is `Adam Hjelm <hjelm.adam@gmail.com>`. Apply it only to the deploy commit with `git -c user.name=... -c user.email=...`; do not change global Git configuration.

No cache-busting `?v=` URL is needed: the existing shell handles its own cache refresh. Test the normal Pages URL after GitHub Pages finishes deploying.

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
   `docs/index.html` and every other Pages path.
4. Stage only `docs/game-v2`, inspect `git diff --cached --name-only`, and verify
   every staged path starts with that prefix. Commit and push `main` to Pages
   `origin` without force-pushing. Verify the deployment at
   `https://hjelmdev.github.io/gravity-run/` after Pages finishes publishing.
