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
