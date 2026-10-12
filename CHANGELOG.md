# Changelog

## Unreleased

### Fixed

- A player joined from another machine is sent the surfaces' operations, which their
  client replays onto its own copy, not the surfaces' pixels every frame: a frame to them
  is about 3 KB where it was about 1 MB.

### Changed

- How the picture reaches a terminal is chosen by the Cauldron client
  (`Cauldron2D.Drafter.Client.Picture`): `--picture` and `NIDHOX_PICTURE` set it for
  every player, ssh players included, `size:WxH` is accepted too, and the default stays
  `native:2,png,swap`.

### Added

- `--mute` (or `CAULDRON_MUTE=1`): no sound on this machine.


### Added

- `MIX_ENV=linux`: an environment of its own (`config/linux.exs`, each environment's
  config file read when present), so a Linux build in this checkout goes to
  `_build/linux` and its native code to the libraries' per-architecture folders, leaving
  the macOS builds alone.

- `mix nidhox --picture` (or `NIDHOX_PICTURE`): any of `native` (the room at its own
  size times the largest whole number that fits, or `native:N`), `png` and `swap`, comma
  separated, for how the picture reaches a kitty terminal; `native:2,png,swap` by
  default, `none` for none.

- The title's attract mode: left alone for 1200 steps, the title plays a match of the
  computer against itself in an area at random, the logo and a blinking "press start"
  over it, until a key is pressed or the match ends.
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
  COMPLETE" with the time; OFFLINE VERSUS in the area chosen; TOURNAMENT for 3 to 8 players at one machine (`Nidhox.Tournament`); ONLINE VERSUS host-as-server over the local network
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

- Hex package metadata: GPL-2.0-or-later (`LICENSE`), the GitHub link, and the packaged
  files listed (`lib`, `mix.exs`, `.formatter.exs`, the README, changelog and licence).
  The libraries are the sibling checkouts when present, else their Hex releases
  (`PLUMB_HEX` forces Hex).
- The depths objects are created at are read from the player's copy at startup
  (`Nidhox.ObjectDepths.read/2`, kept in `Nidhox.Assets`): from the `Nidhogg.exe` beside
  a `data.win`, or, for the macOS build's `game.ios`, from its objects themselves. A
  `data.win` without its `Nidhogg.exe`, or with one from another build, does not start.
  `Nidhox.ObjectDepths.table/0` is removed.
- The default player name is `fencer`; it was `fencer@<host name>`, which showed the
  machine's name to the other player online.
- The decompiled pseudocode under `docs/` is ignored by git.
- The pause menu shows "LEAVE GAME" instead of "QUIT TO TITLE SCREEN" to the player on
  another machine, since choosing it takes only them out of the game.
- `gamepad` comes through `cauldron_2d_drafter` and is no longer listed in `mix.exs`.
- The data file's default is set in `config/runtime.exs`: `NIDHOX_DATA`, else the first of
  the game's usual Steam installs under the home directory, Linux's included; `--data`
  overrides it. `Nidhox.Assets.candidates/0` is gone, and no script names a path of its own.

- The menus are the game's own: one ring of choices turning under the logo
  (`Nidhox.Screen.MenuList`), drawn and sounded as the game's `MainMenu` draws them, its
  lists in the game's order, every one in the title room, VARIANTS under MULTIPLAYER and
  TOURNAMENT, and TOURNAMENT on the main menu with its PLAYERS and MAP. OPTIONS has the
  same look.
- The level select is the game's: up and down through the areas, the area's plate on
  the map, back to the main menu when left alone.
- The results are the game's match statistics, and any press goes on to the level
  select; up or down turns their bottom line to "watch replay", NidhOX's replay of the
  bout. BACK TO MAIN MENU is gone, as the game has none.
- The logos and the credits are the game's: `sMesshofLogo` then `sDaedelus` fading in
  and out with "with music by", and the copy's credits rising in a slowly changing
  colour.
- TOURNAMENT is the game's single elimination tournament, run by the game's own
  `Tournament` in its rooms (`Nidhox.Objects.Tournament`, `Nidhox.Tournament`): the
  shuffled bracket with its byes, the ladder drawn as `drawBracketsListXYWH` draws it,
  the warm-up before each match in `rPreMatch` (`Nidhox.Objects.CountDowns`), the
  fencers in their tournament players' colours, and the champion's room with
  `sWinner` and the pyre in the champion's colour.
- Every match starts as the game's `startMatch` starts one, with its room transition
  (`Nidhox.Objects.Match.start_match/1`).

- Side 2 plays the game's default keys: `M` attacks, `N` jumps, `Enter` starts.

