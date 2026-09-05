# Art, font and sound credits

Every file in this directory is downloaded or composed by `tools/fetch_assets.sh`; nothing here was
drawn for this project. The title screen points players at this file.

## Liberated Pixel Cup character sprites

Source: the [Universal LPC Spritesheet Character Generator](https://github.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator)
(`spritesheets/` directory), part of the [Liberated Pixel Cup](http://opengameart.org/content/lpc-collection)
collection on OpenGameArt.org.

Each layer is individually licensed by its authors. `CREDITS-lpc.csv` lists, for every layer this game
uses, the authors, the licenses offered (OGA-BY 3.0, CC-BY-SA 3.0, GPL 3.0, and for single layers
CC0 and GPL 2.0) and the OpenGameArt/GitHub pages they came from. Please credit those people, not this
repository, if you reuse the art.

| composed file | LPC layers (bottom to top) |
|---|---|
| `otto.png` | body/bodies/male, legs/pants/male, torso/clothes/longsleeve/male, head/heads/human/male, hair/bedhead |
| `imma.png` | body/bodies/female, legs/skirts/plain/thin, torso/clothes/longsleeve/female, head/heads/human/female, hair/bob |
| `lina.png` | body/bodies/female, legs/pantaloons/thin, torso/clothes/shortsleeve/female, head/heads/human/female, hair/bangs |
| `gino.png` | body/bodies/male, legs/pants/male, torso/clothes/shortsleeve/male, head/heads/human/male, hair/balding |
| `skeleton.png` | body/bodies/skeleton |
| `zombie.png` | body/bodies/zombie |
| `reaper.png` | body/bodies/skeleton, hat/cloth/hood, then darkened |
| `mudman.png` | `zombie.png` tinted green |
| `ghost.png` | `zombie.png` bleached and made translucent |

The composed and recoloured PNGs are derivative works and are distributed under
[CC-BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). Attribution for them:

> Liberated Pixel Cup character art by Johannes Sjölund (wulax), Michael Whitlock (bigbeargames),
> Matthew Krohn (makrohn), Nila122, David Conway Jr. (JaidynReiman), Carlo Enrico Victoria (Nemisys),
> Thane Brimhall (pennomi), laetissima, bluecarrot16, Luke Mehl, Benjamin K. Smith (BenCreating),
> MuffinElZangano, Durrani, kheftel, Stephen Challener (Redshrike), William.Thompsonj,
> Marcel van de Steeg (MadMarcel), TheraHedwig, Evert, Pierre Vigier (pvigier), Eliza Wyatt (ElizaWy),
> Sander Frenken (castelonia), dalonedrau, Lanea Zimmerman (Sharm), Manuel Riecke (MrBeast),
> Barbara Riviera, Joe White, Mandi Paugh, Shaun Williams, Daniel Eddeland (daneeklu),
> Emilio J. Sanchez-Sierra, drjamgo, gr3yh47, tskaufma, Fabzy, Yamilian, Skorpio, Tuomo Untinen (reemax),
> Tracy, thecilekli, LordNeo, Stafford McIntyre, PlatForge project, DCSS authors, DarkwallLKE,
> Charles Sanchez (CharlesGabriel), Radomir Dopieralski, macmanmatty, Cobra Hubbard (BlueVortexGames),
> Inboxninja, kcilds/Rocetti/Eredah, Napsio (Vitruvian Studio), The Foreman, AntumDeluge, Ahmad3366.
> Per-file details: CREDITS-lpc.csv.

## LPC Base Assets (`bat.png`, `grass.png`)

Source: [Liberated Pixel Cup (LPC) Base Assets](https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles),
offered under CC-BY-SA 3.0, GPL 3.0 and OGA-BY 3.0. Full credits in `CREDITS-lpc-base.txt`.

- `bat.png` (`sprites/monsters/bat.png`): Charles Sanchez (CharlesGabriel).
- `grass.png` (`tiles/grass.png`): Lanea Zimmerman (Sharm).

## `koalio.png`

The Super Koalio character from the [libgdx](https://github.com/libgdx/libgdx) test suite
(`tests/gdx-tests-android/assets/data/maps/tiled/super-koalio/koalio.png`), Apache License 2.0.
Fetched via Zach Oakes' port in [paranim_examples](https://github.com/paranim/paranim_examples).

## `parakeet.png`

Three walk frames from Zach Oakes' [parakeet](https://github.com/paranim/parakeet) demo, joined side by side.
That repository carries no license file (its nimble file says `license = "FIXME"`), so treat this sprite as
a placeholder: replace it before distributing the game beyond a demo.

## `Roboto-Regular.ttf`

Roboto by Christian Robertson for Google, [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
Copied from the paranim examples.

## Sound (not in this directory)

There are no audio files. Every sound effect and the music are MIDI phrases rendered at startup by
[paramidi](https://github.com/paranim/paramidi). The instrument samples come from
[GeneralUser GS](https://schristiancollins.com/generaluser.php) by S. Christian Collins
(GeneralUser GS License v2.0), embedded from the `paramidi_soundfonts` Nim package.
