# Värld 5–7: Frostfjället, Molnriket, Öknen

Beslut 2026-10-09: Adam valde alla tre. De byggs i den ordningen, var och en spelbar och
committad innan nästa. Punkterna märkta **(förval)** har Adam inte bestämt.

Samma mall som värld 2–4: sex banor och en boss per värld, data i `CampaignCatalog`, frysta
seeds och stjärnor från `campaign_level_tool.gd`, pixelvärld via palett
(`docs/PIXEL_BIOMES.md`), egen musik (`tools/audio/generate_world_music.gd`) och en kartbild.
**Generatorn ändras inte.** Varje värld genereras med ett befintligt generatorbiom och ritas
med ett eget presentationsbiom; allt nytt är skriptade inslag eller skins.

| Värld | Generatorbiom | Presentation | Musik (förval) | Upplåser (förval) |
|---|---|---|---|---|
| 5 Frostfjället | cave (har istappar) | `frost_campaign` | 136 BPM, ljus klockspel, f-moll | Bambu (panda) |
| 6 Molnriket | classic | `clouds_campaign` | 116 BPM, luftig, durig | Hopp (groda) |
| 7 Öknen | classic | `desert_campaign` | 148 BPM, frygisk dominant, darbuka | Axel (axolotl) |

## Värld 5: Frostfjället
- **Utseende:** snö på is, granar, snötäckta toppar, ljus vinterhimmel.
- **Inslag:**
  1. *Snöbollar* (skin): tunnorna rullar som snöbollar.
  2. *Lavin*: som Grottans ras men med snöblock och snödamm som varning.
  3. *Snöstorm*: bara utseende, som askregnet.
- **Boss: Snöjätten.** Rullarens schema: kastar snöbollar (tunnor), river ner istappar (stenar).
  Svag punkt: en isplatta i golv eller tak.

## Värld 6: Molnriket
- **Utseende:** solnedgångshimmel, molnmark (vita molntoppar på ljus fyllning), svävande öar.
- **Inslag:**
  1. *Blixtnedslag*: varning i en fil, sedan slår blixten ner där (glödbombens tidning).
  2. *Vindbyar*: bara utseende (vindstreck), så generatorn och fysiken är orörda. **(förval)**
- **Boss: Åskfågeln.** Blixtar i solfjäder och takspikar; fjäderplatta som svag punkt.

## Värld 7: Öknen
- **Utseende:** sanddyner, kaktusar, en het blek himmel med stor sol.
- **Inslag:**
  1. *Kaktusar* (skin på spikar).
  2. *Sandstorm*: bara utseende, som dimman (hinder nära löparen syns alltid).
  3. *Kvicksandsfall*: sten som faller som sandkorn (stenens tidning).
- **Boss: Sandmasken.** Reser sig ur sanden som Magmaormen; sandbomber och block.

## Arbetsordning per värld
1. Banor i katalogen, seeds och stjärnor, `gap_conflicts`.
2. Palett, mark och bakgrund (`generate_biome_tiles.gd`).
3. Inslag och skins.
4. Boss med testbot.
5. Musik och kartbild, upplåsning, översättningar, test.
