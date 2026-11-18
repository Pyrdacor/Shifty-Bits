//! The main menu: choosing the game mode and its option, the song and the sounds, entering, copying or pasting the
//! seed, and the buttons to start, to show the intro and the help, with the keyboard or with the mouse or a finger.
//! The places of its parts are constants here, so that the drawing (render.csh) and the pointer agree.

namespace ShiftyBits;

using System;

// the rows of the menu, chosen with the up and down keys: the game mode, its option (only for the modes that have
// one), music and sounds side by side, and the buttons
const int _RowMode = 0;
const int _RowOption = 1;
const int _RowMusic = 2;
const int _RowSounds = 3;
const int _RowButtons = 4;

// what the pointer can hit: the rows above, the seed and the buttons
const int _ElSeed = 5;
const int _ElStart = 6;
const int _ElNewSeed = 7;
const int _ElIntro = 8;
const int _ElHelp = 9;
const int _ButtonCount = 4;
const ReadOnlySlice<string> _ButtonLabels = ["START", "NEW SEED", "INTRO", "HELP"];
const ReadOnlySlice<int> _ButtonOffsets = [24, 264, 464, 624];
const ReadOnlySlice<int> _ButtonWidths = [230, 190, 150, 130];

const int MenuW = 780;
// the height with the option row; without it, the rows below move up and the menu gets shorter (its top stays, so
// that the arrows of the mode do not move)
const int _MenuFullH = 480;
const int MenuX = (ScreenW - MenuW) / 2;
const int MenuY = (ScreenH - _MenuFullH) / 2;
const int MenuRowX = MenuX + 24;
const int MenuRowW = MenuW - 48;
// the game mode: a selector with arrows at both ends; the left half of it goes back, the right half on
const int MenuModeY = MenuY + 100;
const int MenuModeH = 76;
// the option of the mode (minutes or points), shown only for the modes that have one
const int MenuOptionY = MenuY + 186;
const int MenuOptionH = 44;
// the part at the right of the option row that changes it: its left half goes back, its right half on
const int MenuOptionW = 292;
// music and sounds beside each other (the rows from here on move up when the option row is hidden)
const int _MenuSwitchTop = MenuY + 240;
const int MenuSwitchH = 40;
const int MenuSwitchW = (MenuRowW - 12) / 2;
// the seed with its label
const int MenuSeedX = MenuX + 36;
const int _MenuSeedTop = MenuY + 292;
const int MenuSeedW = 308;
const int MenuSeedH = 40;
// the buttons
const int _MenuButtonTop = MenuY + 380;
const int MenuButtonH = 48;

// true while the menu is used with the mouse or a finger: the keyboard selection is not shown then
bool _pointerMode;
// what the mouse is over (a row or one of the `_El` constants), -1 for nothing
int _menuHover = -1;