### Fixed

- `nidhox.log` takes notices too, so each ssh player's session start and end, and why
  an ssh connection was dropped, are recorded.

- HOST OVER SSH shows the command to connect with for each of this machine's networks,
  up to three, the home network first; it showed one address, which could be a VPN's
  the other player is not on.

- `mix nidhox` writes warnings and errors, a crashed ssh session among them, to
  `nidhox.log` in the game's data directory.
- A player over ssh whose game's world stops goes to the lobby, told "NidhOX
  stopped", instead of freezing on the last frame.
- A game whose terminal goes away quits, and the controller helper exits with it.
- `Esc` pauses a bout, the warm-up, the tutorial and challenge mode as the game's does
  (`keyboard_check_pressed(27)`), on the game's pause menu, which now also has OPTIONS;
  `q` no longer leaves the game and `p` no longer freezes it, `Ctrl+Q` quitting.
- `Esc` goes back on the title's menus, as jump does, and out of every ONLINE VERSUS
  screen — hosting, host over ssh, the host list and the address and code screens —
  stopping any hosting.
- The `Enter` that finishes typing a join code no longer reopens the typing at once,
  hiding how the join went; a failed join says why: nothing answering at the address,
  no game hosting there, or the code refused (`Cauldron2D.Distribution.join/3`).
- HOST OVER SSH on ONLINE VERSUS: the game served over ssh (`Cauldron2D.Drafter.Server`)
  on a port typed when hosting — any free one when left empty, filled in from
  `NIDHOX_SSH_PORT` or `mix nidhox --ssh-port` — the other player connecting with
  `ssh -p <port> new@<address>`
  and playing side 2 in this machine's game from their own terminal.
- When the other player leaves a game this machine hosts, over ssh or the network, a
  bout in progress is won by forfeit, the match ends, and the hosting screen comes back,
  still hosting on the same port and code, saying "the other player left", so the next
  player connects as the first did; their side no longer passes to this machine's
  keyboard.
- The other player choosing QUIT TO TITLE SCREEN from the pause of a game this machine
  hosts now leaves: a bout in progress is the host's by forfeit, their client quits —
  over ssh their session closes, terminal restored — and the hosting screen comes
  back, still hosting, saying "the other player quit". It took the host to the title
  and stopped hosting.
- A hosted game's level select no longer goes back to the main menu after 720 steps
  untouched, which stopped hosting and dropped the other player.
- A second copy of the game on the same machine joining the first plays as
  `"<name> (2)"`, instead of taking the host's player and freezing the host.
- Over ssh the game draws at 20 frames a second and skips frames a slow connection
  cannot carry, instead of falling behind; a player has 10 minutes to log in, ssh's
  host key question included.
- A player connected over ssh is disconnected when the host stops hosting — quitting
  to the title, going back, or quitting the game — their terminal restored and told
  "NidhOX: the host stopped hosting." (or "The server stopped." as the game quits),
  instead of left frozen on the last frame. `mix nidhox` stops the VM in order as it
  quits.
- A host's address and join code are typed on the keyboard (`Nidhox.Typing`, a menu the
  world asks the client to open), instead of picked a character at a time with the
  movement keys, which also typed nothing.
- Either side's keys work the options menu, and it has CONTROLLERS: each connected
  controller and the player it plays, movable between player 1, player 2 and none.
- The musician's logo flashes yellow, not black, as the game's `ShowLogos` draws it.
- The sky's side rooms show their wind faintly, as the game's `DarkenClouds` sets it
  (a `"swirly"` wind surface tinted at alpha 0.1, backgrounds 0 and 1 tinted with it);
  the cloud tiles take the clouds' own tint.
- The sky's cloud bridge (`NewCloudBlock`) is drawn, breathing as the game draws it;
  the sun sinks as it moves off the room's middle (`Sun`'s step).
- Swords on the ground (`PickupContainer`) and swords falling (`DroppedWeapon`) are
  drawn; the game's draw events for them were missing, so they were invisible.
- The mines' pump-jack (`Pump`) rocks: its wheel, beam and beam end, drawn from the
  game's draw event.
- The game's function addresses (`tools/yyc/yyc.exs`) take only function starts, so no
  name points into the middle of another function's code.
- "Final Screen" shows in the castle's, the cemetery's and the wilds' last rooms before
  the end, made by those rooms' code as in the game.
- Objects the game's code makes take the depths the game makes them at
  (`Nidhox.ObjectDepths`, the game's `object_get_depth` table), and the animals and
  other things a room places draw in front of the grass, as in the game.
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
