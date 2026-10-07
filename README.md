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
macOS. `--area` is where the bout is fought: `Cemetery` (the default), `Castle`,
`Mines`, `Sky` or `Wilds`.

## Controls

Two players share the keyboard, or play with a controller each:

| action | side 1 | side 2 | controller |
| --- | --- | --- | --- |
| move | `A` `D` | `←` `→` | d-pad, left stick |
| up, down | `W` `S` | `↑` `↓` | d-pad, left stick |
| attack | `F` | `.` | `X` |
| jump | `G` | `,` | `A` |
| menu | `Esc` | | |

The first controller to send anything plays side 1, the second side 2.

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
  away. Stand over a sword on the ground to pick it up.
- **Right of way.** Killing your opponent lets you run on towards your goal; the
  camera follows you, and your opponent comes back ahead of you. Only you can leave the
  screen, into the next room. Falling into a pit hands the right of way to your
  opponent.
- **Winning.** Reach the goal at your end of the area. The next bout starts in the
  middle.

The rooms, their scenery and their ground come from your copy of the game. The fencers
and swords are NidhOX's own.
