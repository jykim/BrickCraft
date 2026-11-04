# BrickCraft world-building template

Use this document before implementing a themed shared world. Fill in the short design brief
first, then keep the lifecycle and test sections beside the code while building it. A world in
BrickCraft is a region in the shared Luanti map, not a separate Luanti save. Its coordinates must
therefore be relative to `w.x, w.z`, and its saved state belongs on the world record or in mod
storage keyed by `w.id`.

Delete prompts that do not apply. A small world does not need every system below.

The in-game **Make a new world** menu is the quick version of this template. Terrain and style
change the generated starter landscape; character and event choices are saved as design themes
for later building or feature-specific mechanics. The shared Train Yard, Technic Lab, War Lab,
Siege Castle, Tower Defense, and Kart Circuit worlds remain the places with their complete coded
activities.

## 1. Identity and promise

- **Working name:**
- **World-list name:**
- **Owner:** `BrickCraft` / a player / other
- **One-sentence fantasy:** “Players are …”
- **Primary activity:** build / explore / race / defend / experiment / role-play / other
- **What makes this different from Workshop:**
- **Expected visit length:**
- **Audience and difficulty:**
- **Experimental label needed:** yes / no
- **Success, failure, or free-play outcome:**

## 2. Terrain

- **Footprint:** radius or bounds relative to the world center. Keep normal content inside the
  world's 128-node square; the stock landscape reaches about ±46.
- **Ground:** keep Workshop baseplate and landscape / replace it / modify selected areas
- **Topology:** flat / rolling hills / cliffs / islands / tunnels / layered or elevated routes
- **Zones:** name each area and explain its gameplay purpose.
- **Paths and flow:** where players start, where they notice the first objective, and how they
  travel between landmarks.
- **Landmarks and sightlines:** what helps a player orient without opening a menu?
- **Vertical range:** lowest and highest authored node; include room above for lighting.
- **Boundaries:** scenery, walls, water, fall recovery, or a natural loop back.
- **Hazards:** water, drops, traps, moving objects, enemies, or none.
- **Harvesting and building:** what may players collect, remove, or build over?
- **Protected cells:** floor, roads, track, event machinery, spawn area, or none.
- **Connections to other worlds:** portal, road, railway, none. A route outside the world's
  square needs an explicit reservation so a later world cannot cover it.
- **Generation strategy:** individual `set_node` calls for a small feature, or VoxelManip for a
  large field. State what existing terrain is cleared and what must be preserved.

## 3. Style

- **Theme and era:**
- **Mood:** playful / adventurous / peaceful / tense / mysterious / other
- **Palette:** primary, secondary, accent, team, danger, and neutral colors
- **Materials and textures:** reuse existing BrickCraft nodes where possible; list new nodes.
- **Shape language:** blocky, rounded, mechanical, fortified, organic, fast, tall, etc.
- **Architecture:** recurring building types, rooflines, props, and scale.
- **Lighting and weather:** daylight, lamps, smoke, particles, water, or special atmosphere.
- **Motion:** trains, gears, crowds, flags, karts, projectiles, or ambient animation.
- **Sound:** arrival, interaction, event, success/failure, and ambient cues.
- **Readability rules:** how roads, teams, hazards, interactables, and objectives differ at a
  glance. Do not rely on color alone for an essential distinction.

## 4. Characters

For each role, fill in:

| Role | Look/team | Spawn point | Purpose | Behavior | Player interaction | Defeat/despawn | Saved? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Guide/host | | | | | | | |
| Ally | | | | | | | |
| Rival/enemy | | | | | | | |
| Vehicle or creature | | | | | | | |

Also decide:

- Who appears when the world is empty? Avoid persistent entities that do not need to exist.
- Are characters shared by everyone, assigned to a player, or assigned to a team?
- What happens after server restart, player disconnect, defeat, or a world reset?
- What names, dialogue, signs, HUD text, or help rows explain their role?
- Can characters collide with players, builds, vehicles, or one another?

## 5. Events and world loop

