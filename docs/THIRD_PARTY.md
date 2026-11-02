# Sources and licensing

Verified 2026-10-31 on macOS arm64.

## Runtime selected: Luanti 5.17.0, official Apple Silicon app

- Downloads: https://www.luanti.org/en/downloads/
- Exact official archive: https://github.com/luanti-org/luanti/releases/download/5.17.0/luanti_5.17.0_macos12.3_arm64.zip
- SHA-256 (matches Homebrew cask): `0ba118b537d3cc6fd07cd2268fef25e515fc6d87c27ad69b476144a8e28dba3c`
- Homebrew cask: https://formulae.brew.sh/cask/luanti
- Corresponding source: https://github.com/luanti-org/luanti/tree/5.17.0
- Engine: LGPL-2.1-or-later; engine media have their own CC BY-SA / other notices. Full upstream notice is preserved in `LUANTI-LICENSE.txt`.
- Unmodified app is kept under `runtime/luanti.app`, ignored by Git. No Gatekeeper/quarantine or security setting was disabled. No global app installation was made.
- GitHub latest-release API reported 5.18.0 with Windows assets, while the official macOS download/Homebrew cask offered 5.17.0. We intentionally pinned the verified macOS release.

## Base comparison

| Candidate | Maintenance / compatibility | Licensing | Decision |
| --- | --- | --- | --- |
| Minetest Game | Official, maintenance-only, rolling releases target latest stable engine | LGPL-2.1 code, CC BY-SA 3.0 media with per-mod notices | Good survival/modding foundation; many unused nodes, crafts and systems for this small brick workshop |
| Luanti DevTest | Bundled engine feature/regression test game | Engine repository's source/media licenses | Reference only; testing content is unsuitable as the player-facing game |
| Original minimal standalone game | One local mod, stable documented Lua API, tested with 5.17.0 | Original code, textures and block-person mesh under MIT | Selected: zero external game/mod dependencies; smaller maintenance and attribution surface |

MTG sources: https://github.com/luanti-org/minetest_game and https://github.com/luanti-org/minetest_game/blob/master/LICENSE.txt

API references used: https://api.luanti.org/games/ and https://api.luanti.org/

## Mesecons (bundled, unmodified)

- Source: https://github.com/minetest-mods/mesecons at commit `aca87dbd448637d2dc80e59e909425932acd6c84` (2026-09-08).
- Included submods, unmodified, in `game/mods/mesecons/`: `mesecons`, `mesecons_gamecompat`, `mesecons_wires`, `mesecons_button`, `mesecons_receiver`, `mesecons_luacontroller`, `mesecons_mvps`, `mesecons_pistons`. The upstream `COPYING.txt`, `LICENSE.txt` and `README.md` are kept beside them.
- Licenses: code LGPL-3.0; textures, sounds and documentation CC BY-SA 3.0, © 2011-2016 Mesecons Mod Developer Team and contributors. BrickCraft's own MIT code only calls its public API (`mesecon.*`, node definitions' `mesecons` field) and stays a separate work.
- To update, replace those folders with a newer upstream commit as a whole and record the commit here.

## Original assets

`tools/generate_assets.py` generates all BrickCraft textures and the generic block-person OBJ from original geometric definitions using Python's standard library. No trademark logos, copied minifigure models, branded studs, Minecraft textures or Office Doom assets are included. The 2×2 brick label describes the visual stud layout, not a certified physical part or connection model.

## Office Doom read-only comparison

Inspected `/Users/lifidea/dev/AI4G/cyber-doom/README.md` (Three.js) and `/Users/lifidea/dev/AI4G/cyber-doom-godot/README.md` (Godot 4.7). They focus on FPS movement, weapons, NPCs and office themes. A brick world would still need editable voxel storage, placement/removal, inventory and persistence implemented there. Luanti provides those engine primitives already. No files in either Office Doom project were modified, imported or executed.

## Kart racing references

The kart mod (`game/mods/brickcraft_kart`) is original MIT code; no code, model, texture or sound was copied. These were read for ideas (checked 2026-11-02):

| Project | License | What it gave us |
| --- | --- | --- |
| [Automobiles Pack](https://github.com/APercy/automobiles_pck) (APercy) | MIT | Driving model: speed split along / across the car, sideways drag as grip, steering limited by `1 - 1/(speed + 1)` |
| [PanqKart](https://github.com/Panquesito7/panqkart) (Panquesito7) with lib_mount / vehicle_mash | code LGPL-2.1 (lib_mount), media partly non-free | Race flow: lobby, 3-2-1-GO countdown, ordered checkpoints for laps, wrong-way warning, results table |
| [checkpoints](https://github.com/APercy/checkpoints) (APercy) | MIT | Start lights at the start line |
| [MineKart](https://content.luanti.org/packages/wsor4035/minekart/), [Kart Car](https://content.luanti.org/packages/apercy/kartcar) | see ContentDB | Surveyed; reviews asked for CPU racers and laps, which we added |
| Cubic Racers (Minecraft Forge) | see CurseForge | The banana that spins a kart out (none of the Luanti mods have one) |
