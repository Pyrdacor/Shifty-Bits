# Shifty Bits

**[Play it in the browser](https://pyrdacor.github.io/Shifty-Bits/)**

A falling-block puzzle written in CShift. Rectangular blocks (1x2, 2x1, 3x1 ... up to 4x4) fall from the top, and
every tile holds a 0 or a 1. You can **roll** a block: A/D rolls all rows left or right, W/S rolls all columns up or
down. No bit ever leaves the block. When a block touches the floor or a resting tile, it becomes fixed.

4 or more equal bits in a row (horizontal or vertical) dissolve, and the tiles above fall down. If that forms new runs,
it is a chain reaction.

**Score** per clear: each run is worth `length × 10 + (length − 4) × 25`; the sum is multiplied by the number of runs,
the chain step and the level. A hard drop gives 2 points per row, a soft drop 1.

A block that locks (partly) above the red line ends the game. Every 30 cleared tiles the level goes up: blocks fall
faster and get bigger (at most 3 tiles at first, up to 4x4 from level 8).

## Game modes

The game starts with a menu: Up/Down selects the mode, Left/Right its option, Enter starts.

| Mode | Goal |
|---|---|
| Normal | Play until the well is full. |
| Countdown | 1, 3, 5 or 10 minutes: the most points before the time runs out. A chain reaction that is still running at 0:00 is finished and counts. |
| Score | Reach 1000, 10000, 50000 or 100000 points in the shortest time. The clock stops when the target is reached; a full well ends the game without a time. |
| Non-zero | The rules of the normal mode, but a run of four or more zeros ends the game: only 1s score. |

Every mode and option has its own best value (a score, or a time in the score mode), kept in `shiftybits-best.txt`
(one line per mode and option, then one line with the music and sound settings).

**Seed:** the blocks of a game come from its seed, a number of up to 9 digits: the same seed gives the same blocks
(a block depends on the seed, its position in the sequence and the level at which it appears). Normally the seed is
random and new for every game. In the menu, typing digits enters a seed (Backspace deletes, Del brings the random seed
back), Ctrl+V pastes one and Ctrl+C copies it. An entered seed stays for every following game. The seed is shown during
the game and on the final screen, where Ctrl+C copies it as well.

**Music and sound** come from a small synthesizer written in CShift ([src/music.csh](src/music.csh)): it plays the
chosen song in a loop (a little faster on higher levels), plus
sound effects for rolling, landing, clearing (higher with every chain step), level up and game over. Music and
sound effects are set separately in the menu (the line below the modes): Enter on MUSIC goes through the three
songs (NIGHT SKY in [song.txt](song.txt), DAYBREAK in [song2.txt](song2.txt), OVERCLOCK in [song3.txt](song3.txt))
and then to OFF, and the chosen song starts playing; Enter on SOUNDS switches the sound effects. **M** switches the
music off and on at any time. The settings are remembered.

After a game, **S** (or F12) saves a screenshot of the final screen, with the date instead of the prompts, as
`screenshots/shiftybits-YYYYMMDD-HHMMSS.png`.

## Music editor

`tools/musiceditor` is a small editor for the song files (`song.txt`, `song2.txt`, `song3.txt`). It uses the synthesizer and the sound output of the
game, so a song sounds in the editor as it does in the game.

```sh
cshiftc build tools/musiceditor            # -> tools/musiceditor/bin/MusicEditor.exe
tools/musiceditor/bin/MusicEditor.exe      # edits song.txt of the current folder (or of a folder above)
tools/musiceditor/bin/MusicEditor.exe song2.txt
```

A song has up to 12 tracks and up to 64 bars of 16 steps (16th notes). Every track has its own instrument (waveform,
volume, attack, decay, sustain, release, vibrato, pitch sweep, echo) and plays one note at a time; a track can also
*follow* another one, which plays that track's notes with a second instrument (the song uses it for a quiet sine an
octave above the lead).

