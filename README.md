# NidhOX

Nidhogg Open-source eXperience: a two-player fencing game played in a terminal on
[Cauldron](../cauldron), from your own copy of the game's files.

No game files are included. NidhOX reads the data file of a copy you own — `data.win`
from the Windows build, or `game.ios` from inside the macOS build's `Nidhogg.app` — and
draws its rooms from it. It also reads the game's executable installed with it
(`Nidhogg.exe` beside `data.win`, or the app's `MacOS/Nidhogg`) for the depths the game
creates its objects at and its news; a data file without it does not start. The
languages come from the copy's `lang` folder, and the search screen's lines from its
`match.txt`.

Each NidhOX release plays one version of the game. Use the release that matches your
copy:

| Your copy of Nidhogg | NidhOX | Dependency |
| --- | --- | --- |
| Updated to the Online Update of October 2026 (online play, training mode) | 0.2 | `{:nidhox, "~> 0.2"}` |
| Still on the version before it (the Remix Level update of September 2021) | 0.1.4 | `{:nidhox, "0.1.4"}` |

Steam updates your copy unless you held it back, so most copies are on the Online Update.
NidhOX 0.2 was checked against that update's first build (Steam build 25889827, 13 October
2026); its patch of 16 October 2026 ("The Waiting Game", build 25998581) has not been
checked yet.

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

