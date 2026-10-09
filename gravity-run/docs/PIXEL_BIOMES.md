# Pixelstil för biom

Ängen är det första biomet i pixelstil. Allt som går att dela ligger i en gemensam grund, så
ett nytt biom är främst en **palett** plus det som är unikt för just det biomet.

## Det gemensamma

| Del | Fil | Vad den gör |
|---|---|---|
| Palett | `biomes/pixel_palette.gd` (`PixelPalette`) | Biomets färger och val: mark, hinder, bakgrund. Standardvärdena är ängens. |
| Markgenerator | `tools/pixel_tiles/generate_biome_tiles.gd` | Ritar ytrutorna (åtta varianter) och fyllnadstexturen ur paletten. |
| Hinder | `hazards/pixel_hazard_art.gd` (`PixelHazardArt`) | Stenpelare, spikar, sågklinga, fallande sten, tunnor. Ritas i hindrets exakta storlek och cachas per palett. |
| Bakgrund | `BiomeRenderer._draw_pixel_backdrop` | Himmel i band, sol, moln, bergsrygg, kullar, träd. Varje del kan stängas av i paletten. |
| Renderare | `BiomeDefinition` | Fyllnadstextur under ytan, pixelskarpa rutor och rutor som sticker upp över ytan. |
| Gemensamt för alla | `collectibles/pixel_coin.gd`, `campaign/gravity_star.gd`, `campaign/finish_line.gd` | Mynt, stjärnor och målflagga ser likadana ut överallt. |

Pixelstilen slås på av **`BiomeDefinition.pixel_palette`**. När ett låst kampanjbiom har en
palett får hindren utseendet `"pixel"` (i `main.gd`), och sågklingor, trappstegens spikar och
nedgrävda stenar läser paletten via `BiomeRenderer.locked_pixel_palette()`. Ingen kod kollar
efter ett visst biomnamn.

## Nytt biom i pixelstil

1. **Palett:** skapa `assets/biomes/<id>/<id>_palette.tres` med `PixelPalette` och ändra bara
   det som skiljer från ängen. Exempel för en snövärld: `surface*` blir snö, `fill*` blir is,
   `growth*` blir frost, `trees = false`, andra `sky_bands` och `seed_offset = 1`.
2. **Mark:** kör generatorn. Den skriver `<id>_surface.png` och `<id>_dirt.png`.
   ```
   godot --headless --path . -s res://tools/pixel_tiles/generate_biome_tiles.gd -- <id>
   ```
3. **Tileset:** kopiera `assets/biomes/meadow/meadow_tileset.tres` och peka om texturen.
4. **Biomdefinitionen:** sätt `pixel_palette`, `tile_set`, `tile_world_size = (64, 40)`,
   `tile_rise = 8`, `pixel_art = true`, `terrain_fill_texture`, `draw_edge_line = false` och
   ytrutornas atlaskoordinater (som i `meadow.tres`).
5. **Kontroll:** ta skärmdumpar med
   ```
   godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/pixel_tiles/meadow_capture.tscn -- <mapp> <bana> [tick mellan bilder] [antal] [första tick]
   ```

## Det unika per biom

Det som inte passar i en palett skrivs för biomet: egna hinder (lava, spöken, istappar),
skriptade inslag, väder (ängens kronblad, grottans damm) och bossar. Behöver ett biom en annan
form på något gemensamt, till exempel kantigare kullar, lägg hellre till ett val i paletten än
en ny kopia av koden.
