# NidhOX

Nidhogg Open-source eXperience: a two-player fencing game played in a terminal on
[Cauldron](../cauldron), from your own copy of the game's files.

No game files are included. NidhOX reads the data file of a copy you own — `data.win`
from the Windows build, or `game.ios` from inside the macOS build's `Nidhogg.app` — and
draws its rooms from it. With `data.win` it also reads the `Nidhogg.exe` installed
beside it, for the depths the game creates its objects at; a `data.win` without it does
not start.

```sh
mix deps.get
mix nidhox
mix nidhox --area Wilds
mix nidhox --data path/to/data.win
```

`--data` defaults to `NIDHOX_DATA`, then the first of the usual Steam installs under
your home directory: CrossOver's, macOS's and Linux's (set in `config/runtime.exs`). `--area` is the area the level select starts on: `Cemetery` (the default),
`Castle`, `Mines`, `Sky` or `Wilds`.

## Controls

Two players share the keyboard, or play with a controller each:

| action | side 1 | side 2 | controller |
| --- | --- | --- | --- |
| move | `A` `D` | `←` `→` | d-pad, left stick |
| up, down | `W` `S` | `↑` `↓` | d-pad, left stick |
| attack | `F` | `M` | `X` |
| jump | `G` | `N` | `A` |
| start, pause | `Enter` | `Enter` | Start |
| pause | `Esc` | | |

Either side's keys work the menus; jump or `Esc` goes back. `Ctrl+Q` quits at once.

Controllers take the free sides in the order they connect; **Options → Controls →
Controllers** lists the connected ones and moves each between player 1, player 2 and
none, and the choice is kept for that controller.

## Modes

NidhOX opens on the logos, then the title. Press `Enter` (or attack) to reach the
menu. The menus turn like a wheel under the logo, the selected line in the middle;
up and down turn them, `Enter` or attack chooses, and jump goes back (on the main menu,
to **Quit to desktop**). Left on the title for twenty seconds, the computer plays a
match against itself; any key brings back the menu.

- **Multiplayer**
  - **Offline versus**: two players at one keyboard, or a controller each. The level
    select pans across the map; up and down pick the area, `Enter` or attack starts the
    bout. Left alone for twelve seconds, it goes back to the main menu. After a bout
    the match statistics show; up or down switches their bottom line between going on
    and **watch replay**, which plays the bout again (`Enter` skips it).
  - **Online versus**: one machine hosts and another joins it; both play in the
    host's game.
    - **Host** shows this machine's address and a join code. Tell both to the player
      joining. Hosting stops when you go back (jump or `Esc`).
    - **Host over SSH** serves the game over ssh instead. It first asks for the port:
      leave it empty for any free one, or type one (`NIDHOX_SSH_PORT` or `mix nidhox
      --ssh-port` fills it in). It then shows the command to give the other player:
      `ssh -p <port> new@<address>`. They need only an ssh client — no copy of the game. The first
      time, any password opens a form where they pick a name and password, and they
      connect as that name from then on. They play orange in this machine's game, in
      their own terminal; sound reaches them only through an `ssh -R` tunnel to a player
      program on their machine. They have 10 minutes from connecting to log in. The
      game reaches them at 20 frames a second, fewer on a connection too slow for
      that. Going back, quitting to the title or quitting the game stops serving;
      they are disconnected with their terminal put back as it was and a line saying
      the host stopped.

      On a terminal that keeps images, how the picture is sent can be chosen when
      starting the game, for every player including those over ssh, with `mix nidhox
      --picture` (or `NIDHOX_PICTURE`) and any of, comma separated: `native` draws
      the room at its own size times the largest whole number that fits the window,
      or `native:2`, `native:3`, … at that many times; `size:WxH` sets the size
      itself; `png` sends each frame as a PNG, smaller; `swap` replaces each frame
      without the picture going blank in between. The default is `native:2,png,swap`;
      `--picture none` sends the picture at the window's cells as raw pixels instead.
    - **Join** lists the hosts on your local network; pick one and type its code.
    - **Set IP** types a host's address (it starts with your own network's part),
      then its code.

    Typing: type the address or code on the keyboard (letters come out in capitals);
    Backspace and Delete erase, the arrows move the caret, `Enter` finishes and `Esc`
    goes back. With a controller, up and down change the character before the caret.
    If the typing box closes, press start or attack to bring it back. The joining
    player plays orange.

    If the other player leaves, the bout under way is yours by forfeit and the hosting
    screen comes back saying "the other player left", still hosting on the same port
    (or address and code), so another player can connect straight away. When the other
    player chooses QUIT TO TITLE SCREEN from the pause, they leave: their ssh session
    or game ends and this machine goes back to the hosting screen the same way, saying
    "the other player quit". A second copy of the
    game on the same machine can join the first; it plays as your name with " (2)"
    after it.

    The code admits the joining machine fully to the host's Erlang VM, so give it only
    to the player you are playing with. On a local network this needs nothing more.
    Across the internet, the host starts with a fixed port (`mix nidhox --port 9200`)
    and opens it and port 4369 to the joining machine; the traffic is not encrypted.
  - **Variants**: the game's own. **Time limit** (none, or 3:00 to 9:30 in half
    minutes; when it runs out, the bout goes on in the area's sudden death room, where
    the first kill wins), then divekicks, throws, no swords, throws only, baby mode,
    low gravity, sudden death only, skippy mode, turbo, slow, spine swords, boomerang
    swords and trails, each on or off, as many at once as you like. Attack or start
    changes the one selected.