// the row of the keyboard selection (`_RowMode` ... `_RowButtons`) and the button selected in the button row
int _menuRow;
int _menuButton;
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
            _SelectSong((settings >> 2) & 7);
            _settingsLoaded = true;
            // a phone or tablet starts with the buttons
            _pointerMode = Platform.IsTouch();
        }
        _state = State.Menu;
        _paused = false;
        _menuRow = _RowMode;
        Music.Stop();
        if (!_seedFixed)
            _seed = Game.RandomSeed();
        _menuBest = new int[StoredSlots];
        for (var i = 0; i < StoredSlots; i += 1)
        {
            _menuBest[i] = Platform.LoadBest(i);
        }
    }

    /// Keeps the music and sound settings for the next start.
    static void SaveSettings()
    {
        Platform.SaveBest(SettingsSlot, (Music.IsOn() ? 0 : 1) | (Music.SoundsOn() ? 0 : 2) | (Music.SongIndex() << 2));
    }

    /// Loads the song chosen in the menu again (after the intro played its own).
    static void RestoreSong()
    {
        _SelectSong(Music.SongIndex());
    }

    /// How far the rows below the option row move up: by the option row and its gap when it is hidden.
    static int _Shift()
    {
        return HasOption(_mode) ? 0 : -(MenuOptionH + 10);
    }

    /// The height of the menu; a phone or tablet has no line with the keys at the bottom.
    static int Height()
    {
        return _MenuFullH + _Shift() - (Platform.IsTouch() ? 30 : 0);
    }

    /// The top of the music and sound row.
    static int SwitchY()
    {
        return _MenuSwitchTop + _Shift();
    }

    /// The top of the seed.
    static int SeedY()
    {
        return _MenuSeedTop + _Shift();
    }

    /// The top of the buttons.
    static int ButtonY()
    {
        return _MenuButtonTop + _Shift();
    }

    /// Whether `mode` has an option to choose (minutes or points).
    static bool HasOption(Mode mode)
    {
        return mode == Mode.Countdown || mode == Mode.Score;
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
        int before = _seed;
        _Key(k, mods);
        // the easter egg tells that it was found
        if (_seed != before && Game.SwordAndShield())
            Render.Toast("TO ARMS! THE BITS TAKE UP SWORDS AND SHIELDS");
    }

    static void _Key(int k, int mods)
    {
        if (k == KeySeedInput)
        {
            // every change of the on-screen keyboard's text arrives as the whole text
            int typed = _ParseSeed(Platform.PasteText());
            if (typed < 0)
                _RandomSeed();
            else
            {
                _seed = typed;
                _seedFixed = true;
            }
            return;
        }
        _pointerMode = false;
        if ((mods & ModCtrl) != 0)
        {
            if (k == 'V')
                _Paste(Platform.PasteText());
            return;
        }
        if (k == KeyEscape)
            Platform.Quit();
        else if (k == KeyUp || k == 'W')
            _MoveRow(-1);
        else if (k == KeyDown || k == 'S')
            _MoveRow(1);
        else if (k == KeyLeft || k == 'A')
            _ChangeOption(-1);
        else if (k == KeyRight || k == 'D')
            _ChangeOption(1);
        else if (k == KeyEnter || k == KeyPadEnter || k == ' ')
        {
            if (_menuRow == _RowMusic)
                _NextSong();
            else if (_menuRow == _RowSounds)
                _ToggleSounds();
            else if (_menuRow == _RowButtons)
                _Press(_ElStart + _menuButton);
            else
                _Start();
        }
        else if (k == 'I')
            Intro.Start();
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

    /// What is at a pixel of the screen: a row of the menu, one of the `_El` constants, or -1.
    static int ElementAt(int x, int y)
    {
        if (x >= MenuRowX && x < MenuRowX + MenuRowW)
        {
            if (y >= MenuModeY && y < MenuModeY + MenuModeH)
                return _RowMode;
            if (HasOption(_mode) && y >= MenuOptionY && y < MenuOptionY + MenuOptionH)
                return _RowOption;
            if (y >= SwitchY() && y < SwitchY() + MenuSwitchH)
            {
                if (x < MenuRowX + MenuSwitchW)
                    return _RowMusic;
                if (x >= MenuRowX + MenuRowW - MenuSwitchW)
                    return _RowSounds;
            }
        }
        if (x >= MenuSeedX && x < MenuSeedX + MenuSeedW && y >= SeedY() && y < SeedY() + MenuSeedH)
            return _ElSeed;
        if (y >= ButtonY() && y < ButtonY() + MenuButtonH)
        {
            for (var b = 0; b < _ButtonCount; b += 1)
            {
                int bx = MenuX + _ButtonOffsets[b];
                if (x >= bx && x < bx + _ButtonWidths[b])
                    return _ElStart + b;
            }
        }
        return -1;
    }

    /// Handles the mouse moving over the menu.
    static void Hover(int x, int y)
    {
        _menuHover = ElementAt(x, y);
    }

    /// Handles a click or tap in the menu.
    static void Pointer(int x, int y)
    {
        _pointerMode = true;
        int element = ElementAt(x, y);
        _menuHover = element;
        if (element < 0)
            return;
        if (element == _RowMode)
        {
            _menuRow = element;
            _ChangeOption(x < MenuRowX + MenuRowW / 2 ? -1 : 1);
        }
        else if (element == _RowOption)
        {
            _menuRow = element;
            int optionX = MenuRowX + MenuRowW - MenuOptionW;
            if (x >= optionX)
                _ChangeOption(x < optionX + MenuOptionW / 2 ? -1 : 1);
        }
        else if (element == _RowMusic || element == _RowSounds)
        {
            _menuRow = element;
            _Press(element);
        }
        else if (element >= _ElStart)
        {
            _menuRow = _RowButtons;
            _menuButton = element - _ElStart;
            _Press(element);
        }
        // a tap on the seed opens the on-screen keyboard: the browser does that itself (web/shiftybits.js)
    }

    // what a button or a switch does
    static void _Press(int element)
    {
        if (element == _RowMusic)
            _NextSong();
        else if (element == _RowSounds)
            _ToggleSounds();
        else if (element == _ElStart)
            _Start();
        else if (element == _ElNewSeed)
            _RandomSeed();
        else if (element == _ElIntro)
            Intro.Start();
        else if (element == _ElHelp)
            _showHelp = true;
    }

    // starts the chosen mode
    static void _Start()
    {
        Game.NewGame();
    }

    // the next row up or down; the option row only for a mode that has an option, music and sounds share a line
    static void _MoveRow(int step)
    {
        int row = _menuRow == _RowSounds ? _RowMusic : _menuRow;
        row = step < 0 ? (row == _RowMode ? _RowButtons : row == _RowButtons ? _RowMusic : row - 1) : (row == _RowButtons ? _RowMode : row == _RowMusic ? _RowButtons : row + 1);
        if (row == _RowOption && !HasOption(_mode))
            row = step < 0 ? _RowMode : _RowMusic;
        _menuRow = row;
    }

    static void _ToggleSounds()
    {
        Music.SetSoundsOn(!Music.SoundsOn());
        SaveSettings();
        // lets the player hear that the sounds are back
        Music.Play(Sfx.Roll, 0);
    }

    // left and right: the mode, its option, between music and sounds, or between the buttons
    static void _ChangeOption(int step)
    {
        if (_menuRow == _RowMode)
            _mode = (Mode)(((int)_mode + ModeCount + step) % ModeCount);
        else if (_menuRow == _RowMusic)
            _menuRow = _RowSounds;
        else if (_menuRow == _RowSounds)
            _menuRow = _RowMusic;
        else if (_menuRow == _RowButtons)
            _menuButton = (_menuButton + _ButtonCount + step) % _ButtonCount;
        else if (_mode == Mode.Countdown)
            _countdownChoice = (_countdownChoice + CountdownMinutes.Length + step) % CountdownMinutes.Length;
        else if (_mode == Mode.Score)
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

    // the first 9 digits of a text as a seed; -1 if it has no digit
    static int _ParseSeed(string text)
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
        return digits > 0 ? value : -1;
    }

    // takes the digits of a pasted text as the seed
    static void _Paste(string text)
    {
        int value = _ParseSeed(text);
        if (value < 0)
        {
            Render.Toast("NO SEED IN THE CLIPBOARD");
            return;
        }
        _seed = value;
        _seedFixed = true;
        Render.Toast("SEED PASTED");
    }
}
