# Changelog

## Unreleased

### Added

- `mix nidhox`: the game in the terminal from the player's own data file
  (`Nidhox.Assets`), its rooms running on `Cauldron2D.GameMaker` (`Nidhox.Game`) and
  drawn at the pane's size (`Nidhox.Client`); `--area`, `--name` (default
  `fencer@<host name>`), `--port`.
- Two sides at one keyboard, or a controller each, and watchers; `Nidhox.Controls` for
  each side's keys and the controllers.
- The game's screens and menus in its own rooms, sprites and fonts (`Nidhox.Flow`,
  `Nidhox.Screen.*`): the logos, the title with "press start", the main menu, OPTIONS
  (SFX and MUSIC on and off, CONTROLS to remap PLAYER 1 or PLAYER 2), CREDITS from the
  copy's `credits.txt`, the level select panning across the copy's map, the pause, and
  the results — CONTINUE, WATCH REPLAY (the bout again from its recorded inputs, with
  SKIP THIS), BACK TO MAIN MENU.
- SINGLE PLAYER through every area against the computer; OFFLINE VERSUS in the area
  chosen; TOURNAMENT for 3 to 8 players at one machine (`Nidhox.Tournament`,
  `Nidhox.Screen.Ladder`); ONLINE VERSUS host-as-server over the local network
  (`Nidhox.Online`).
- The level select's VARIANTS (NO SWORDS, THROWS ONLY, SUDDEN DEATH ONLY, LOW GRAVITY,
  TURBO MODE, SLOW MODE, BOOMERANG SWORDS) and TIME LIMIT (none, 1, 2, 3 or 5
  minutes), set as the game's own `System` switches (`Nidhox.Rules`).
- The fencer from the game's own code (`Nidhox.Man`): its state machine, physics,
  collisions, body (`FleshCollisionMask`, tinted by `getPlayerColor`) and sword
  (`HeldWeapon`), thrown, dropped and lying swords, impaling, disarming, punches, kicks,
  dives, climbing, hanging and the heart; see `FENCER_PORT.md`.
- The match from the game's own code (`Nidhox.Objects.Match`, `Nidhox.Bout`): the
  frame (`updateMatchFrame`), input kept per frame, the faceoff, spawning and respawns,
  the right of way and its arrow, the camera, the clock and sudden death, statistics,
  the blood bank, room transitions (`FinalFantasyVIIITransition`), and the Nidhogg
  that eats the winner at the area's end.
- The computer player from the game's own code (`Nidhox.Objects.Brain`,
  `Nidhox.Brain`): its plans, its 31 actions, its personalities and their chances, its
  beat, and its buttons read by the match a frame late.
- HOW TO PLAY from the game's own code (`Nidhox.Objects.Tutorial`,
  `Nidhox.Tutorial.Lessons`): sixteen lessons against a computer partner, each
  instruction typed out by the game's `DialogBox`, the crowd cheering at the last one
  (`CheerControl`), and the finish line.
- Sounds that follow what makes them (`Nidhox.Objects.Ear.attach/3`): looping sounds
  kept where their instance is and let go once it is gone.
- Squirrels, cats and birds from the game's own code (`Nidhox.Objects.Animals`):
  squirrels and cats wander, hop and rest; birds take off, fly between perches and land.
- Scenery from the game's own code: the moving backdrop, parallax, the moon, the wind
  surface, the title's colour, sway and grass, grass that flattens and rises, doors and
  the castle's facades, the chandelier, conveyors, smashers, the mines' camera, cloud
  platforms and puffs, spawn areas, water.
- The rooms' standing sounds: wind, fire, the mines' drone, the waterfall and its edges
  (`Nidhox.Objects.Ambience`); every sound of the copy decoded ahead of play
  (`Nidhox.Sounds`).
- Music from the player's copy: each area's title track on the title, menus and
  results, and its layers during the bout (`Nidhox.Music`).
- Each bout's result kept in NidhOX's ledger through `Cauldron2D.Worlds` and
  `Cauldron2D.Ledger.Recorder`.
- `PARITY.md`, the list of what still differs from Nidhogg, and `tools/yyc`, which reads
  the player's own `Nidhogg.exe` and `data.win` (`mix run tools/gaps.exs`).

### Fixed

- Blocks are no longer drawn as white rectangles; the castle's walls no longer show a
  stone fill the original does not have; the sky no longer shows cloud banks the
  original keeps hidden.
- The level select pans across the copy's painted map to the selected area under its
  name plate.
- Side 2 plays from the right of the keyboard again.
- The moon is its plain disc, with the wind surface's clouds streaking across it and
  the sky, added to what is beneath them as the original adds them.
- A fencer no longer clips through the ground or is pushed through it by the other.