- **Tournament** — 3 to 8 players taking turns at the two sides, single elimination.
  Set **Players** and the **Map** with left and right, and the **Variants**, then
  **Start tournament**. The ladder shows the bracket, the next two players flashing;
  a player drawn against an empty place (X) goes through. `Enter` or attack leads to a
  nine-second warm-up in which the next two find their controllers and can already
  fence, then their match; the first of the two plays yellow. The last player left is
  the champion; their room ends the tournament after ten seconds or on `Enter`.
- **Options** — **Controls** to remap each player's keys, flashing and persistent
  blood on or off, and music and sound effect sliders (left and right; the effects
  level scales the music too, as in the game). They are kept in your settings,
  `~/.config/nidhox/<name>.settings`. They are on the pause menu as well.
- **Credits** — from your copy's `credits.txt`.
- **Quit to desktop**
- **How to play** — the game's own lessons, one at a time, with an orange dummy.
- **Single player** — sixteen bouts against the computer across the Mines, Sky, Wilds
  and Castle, each against a different opponent and harder as you go. The map shows
  your run and its time; press attack or start to fight the next bout. Lose and you
  fight that opponent again; win the last and the game is complete, with your time.
- **Challenge** — you against a computer opponent that gets harder each time you kill
  it. Every move that lands scores its worth: lunge, snap, kick, punch, sweep, guard,
  parry, throw and dodge. A move's worth halves each time you use it and climbs back
  while you use others, so vary them. Dying ends the run; your best score is shown
  along the bottom. `Enter` or `Esc` pauses.

`Enter` or `Esc` during a bout pauses it: unpause, change level (versus), quit to the
title, or options.
After a bout come its time, the winner, and each side's kills and suicides; any press
goes on to the level select. Every bout's result is kept, per player, in
`~/.local/share/nidhox/ledger.dets`.

## How it plays

Two fencers start in the middle of an area. Yellow wants to reach the far right end,
orange the far left.

- **Stance.** Up and down move your sword between high, middle and low. A thrust is
  parried by an opponent who faces you with the sword at the same height; it kills
  one holding it anywhere else.
- **Disarm.** Moving your sword into the height of a thrust just before it lands
  knocks the attacker's sword away.
- **Throw.** Hold up in high stance and attack to throw your sword. It kills whoever
  it reaches, unless they face it with their sword held high.
- **Unarmed.** Without a sword, attack is a punch that knocks the opponent's sword
  away. Duck over a sword on the ground to pick it up.
- **Right of way.** Killing your opponent lets you run on towards your goal; the
  camera follows you, and your opponent comes back ahead of you. Only you can leave the
  screen, into the next room. Falling into a pit hands the right of way to your
  opponent.
- **Winning.** Reach the goal at your end of the area. The next bout starts in the
  middle.

The rooms, their scenery and ground, the fencers, the menus and their lettering, the
sounds and the music all come from your copy of the game.