- **Idle state:** what is happening before players act?
- **Trigger:** arrival / timer / button / command / entering a zone / interacting with an object
- **Participants:** everyone in the world / one player / teams / spectators
- **Phases:** setup → countdown → active play → result → recovery, or another sequence
- **Core loop:** what players repeatedly decide and do.
- **Dynamic changes:** doors, waves, traffic, machines, weather, destructible structures, etc.
- **Resources:** score, lives, gold, ammunition, laps, bricks, cooldowns, or none.
- **Scaling:** player count, difficulty choice, elapsed time, wave number, or fixed.
- **Win/fail conditions:**
- **Rewards and consequences:**
- **Reset:** automatic / command / panel; what resets and what player-built work survives?
- **Join in progress:** role, spawn location, and state shown to a late player.
- **Leave/reconnect:** whether the event pauses, continues, or releases that player's assets.
- **No-player behavior:** stop expensive simulation; decide whether timers continue logically.

## 6. Structures, objects, and rules

- **Signature structures:**
- **Interactive objects:** button, lever, panel, vehicle, chest, station, tower pad, etc.
- **Routes:** track, road, lane, patrol path, coaster path, or racing spline.
- **Construction rules:** normal / Strict LEGO compatible / building restricted in some zones
- **Destruction rules:** permanent, staged damage, temporary, automatically repaired, or immune
- **Inventory changes:** new parts, temporary event tools, pickups, and cleanup.
- **Commands and formspecs:** include an in-world way to discover them.
- **Recovery:** `/home`, unstick, vehicle reset, respawn, out-of-bounds, and corrupt-state fallback.

## 7. Multiplayer and accessibility

- Is the authoritative state per world, per player, or per team?
- Can two events run at once? If not, how does a second start request respond?
- How are simultaneous interactions and disconnects resolved?
- What may a spectator change?
- Are player-built nodes preserved during layout updates and resets?
- Which cues need text or shape in addition to color and sound?
- Can the activity be completed with keyboard controls and with the documented trackpad controls?
- Which timings, camera movements, flashing effects, or precision actions need an assist option?

## 8. Persistence and upgrades

- **World marker:** a unique boolean field such as `w.moonbase`.
- **Built marker:** a field such as `w.moonbase_built`; this is separate from core `w.built`.
- **Layout version:** integer if later releases may add or migrate content.
- **Durable state on `w`:** small, serializable facts needed by other mods or startup recovery.
- **Durable state in mod storage:** larger/per-player values, keyed with `w.id`.
- **Runtime-only state:** entities, timers, caches, current participants, and transient damage.
- **First build policy:** which terrain and Workshop fixtures may be replaced?
- **Upgrade policy:** identify this world's own nodes and replace only those or air. Preserve
  unrelated player builds unless the design explicitly promises a full reset.
- **Interrupted build:** startup must detect and finish a layout whose callback did not complete.
- **Entity restoration:** spawn runtime entities only after a player is nearby and the area is
  loaded; saved nodes already restore themselves.

## 9. Implementation scaffold

Put a self-contained feature in the mod that owns its mechanics. Use one unique marker on the
world record rather than finding it by display name. This skeleton follows Train Yard, Technic
Lab, War Lab, Tower Defense, and Kart Circuit:

