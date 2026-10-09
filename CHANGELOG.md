# Changelog

## Unreleased

### Added

- Sound from the player's copy: each event of a bout plays the copy's own effect —
  screams, stabs, clashes, disarms, thrusts, throws, jumps, landings, footsteps by
  stride, pickups, swords landing, room changes, the start and the cheer
  (`Nidhox.Sounds`, `Nidhox.Noises`), placed and panned from the camera's centre.
- Music from the player's copy: each area's title track on the title, menus and
  results, and all its layers together during the bout (`Nidhox.Music`).
- The bout's camera eases towards where it should be and snaps when a bout starts or
  enters a room; parallax dressing follows it by its depth (`Nidhox.Parallax`).
- The game's own screens and menus, in its own rooms, sprites and fonts
  (`Nidhox.Flow`, `Nidhox.Screen.*`): the Messhof and Daedelus logos; the `nidhogg`
  title with "press start"; the main menu — SINGLE PLAYER, MULTIPLAYER, OPTIONS,
  CREDITS, QUIT TO DESKTOP; MULTIPLAYER's OFFLINE VERSUS, ONLINE DISABLED and BACK; the
  level select panning across the copy's map of the areas; the pause — UNPAUSE GAME, CHANGE LEVEL,
  QUIT TO TITLE SCREEN; the match's statistics; the credits from the copy's own
  `credits.txt`.
- SINGLE PLAYER through every area against the computer; OFFLINE VERSUS in the area
  chosen. `:start` on `Enter` and the controller's Start, and it pauses a bout.
- OPTIONS (`Nidhox.Options`): SFX and MUSIC on and off, and CONTROLS to remap each
  action's key, kept in the player's own settings. QUIT TO DESKTOP ends the client of
  the player who chose it.
- The rooms' standing sounds from the copy: wind, fire, the mines' drone, the waterfall
  and its edges, and the chandeliers' creak and chain (`Nidhox.Objects.Ambience`);
  every sound decoded ahead of play.
- Squirrels and birds: they sit and perch, wander and peck, and run or fly off from a
  fencer that comes close (`Nidhox.Objects.Animals`).
- The GO arrow and the winner banner from the copy's `sGO` and `sWinner`.
- Fencers drawn in the copy's own poses (`Nidhox.Pose`): guard stances at each height,
  walking on guard forwards and backwards, lunges at each height, running, rising,
  falling, throws, the punch, and unarmed stances, each sword drawn with its body or
  held from the hand.
- Doors that stay shut and swing open as a fencer runs through (`Nidhox.Objects.Doors`).
- The castle's chandelier swinging on its chain with its candles' glow, the castle's
  stone backdrop, torches burning with rising flames and embers, the cemetery's clouds
  drifting across the moon, the sky's cloud banks and cloud puffs.
- OPTIONS → CONTROLS remaps PLAYER 1 or PLAYER 2; player 2's keys are kept in the
  player's settings. `Esc` opens OPTIONS during play.
- `PARITY.md`, the list of what still differs from Nidhogg.
- More moves: sliding (down while running), rolling (landing with down held), the second
  punch and the uppercut, being disarmed, catching a falling sword, hanging from ledges
  and climbing onto them, running up walls (`Nidhox.Climb`).
- Blood in the victim's colour; rain, swaying leaves, grass that flattens underfoot,
  cats; the castle's fire clouds.
- Ducking and crawling, sweeping the leg, the divekick, being knocked down and getting
  up, tearing out a knocked-down opponent's heart, disarming by moving your blade into
  the opponent's, and picking a sword up by ducking over it, each in the copy's
  sprites and with its sounds.
- The Nidhogg comes for the winner at the end of an area, eats them and flies off
  (`Nidhox.Ending`).
- The wilds' waterfall spray; the mines' conveyors, which carry fencers, screws, pump,
  smashers, smoke and worms.
- HOW TO PLAY (`Nidhox.Tutorial`): the copy's own lessons, one at a time in
  `rTutorial`, each passed by doing what it says, with an orange dummy that throws its
  sword in the blocking lesson.
- The results menu — CONTINUE, WATCH REPLAY, BACK TO MAIN MENU; WATCH REPLAY plays the
  bout again from its recorded inputs, with SKIP THIS.
- The level select's VARIANTS (NO SWORDS, DIVEKICK ONLY, THROWS ONLY, SUDDEN DEATH
  ONLY, LOW GRAVITY, TURBO MODE, SLOW MODE, BOOMERANG SWORDS) and TIME LIMIT (none, 1,
  2, 3 or 5 minutes) (`Nidhox.Rules`). When time runs out the bout goes on in the
  area's sudden death room, where the first kill wins.
