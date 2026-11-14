//! The main menu: choosing the game mode with its option, the song and the sounds, and entering, copying or pasting
//! the seed.

namespace ShiftyBits;

using System;

// the row of the menu that chooses the song or switches the music off; the rows before it are the modes
const int _RowMusic = ModeCount;
// the row for the sound effects, drawn beside the music row
const int _RowSounds = ModeCount + 1;

// the row under the cursor: the number of a `Mode`, `_RowMusic` or `_RowSounds`
int _menuRow;
bool _settingsLoaded;
// the best value of every mode and option, read when the menu opens
int[] _menuBest = [];

/// The main menu.
struct Menu
{
    /// Shows the menu (also ends a running game).
    static void Open()
    {
        if (!_settingsLoaded)
        {
            int settings = Platform.LoadBest(SettingsSlot);
            Music.SetOn((settings & 1) == 0);
            Music.SetSoundsOn((settings & 2) == 0);
            _SelectSong((settings >> 2) & 3);
            _settingsLoaded = true;
        }
        _state = State.Menu;
        _paused = false;
        if (_menuRow < ModeCount)
            _menuRow = (int)_mode;
        Music.Stop();
        if (!_seedFixed)
            _seed = Game.RandomSeed();
        _menuBest = new int[BestSlots];
        for (var i = 0; i < BestSlots; i += 1)
        {
            _menuBest[i] = Platform.LoadBest(i);
        }
    }

    /// Keeps the music and sound settings for the next start.
    static void SaveSettings()
    {
        Platform.SaveBest(SettingsSlot, (Music.IsOn() ? 0 : 1) | (Music.SoundsOn() ? 0 : 2) | (Music.SongIndex() << 2));
    }

    static void _SelectSong(int index)
    {
        Music.SelectSong(Math.Min(index, SongCount - 1));
        // the desktop game prefers a song file in its folder
        Platform.LoadSongFile(Music.SongIndex());
    }

    // the music switch: the songs one after the other, then off
    static void _NextSong()
    {
        if (!Music.IsOn())
        {
            Music.SetOn(true);
            _SelectSong(0);
        }
        else if (Music.SongIndex() + 1 < SongCount)
            _SelectSong(Music.SongIndex() + 1);
        else
            Music.SetOn(false);
        SaveSettings();
        // the chosen song plays in the menu, to hear what was chosen
        if (Music.IsOn())
            Music.Start();
        else
            Music.Stop();
    }

    /// Handles one key press while the menu is shown.
    static void Key(int k, int mods)
    {
        if ((mods & ModCtrl) != 0)
        {
            if (k == 'V')
                _Paste(Platform.PasteText());
            return;
        }
        if (k == KeyEscape)
            Platform.Quit();
        else if (k == KeyUp || k == 'W')
        {
            // music and sounds share one line below the modes
            if (_menuRow == 0)
                _menuRow = _RowMusic;
            else
                _menuRow = Math.Min(_menuRow, ModeCount) - 1;
        }
        else if (k == KeyDown || k == 'S')
            _menuRow = _menuRow >= ModeCount ? 0 : _menuRow + 1;
        else if (k == KeyLeft || k == 'A')
            _ChangeOption(-1);
        else if (k == KeyRight || k == 'D')
            _ChangeOption(1);
        else if (k == KeyEnter || k == KeyPadEnter || k == ' ')
        {
            if (_menuRow == _RowMusic)
                _NextSong();
            else if (_menuRow == _RowSounds)
            {
                Music.SetSoundsOn(!Music.SoundsOn());
                SaveSettings();
                // lets the player hear that the sounds are back
                Music.Play(Sfx.Roll, 0);
            }
            else
            {
                _mode = (Mode)_menuRow;
                Game.NewGame();
            }
        }
        else if (k == 'H' || k == KeyF1)
            _showHelp = true;
        else if (k >= '0' && k <= '9')
            _Digit(k - '0');
        else if (k >= KeyPad0 && k <= KeyPad0 + 9)
            _Digit(k - KeyPad0);
        else if (k == KeyBackspace)
        {
            // deleting the last digit brings the random seed back
            if (_seedFixed && _seed >= 10)
                _seed /= 10;
            else
                _RandomSeed();
        }
        else if (k == KeyDelete)
            _RandomSeed();
    }

    static void _ChangeOption(int step)
    {
        if (_menuRow == _RowMusic)
            _menuRow = _RowSounds;
        else if (_menuRow == _RowSounds)
            _menuRow = _RowMusic;
        else if (_menuRow == (int)Mode.Countdown)
            _countdownChoice = (_countdownChoice + CountdownMinutes.Length + step) % CountdownMinutes.Length;
        else if (_menuRow == (int)Mode.Score)
            _scoreChoice = (_scoreChoice + ScoreTargets.Length + step) % ScoreTargets.Length;
    }

    static void _RandomSeed()
    {
        _seedFixed = false;
        _seed = Game.RandomSeed();
    }

    // the first digit typed replaces a random seed
    static void _Digit(int d)
    {
        if (!_seedFixed)
        {
            _seedFixed = true;
            _seed = 0;
        }
        if (_seed <= MaxSeed / 10)
            _seed = _seed * 10 + d;
    }

    // takes the digits of a pasted text as the seed
    static void _Paste(string text)
    {
        int value = 0;
        int digits = 0;
        for (var i = 0; i < text.Length && digits < 9; i += 1)
        {
            int c = (int)(uint8)text[i];
            if (c >= '0' && c <= '9')
            {
                value = value * 10 + (c - '0');
                digits += 1;
            }
        }
        if (digits == 0)
        {
            Render.Toast("NO SEED IN THE CLIPBOARD");
            return;
        }
        _seed = value;
        _seedFixed = true;
        Render.Toast("SEED PASTED");
    }
}
