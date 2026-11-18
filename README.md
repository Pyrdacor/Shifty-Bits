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
faster (up to level 20) and get bigger (at most 3 tiles at first, up to 4x4 from level 8), and the tiles change
their colors (8 pairs of colors that repeat).

## Intro

The game starts with a little intro in the style of the Amiga and Atari ST demo scene ([src/intro.csh](src/intro.csh)):
copper bars, a sunset over three layers of mountains and a checkerboard floor, chains of 0s and 1s winding through
the picture, the title flying in, zooming words and a sine scroller, to its own chip tune ([intro.txt](intro.txt)).
A click or any key skips it; it ends by itself after about 45 seconds. In the browser, which only plays sound after a
key or a click, the first key or click starts the intro again with its music (Esc skips at once). The INTRO button
of the menu (or **I**) shows it again.

## Game modes

The menu chooses the game mode with a selector (Left/Right or a click on its left or right half). The countdown and
score modes have an option below it (the minutes or the target score); for the other modes that row is hidden.
Below them are MUSIC and SOUNDS, the seed and the buttons START, NEW SEED, INTRO and HELP. Up/Down moves between the
rows, Left/Right changes the value or the button, Enter starts the game from the mode and option rows and presses the
selected button in the button row.

The menu also works with the mouse and, in the browser, with a finger: a click or tap on a half of the mode or the
option goes back or on, MUSIC and SOUNDS switch with a click, and the buttons do what they say. On a phone or tablet a
tap on the seed opens the on-screen keyboard to type one.

**Touch controls:** on a phone or tablet the browser version shows buttons that send the keys of the keyboard
controls: at the left moving (held buttons repeat), FASTER and DROP, at the right a cross that rolls the rows and
columns, at the top PAUSE and fullscreen. While the game is paused or over, buttons for RESUME, NEW GAME,
SCREENSHOT and MENU take their place. Held upright, the game is at the top and the buttons below it; lying, the buttons
are at the edges of the screen. `?touch=1` at the end of the address shows the buttons on any device, `?touch=0` hides
them.

| Mode | Goal |
|---|---|
| Normal | Play until the well is full. |
| Countdown | 1, 3, 5 or 10 minutes: the most points before the time runs out. A chain reaction that is still running at 0:00 is finished and counts. |
| Score | Reach 1000, 10000, 50000 or 100000 points in the shortest time. The clock stops when the target is reached; a full well ends the game without a time. |
| Non-zero | The rules of the normal mode, but a run of four or more zeros ends the game: only 1s score. |
| Alternate | The rules of the normal mode, but 1s and 0s must be cleared in turn; either may come first. Clearing 1s and 0s at the same time is always allowed and keeps the turn (after it, the same bit is due again). Clearing the bit that is not due ends the game; every step of a chain reaction counts. The left panel shows which bit is due next. |

Every mode and option has its own best value (a score, or a time in the score mode), kept in `shiftybits-best.txt`
(one line per mode and option of the first four modes, then one line with the music and sound settings, then the
line of the alternate mode).

**Seed:** the blocks of a game come from its seed, a number of up to 9 digits: the same seed gives the same blocks
(a block depends on the seed, its position in the sequence and the level at which it appears). Normally the seed is
random and new for every game. In the menu, typing digits enters a seed (Backspace deletes, Del brings the random seed
back), Ctrl+V pastes one and Ctrl+C copies it. An entered seed stays for every following game. The seed is shown during
the game and on the final screen, where Ctrl+C copies it as well.

**Music and sound** come from a small synthesizer written in CShift ([src/music.csh](src/music.csh)): it plays the
chosen song in a loop (a little faster on higher levels), plus
sound effects for rolling, landing, clearing (higher with every chain step), level up and game over. Music and
sound effects are set separately in the menu (the line below the modes): Enter on MUSIC goes through the five
songs (NIGHT SKY in [song.txt](song.txt), DAYBREAK in [song2.txt](song2.txt), OVERCLOCK in [song3.txt](song3.txt),
AFTERGLOW in [song4.txt](song4.txt), AURORA in [song5.txt](song5.txt)) and then to OFF, and the chosen song starts playing; Enter on SOUNDS switches the sound effects. **M** switches the
music off and on at any time. The settings are remembered.

