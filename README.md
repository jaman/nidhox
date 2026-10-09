# NidhOX

Nidhogg Open-source eXperience: a two-player fencing game played in a terminal on
[Cauldron](../cauldron), from your own copy of the game's files.

No game files are included. NidhOX reads the data file of a copy you own — `data.win`
from the Windows build, or `game.ios` from inside the macOS build's `Nidhogg.app` — and
draws its rooms from it.

```sh
mix deps.get
mix nidhox
mix nidhox --area Wilds
mix nidhox --data path/to/data.win
```

`--data` defaults to `NIDHOX_DATA`, then the usual Steam installs under CrossOver and
macOS. `--area` is the area the level select starts on: `Cemetery` (the default),
`Castle`, `Mines`, `Sky` or `Wilds`.

## Controls

Two players share the keyboard, or play with a controller each:

| action | side 1 | side 2 | controller |
| --- | --- | --- | --- |
| move | `A` `D` | `←` `→` | d-pad, left stick |
| up, down | `W` `S` | `↑` `↓` | d-pad, left stick |
| attack | `F` | `.` | `X` |
| jump | `G` | `,` | `A` |
| start, pause | `Enter` | | Start |
| options | `Esc` | | |

The first controller to send anything plays side 1, the second side 2.

## Modes

NidhOX opens on the logos, then the title. Press `Enter` (or attack) to reach the
menu:

- **Single player** — you against the computer through every area in turn: Cemetery,
  Castle, Mines, Sky, Wilds. A loss ends the run.
- **Multiplayer**
  - **Offline versus**: two players at one keyboard, or a controller each, in the area
    chosen on the level select (left and right pick it). Under the area: **Variants**
    (no swords, divekick only, throws only, sudden death only, low gravity, turbo,
    slow, boomerang swords), **Time limit** (none, 1, 2, 3 or 5 minutes; when it runs
    out, the bout goes on in the area's sudden death room, where the first kill wins)
    and **Begin**.
  - **Tournament**: 3 to 8 players taking turns at the two sides, double elimination.
    Set **Players**, the area, variants and time limit, then **Start tournament**.
    Between matches the ladder shows every match so far and who fights next (yellow
    against orange); the last player standing is the champion.
  - **Online versus**: one machine hosts and another joins it; both play in the
    host's game.
    - **Host** shows this machine's address and a join code. Tell both to the player
      joining. Hosting stops when you go back from the level select or to the menus
      before it.
    - **Join** lists the hosts on your local network; pick one and type its code.
    - **Set IP** types a host's address (it starts with your own network's part),
      then its code.

    Typing: up and down change the character under the cursor, left and right move
    the cursor (right past the end adds a character), `Enter` or attack finishes,
    jump goes back. The joining player plays orange.

    The code admits the joining machine fully to the host's Erlang VM, so give it only
    to the player you are playing with. On a local network this needs nothing more.
    Across the internet, the host starts with a fixed port (`mix nidhox --port 9200`)
    and opens it and port 4369 to the joining machine; the traffic is not encrypted.
- **How to play** — the game's own lessons, one at a time, with an orange dummy.
- **Options** — sound effects and music on or off, and **Controls** to remap
  each player's keys; kept in your settings. `Esc` opens them during play as well.
- **Credits** — from your copy's `credits.txt`.
- **Quit to desktop**

On the menus, up and down move, `Enter` or attack chooses, and jump goes back. `Enter`
during a bout pauses it: unpause, change level (versus), or quit to the title. After
a bout, the match's statistics (its time, and each side's kills and suicides), then
**Continue**, **Watch replay** (the bout again; `Enter` skips it) or **Back to main
menu**. Every
bout's result is kept, per player, in `~/.local/share/nidhox/ledger.dets`.

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