- TOURNAMENT on MULTIPLAYER (`Nidhox.Tournament`, `Nidhox.Screen.Ladder`): 3 to 8
  players at one machine, double elimination, set up on the level select (PLAYERS,
  VARIANTS, TIME LIMIT, START TOURNAMENT); the players' icons over
  `rTournamentIntro`, the ladder and the next match over `rShowLadder` ("final
  showdown!" before the final), and the champion over the pyre of `rShowChampion`.
- ONLINE VERSUS (`Nidhox.Online`): HOST shows this machine's address and a join code;
  JOIN lists the hosts on the local network; SET IP types an address. Typing the
  host's code joins its game as orange, taking the side from the host's second
  keyboard seat until the joining player leaves. `mix nidhox --port` fixes the port a
  host listens on.
- `mix nidhox --name` defaults to `fencer@<host name>`, so players on different
  machines have different names.
- Blood stays where it lands on the ground (`Nidhox.Objects.Stains`), in the victim's
  colour; blood drops are the victim's colour rather than the copy's red `sDrop`.
- The castle's pebbles drop away from under its bridges (`Nidhox.Objects.Rocks`); the
  moon stays in the sky as a far layer while the view moves; the menus' and sky's
  background colour pulses.
- `mix run tools/gaps.exs`: the full gap analysis from the player's own copy — every room, object and event, which NidhOX handles, and each event's compiled code traced from `Nidhogg.exe` (`tools/yyc`); `mix run tools/render_rooms.exs` draws every room as NidhOX draws it.
- From the game's own compiled code (`tools/yyc/decompile.exs`): the moving paper-like
  backdrop of every screen (`Nidhox.Objects.Background`); parallax by depth / 400 × 0.7;
  the moon's follow; the title's colour, camera sway, grass and "press start"; the
  castle's black backdrop and its chandelier's swing, squeak and glow; grass laid,
  swaying and tinted, dark grass breathing deeper, trodden flat by fencers, shaken by
  passing fencers, flying swords and cats, and rising again (`Nidhox.Objects.Grass`).
- The wind surface as the game churns it — random patches nudged across a tiled
  `bWindSurface` canvas — in the cemetery's sky and, faintly, across the title; the
  castle centre's edge sounds (`sfxEdgeOfCenter`), and the wind sound only there.
- Each bout's result kept in NidhOX's ledger through `Cauldron2D.Worlds` and
  `Cauldron2D.Ledger.Recorder`.
- Fencing: stances, thrusts, parries, disarms, thrown swords, punches and picking a
  sword up (`Nidhox.Fencer`, `Nidhox.Duel`), on the room's ground (`Nidhox.Terrain`).
- Bouts across an area's rooms: the right of way, respawning ahead of the runner, the
  camera following it, room changes and winning at the goal (`Nidhox.Match`); `--area`.
- `mix nidhox`: the game in the terminal from the player's own data file
  (`Nidhox.Assets`), its rooms running on `Cauldron2D.GameMaker` (`Nidhox.Game`) and
  drawn at the pane's size (`Nidhox.Client`).
- Two sides at one keyboard, or a controller each, and watchers; `Nidhox.Controls` for
  each side's keys and the controllers.
- `Nidhox.Code`, the table of the game's code, built from object modules.

### Fixed

- Blocks are no longer drawn as white rectangles; the castle's walls no longer show
  a stone fill the original does not have; the sky no longer shows cloud banks the
  original keeps hidden.

- A fallen fencer no longer blanks the screen, and lies on the ground where it fell,
  its fall played once.
- A fencer near its opponent walks on guard only within 64 pixels, not a third of the
  screen.
- The bout's camera follows the fencers up and down, keeping them the room view's
  border inside the screen, so tall rooms like the mines' centre show the fight.
- A bout no longer draws a made-up moon, clouds and grass over every room; each room
  shows only its own scenery.
- The bout's music no longer clips: its stems join one by one as the bout moves from
  the centre towards an end room, each at an equal share of the level.
- The level select pans across the copy's painted map to the selected area under its
  name plate.
- Side 2 plays from the right of the keyboard again.
- Thrusts land: blades are what the poses draw (`Nidhox.Blade`), reaching as far as the
  copy's lunge and sword; blades at the same height stop each other, and a held blade
  stops a thrown sword at any height.
- A bout carries on into the next room at an area's edge: the camera now arrives at the
  room's edge instead of stopping just short of it.
- Fencers stand on the ground in every pose: each is placed by its own sprite's origin.
- The moon is its plain disc, with the wind surface's clouds streaking across it and the
  sky, added to what is beneath them as the original adds them.