| Where | What |
|---|---|
| Grid | Click sets a note, dragging to the right makes it longer, a right click deletes it. The wheel scrolls the notes, Shift+wheel the bars. The notes of the other tracks are shown faintly. |
| Piano keys | Click to hear a note with the instrument of the track |
| Track list | Select a track; **M** mutes it (saved with the song), **S** plays it alone (not saved). NEW, DUP, DEL and NAME below the list. |
| Instrument | `-` and `+` change a value (Shift: 10 steps), the wheel works too; the changed sound is played |
| Overview | One row per track, one cell per bar: click to go there |
| Space | Play from the selected bar / stop. LOOP switches between the whole song and the two bars shown. |
| ← → / ↑ ↓ | Select the bar / the track |
| Ctrl+C / Ctrl+V | Copy and paste the selected bar of the track (Ctrl+Shift+C: of all tracks) |
| Del | Clear the selected bar (Shift: of all tracks) |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+S | Save |

The game embeds the three song files when it is built. The desktop game also reads a song file of the same name from
the folder it is started in, so a saved song can be heard in the game at its next start without building; the browser
version needs a new build. The name of a song shown in the menu is its `name` line (up to 11 characters are shown);
the editor keeps it, to change it edit the line in the file. `MusicEditor.exe --selftest` checks the editing functions without a window.

## Controls

| Key | Action |
|---|---|
| ← / → | Move the block |
| A / D (Z / X) | Roll all rows left / right |
| W / S (↑) | Roll all columns up / down |
| ↓ | Soft drop |
| Space | Hard drop |
| P | Pause |
| R | New game (same mode) |
| H / F1 | Help |
| F11 / Alt+Enter | Fullscreen on / off (the image is scaled with its aspect ratio kept) |
| S / F12 | Save a screenshot (on the game over screen) |
| M | Music on / off |
| Ctrl+C | Copy the seed |
| Esc | Back to the menu (in the menu: quit) |

`ShiftyBits.exe --fullscreen` starts in fullscreen mode.

## Building

Requires `cshiftc` and `clang` (MSYS2 CLANG64). `libminifb.a`, `include/`, `font.txt` and `src/gfx.csh` come from
`../ShiftTower`.

```
src/               the game, shared by both versions (logic, drawing, music, input, PNG encoder)
song*.txt          the three songs, embedded by the game and edited with tools/musiceditor
platform/native/   desktop: MiniFB window, winmm sound (audio.csh), files; testing.csh writes test images and music
tools/musiceditor/ the music editor (shares gfx.csh, song.csh, music.csh and audio.csh with the game)
platform/web/      browser: imports from web/shiftybits.js
web/               index.html, shiftybits.js (host: canvas, keyboard, Web Audio), serve.mjs, cshift.json
```

**Desktop:**

```sh
cshiftc build .        # -> bin/ShiftyBits.exe
```

**Browser** (CShift's own wasm backend, no other tools needed):

```sh
cshiftc build web      # -> web/shiftybits.wasm
node web/serve.mjs     # -> http://localhost:8080/
```

Every push to `main` builds the browser version and publishes it on GitHub Pages
(<https://pyrdacor.github.io/Shifty-Bits/>): [.github/workflows/pages.yml](.github/workflows/pages.yml) downloads the
CShift release named there, builds `web` and uploads the page, its script and the wasm file.

The wasm backend only exports `_start`, the memory and the function table. The program registers its frame function
with `web_set_frame` and calls `web_run`, which throws back to JavaScript, so `Main` never returns and nothing is
released. JavaScript then calls the frame function through the function table on every animation frame. Music starts
with the first key press or click (browsers only allow sound after one). In the browser the best values are kept in
`localStorage` and a screenshot is downloaded.

`ShiftyBits.exe --shot image.png [play|over|help|menu|countdown|score|nonzero]` plays a few automatic moves and renders
one image;
`ShiftyBits.exe --shot music.wav music` renders 40 seconds of music, `music2` and `music3` the other songs, `sounds` only the
sound effects (all for testing).
