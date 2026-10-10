# Changelog

## Unreleased

### Added

- CHALLENGE on the main menu: the game's challenge mode (`Nidhox.Objects.Challenge`),
  every move scored as the game's `challengeMode_move_completed` scores it, its
  popups, its score and best score, and a computer opponent growing harder.
- The game's VARIANTS menu on the level select (`Nidhox.Rules`): its time limits (none,
  3:00 to 9:30) and thirteen switches, any number on at once.
- OPTIONS as the game's list: CONTROLS, flashing, persistent blood, and MUSIC and SFX
  sliders; the effects level scales the music as the game's master gain does.
- The game's own pause (`PauseController`), the screen's fade up out of black at every
  room start (`System.aperture`), and silence while paused (`mute`).
- `Nidhox.TileLayerCache`: a room's tile layers drawn once each and kept while the room
  is shown.

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
- SINGLE PLAYER as the game's own run (`Nidhox.Objects.Arcade`): sixteen levels on its
  progress map, each an area and a computer personality growing harder, "GAME
  COMPLETE" with the time; OFFLINE VERSUS in the area chosen; TOURNAMENT for 3 to 8 players at one machine (`Nidhox.Tournament`,
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
- The rooms' standing sounds from the game's code: wind, fire, the mines' drone, the
  waterfall and its edges, each room starting and stopping its own
  (`Nidhox.Objects.Ambience`); every sound of the copy decoded ahead of play
  (`Nidhox.Sounds`).
- More scenery from the game's code: the clouds' sun, tint, defensive walls and "Final
  Screen" text; the castle's burning sky, swinging lamps, chandeliers with their creak
  and the sudden death backdrop, crumbling stone; the mines' screws, smoke and worms
  with their tunnels; the wilds' rain, leaves, waterfall spray and warping foliage;
  windows that shatter; candle and torch flames; the crowd in the end rooms' stands and
  its cheer; the fencers' faint outlines; the placed instances' creation code
  (`Nidhox.Objects.InstanceCodes`) and the rooms' backgrounds changed by code
  (`Nidhox.Backgrounds`).
- Music from the player's copy as the game mixes it: the area's track the game's
  `MainMenuMusic` chooses on the title, menus and results, and during the bout its
  layers mixed by `LayeredMusic` (`Nidhox.Objects.LayeredMusic`, `Nidhox.Music.Mixer`)
  by the fencers' speed, each area's own rule and the end rooms' fade.
- Each bout's result kept in NidhOX's ledger through `Cauldron2D.Worlds` and
  `Cauldron2D.Ledger.Recorder`.
- `PARITY.md`, the list of what still differs from Nidhogg, and `tools/yyc`, which reads
  the player's own `Nidhogg.exe` and `data.win` (`mix run tools/gaps.exs`).

### Changed

- The menus are the game's own: one ring of choices turning under the logo
  (`Nidhox.Screen.MenuList`), drawn and sounded as the game's `MainMenu` draws them, its
  lists in the game's order, every one in the title room, VARIANTS under MULTIPLAYER and
  TOURNAMENT, and TOURNAMENT on the main menu with its PLAYERS and MAP. OPTIONS has the
  same look.
- The level select is the game's: up and down through the areas, the area's plate on
  the map, back to the main menu when left alone.
- The results are the game's match statistics, and any press goes on to the level
  select. WATCH REPLAY and BACK TO MAIN MENU are gone, as the game has neither.

- Side 2 plays the game's default keys: `M` attacks, `N` jumps, `Enter` starts.

### Fixed

- Music plays as the game plays it, from the game's own objects: the title's track
  (`MainMenuMusic`) only in the title room, three seconds after entering it, chosen by
  the level last played (the castle's at first), and each area's layers with its
  match, stopped when the match ends. The recordings play in stereo from their start,
  instead of folded to mono and played as a synthesizer's voice, and only the music
  in use is kept in memory.
- Quitting a bout from its pause, to the title or to change level, ends its match.

- A fencer's death has its computer player choose its next personality, as the game's
  `Man` destroy event does.

- Blocks are no longer drawn as white rectangles; the castle's walls no longer show a
  stone fill the original does not have; the sky no longer shows cloud banks the
  original keeps hidden.
- The level select pans across the copy's painted map to the selected area under its
  name plate.
- Side 2 plays from the right of the keyboard again.
- The moon is its plain disc, with the wind surface's clouds streaking across it and
  the sky, added to what is beneath them as the original adds them.
- A fencer no longer clips through the ground or is pushed through it by the other.