AURORA is light and melancholic electronic pop: 64 bars (about 2:10) at 120 BPM in D minor, where the echo of the
synthesizer (375 ms) is a dotted 8th. A bouncing staccato synth bass in 16ths, warm offbeat electric piano chords, a
plucked lead that rings through the echo, four on the floor with claps and 16th hats, and quiet pads behind it.

After a game, **S** (or F12) saves a screenshot of the final screen, with the date instead of the prompts, as
`screenshots/shiftybits-YYYYMMDD-HHMMSS.png`.

## Music editor

`tools/musiceditor` is a small editor for the song files (`song.txt` to `song5.txt` and the intro's
`intro.txt`). It uses the synthesizer and the sound output of the
game, so a song sounds in the editor as it does in the game.

```sh
cshiftc build tools/musiceditor            # -> tools/musiceditor/bin/MusicEditor.exe
tools/musiceditor/bin/MusicEditor.exe      # edits song.txt of the current folder (or of a folder above)
tools/musiceditor/bin/MusicEditor.exe song2.txt
```

A song has up to 12 tracks and up to 64 bars of 16 steps (16th notes). Every track has its own instrument (waveform: sine, triangle, pulse, square, noise or sawtooth;
volume, attack, decay, sustain, release, vibrato, pitch sweep, detune, a low-pass filter that can open with every
note (cutoff and pluck), echo) and plays one note at a time; a track can also
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

The game embeds the five song files and `intro.txt` when it is built. The desktop game also reads a song file of the same name from
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
| I | Show the intro (in the menu) |
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
song*.txt          the five songs, embedded by the game and edited with tools/musiceditor
intro.txt          the song of the intro (the same format)
platform/native/   desktop (Windows and Linux): MiniFB window, files; testing.csh writes test images and music
platform/windows/  Windows: winmm sound (audio.csh), clipboard
platform/linux/    Linux: ALSA sound (audio.csh), clipboard (wl-copy, xclip or xsel), its project file cshift.json
tools/musiceditor/ the music editor for Windows (shares gfx.csh, song.csh, music.csh and audio.csh with the game)
platform/web/      browser: imports from web/shiftybits.js
web/               index.html, shiftybits.js (host: canvas, keyboard, Web Audio), serve.mjs, cshift.json
```

**Windows:**

```sh
cshiftc build .        # -> bin/ShiftyBits.exe
```

**Linux** (Debian/Ubuntu: `sudo apt install git cmake build-essential libx11-dev libxrandr-dev libxkbcommon-dev libgl-dev
libasound2-dev`, plus what [CShift needs on Linux](https://github.com/Robert-Schneckenhaus/CShift)):

```sh
tools/build-linux.sh   # -> bin/shiftybits; builds MiniFB into lib/linux/ the first time
```

The version is `GameVersion` in [src/version.csh](src/version.csh); it is shown in the title bar, in the menu and in
the intro.

**Releases:** the notes of a release take the section of the version from [CHANGELOG.md](CHANGELOG.md). Pushing a tag `v<version>` (matching `GameVersion`), or starting the workflow by hand with "publish"
checked (it then creates the tag), starts
[.github/workflows/release.yml](.github/workflows/release.yml): it builds and tests the Windows, Linux and browser
versions and publishes them as a GitHub release (`ShiftyBits-<version>-windows-x64.zip`, `-linux-x64.tar.gz`,
`-web.zip`). Started by hand without "publish", the workflow only builds and keeps the packages as artifacts of the run.

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

`ShiftyBits.exe --shot image.png [play|over|help|menu|pointer|countdown|score|nonzero|alternate|intro]` plays a few automatic moves and renders
one image;
`ShiftyBits.exe --shot music.wav music` renders the song once through (at least 40 seconds), `music2` to `music5` the other songs, `intromusic` the intro's song, `sounds` only the
sound effects (all for testing).