```lua
local C = core
local worlds, save_worlds = brickcraft.worlds(), brickcraft.save_worlds
local WORLD_KEY = "moonbase"
local LAYOUT_VERSION = 1
local R = 24

local function themed_world()
  for _, w in ipairs(worlds) do
    if w[WORLD_KEY] then return w end
  end
end

-- Every authored position is relative to w.x, w.z. For a large layout, use VoxelManip
-- and record which node names belong to this world so upgrades preserve player builds.
local function build_layout(w, first)
  -- Example: C.set_node({x=w.x + 8, y=0, z=w.z - 4}, {name="brickcraft:navy"})
  -- `first` may clear the chosen footprint; upgrades should normally alter only owned
  -- nodes or air.
  w.moonbase_built = true
  w.moonbase_version = LAYOUT_VERSION
  save_worlds()
end

local function emerge_and_build(w, first)
  C.emerge_area(
    {x=w.x-R, y=-2, z=w.z-R},
    {x=w.x+R, y=31, z=w.z+R},
    function(_, _, remaining)
      if remaining == 0 then build_layout(w, first) end
    end
  )
end

C.after(0, function()
  -- Match the owning mod's test setting so ordinary disposable test worlds stay small.
  if brickcraft.testing and not C.settings:get_bool("brickcraft_moonbase_test", false) then
    return
  end

  local w = themed_world()
  if w then
    if w.built and (not w.moonbase_built or (w.moonbase_version or 0) < LAYOUT_VERSION) then
      emerge_and_build(w, not w.moonbase_built)
    end
    return
  end

  w = brickcraft.make_world("Moon Base (experimental)", "BrickCraft", function(built)
    build_layout(built, true)
  end)
  C.log("action", "BrickCraft Moon Base " ..
    (w and "being made at " .. w.x .. "," .. w.z or "has no room"))
  if w then
    w[WORLD_KEY] = true
    save_worlds()
  end
end)
```

Add runtime behavior separately:

- A slow `globalstep` may check for nearby players, as Train Yard does, but should return early
  when the world is empty.
- Keep current matches/races/waves in a table keyed by `w.id`, as Tower Defense does.
- Derive authored paths from relative coordinates, as Technic Lab and Kart Circuit do.
- Add help rows to `brickcraft.help`, a world-checked chat command, and an interaction or panel
  that exposes the same controls.
- Export only the small API other mods or tests actually need.

## 10. Test plan and definition of done

### Automated

- The world is created once, receives a unique center, and is found by its marker.
- Its layout completes only after the area emerges and its built/version markers are saved.
- Representative terrain, landmark, route, and protected-floor cells have the expected nodes.
- Coordinates still work when the world is not in the first available map square.
- A restart neither duplicates one-time objects nor loses required runtime objects.
- An upgrade preserves a player brick in the footprint while updating owned nodes.
- Event start, phase changes, win/fail, reset, late join, disconnect, and empty-world shutdown work.
- Two players see the same shared state; simultaneous input cannot duplicate rewards or vehicles.
- Out-of-bounds, stuck, or destroyed-critical-object recovery works.
- The dedicated test setting does not create all unrelated shared worlds.

### Playtest

- A new player can identify the first activity and begin without a developer explaining it.
- Landmarks make the route and home direction understandable.
- Important objects, teams, and hazards remain distinguishable without relying only on color.
- Controls work with the project's documented keyboard and trackpad paths.
- Two players can join, leave, and rejoin without confusing ownership or state.
- Performance remains comfortable at the busiest intended moment.

The world is done when its promise in section 1 is recognizable in play, recovery and restart are
safe, the layout can be upgraded without erasing unrelated builds, and both automated checks and
a short multiplayer playtest pass.

## 11. Patterns from existing worlds

| Existing world | Reusable lesson |
| --- | --- |
| Workshop and player worlds | Start from a consistent baseplate, material stacks, hills, trees, protected floor, home position, and relative world center. Only fill air when enriching saved scenery. |
| Train Yard | Add a small authored feature after the base world, spawn expensive entities only when a player approaches, save one-time spawn flags, and reserve any connection that crosses world squares. |
| Technic Lab | Build a curated exhibit from paths and relative coordinates; use an integer layout version to upgrade older worlds; restore ride vehicles near players rather than saving entities. |
| War Lab | Layer a lightweight theme over the stock landscape, migrate one added zone independently, and respawn unsaved practice characters while the world is occupied. |
| Siege Castle | Define a complex structure with one deterministic cell function, distinguish world-owned nodes from player builds, support staged destruction and explicit reset, and recover players trapped by an update. |
| Tower Defense | Replace a whole arena on first build, preserve player nodes on later layout passes, keep each world's live game in a table keyed by world id, and design explicit phases, teams, resources, waves, and reset. |
| Kart Circuit | Generate a large deterministic route, derive roads and scenery from data, version the layout, preserve later player construction, and provide assist and reset controls for a movement-heavy activity. |
