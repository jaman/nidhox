# Changelog

## Unreleased

### Added

- Fencing: stances, thrusts, parries, disarms, thrown swords, punches and picking a
  sword up (`Nidhox.Fencer`, `Nidhox.Duel`), on the room's ground (`Nidhox.Terrain`).
- Bouts across an area's rooms: the right of way, respawning ahead of the runner, the
  camera following it, room changes and winning at the goal (`Nidhox.Match`); `--area`.
- NidhOX's own fencers and swords (`Nidhox.Art`, `Nidhox.Look`), and the banner.
- `mix nidhox`: the game in the terminal from the player's own data file
  (`Nidhox.Assets`), its rooms running on `Cauldron2D.GameMaker` (`Nidhox.Game`) and
  drawn at the pane's size (`Nidhox.Client`).
- Two sides at one keyboard, or a controller each, and watchers; `Nidhox.Controls` for
  each side's keys and the controllers.
- `Nidhox.Code`, the table of the game's code, built from object modules.