In the menus, either side's keys work: up and down move, jump or start chooses, and
`Esc` (a controller's B) goes back. The prompts in each box show the keys and buttons
of the player using it. `Ctrl+Q` quits at once.

Controllers take the free sides in the order they connect; **Options → Controls →
Controllers** lists the connected ones and moves each between player 1, player 2 and
none, and the choice is kept for that controller.

## Modes

NidhOX opens on the logos, then the main menu. Press start to open it. Left alone for
twenty seconds, the computer plays a match against itself on one of the five areas;
any key brings back the menu. A white dot marks what is new, and **News** while an
article is unread.

- **Multiplayer**
  - **Local**: two players at one keyboard, or a controller each. The level select
    pans across the map; up and down pick the area, jump or start starts the bout, and
    `Esc` asks whether to go back to the main menu. After a bout the match statistics
    show; up or down switches their bottom line between going on and **watch replay**,
    which plays the bout again (`Enter` skips it).
  - **Online**: see [Playing online](#playing-online).
  - **Tournament**: 3 to 8 players taking turns at the two sides, single
    elimination. Its window shows the bracket as it will start. Set **Players** and the
    **Map** with left and right, the **Variants**, then **Start tournament**. The ladder
    shows the bracket, the next two players flashing; a player drawn against an empty
    place (X) goes through. Start or jump leads to a nine-second warm-up in which the
    next two find their controllers and can already fence, then their match; the first
    of the two plays yellow. The last player left is the champion.
- **Options**: the language, **Controls** to remap each player's keys, flashing and
  persistent blood on or off, and music and sound effect sliders (left and right; the
  effects level scales the music too). They are kept in your settings,
  `~/.config/nidhox/<name>.settings`. They are on the pause menu as well.
- **Extras**
  - **How to play**: the game's lessons, one at a time, with an orange dummy. Each
    instruction shows your own keys.
  - **CPU battle**: the computer against itself. Set **Hype** (how well both play),
    the **Time limit** and **Sudden death only**, then **Begin**. The level select
    picks an area at random and starts by itself after 45 seconds; the results go on by
    themselves after 15, round and round until you leave from the pause or the level
    select.
  - **Credits**: from your copy's `credits.txt`.
  - **Challenge**: you against a computer opponent that gets harder each time you kill
    it. Every move that lands scores its worth: lunge, snap, kick, punch, sweep, guard,
    parry, throw and dodge. A move's worth halves each time you use it and climbs back
    while you use others, so vary them. Dying ends the run; your best score is shown
    along the bottom.
- **Quit to desktop**: asks first.
- **News**: the game's articles. Choose one to read it; up and down scroll it. An
  article's video is named where the game plays it; select on its link puts the link
  on your clipboard.
- **Single player**
  - **Arcade**: sixteen bouts against the computer across the Mines, Sky, Wilds and
    Castle, each against a different opponent and harder as you go. Lose and you fight
    that opponent again; win the last and the game is complete, with your time.
  - **Training**: you against the computer on side 2. Pick its personality, then its
    difficulty (left and right), then the area on the level select.

`Enter` or `Esc` during a bout pauses it: unpause, change level, variants (changing the
time limit or sudden death asks to restart the match), change color (each side's colour
from eight), options, and exit, which asks first. After a bout come its time, the
winner, and each side's kills and suicides; any press goes on to the level select.
Every bout's result is kept, per player, in `~/.local/share/nidhox/ledger.dets`.

## Playing online

**Multiplayer → Online** opens the online menu. While it shows, this machine keeps a
lobby open on the local network that friends can join.

- **Find a match** searches the local network. It joins the open lobby with the
  lowest ping, or opens one and waits. When two players meet, both see **MATCH
  FOUND!** with the other's name and ping: both press select within ten seconds to
  play. Back denies; the denier stops searching and the other goes on searching,
  passing over the denier for 30 seconds.
- **Invite friend** lists the players heard on the local network and your recent
  opponents. Choose one in the game to join them, or any other to invite them: they
  see **INVITE!** for 30 seconds on their menus.
- **Host over SSH** serves the game over ssh. It first asks for the port: leave it
  empty for any free one, or type one (`NIDHOX_SSH_PORT` or `mix nidhox --ssh-port`
  fills it in). It then shows the command to give the other player: `ssh -p <port>
  new@<address>`. They need only an ssh client, no copy of the game. The first time,
  any password opens a form where they pick a name and password, and they connect as
  that name from then on. They play orange in this machine's game, in their own
  terminal; sound reaches them only through an `ssh -R` tunnel to a player program on
  their machine. The game reaches them at 20 frames a second, fewer on a connection too
  slow for that. Going back stops serving; they are disconnected with their terminal
  put back as it was and a line saying the host stopped.
- **Join by address** types the address and port a lobby shows under the online menu,
  `address:port`, to join a machine the local network cannot hear, such as one across
  the internet. That machine starts with a fixed port (`mix nidhox --port 9200`) and
  opens that TCP port.

Two players who meet play in the lobby: each stands in their own half and readies up
by standing on their ready zone. Once both have stood there for a second, the loser of
the last match picks the area, and the match is played. Its results wait for both
players, and the lobby comes back, with each player's wins tallied. In the lobby,
start opens the pause: **Input delay** sets how many frames ahead your input is sent,
green when it covers the ping. Leaving the lobby or the level select ends the session
for both; in a match, the pause's **Forfeit** gives it to the other player.

Each machine runs and draws the game itself, playing with rollback. The two exchange
only the players' joins, leaves and input over one TCP connection, and nothing the
other machine sends can run code on yours.

On a terminal that keeps images, how the picture is sent can be chosen when starting
the game, for every player including those over ssh, with `mix nidhox --picture` (or
`NIDHOX_PICTURE`) and any of, comma separated: `native` draws the room at its own size
times the largest whole number that fits the window, or `native:2`, `native:3`, … at
that many times; `size:WxH` sets the size itself; `png` sends each frame as a PNG,
smaller; `swap` replaces each frame without the picture going blank in between. The
default is `native:2,png,swap`; `--picture none` sends the picture at the window's cells
as raw pixels instead.

Where the machine has a graphics card, it draws the picture: the same picture, pixel for
pixel at the whole-number sizes `native` picks, in about a sixth of the time at large
sizes. Without one the game draws it in software. The picture options choose otherwise:
`software` draws in software, `gpu` asks for the card in the terminal, and `window` opens
a window of its own whose keys play the game, as in `--picture native:2,png,window`.

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
