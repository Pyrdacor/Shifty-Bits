//! The main menu: choosing the game mode with its option, the song and the sounds, and entering, copying or pasting
//! the seed, with the keyboard or with the mouse or a finger. The places of its parts are constants here, so that
//! the drawing (render.csh) and the pointer agree.

namespace ShiftyBits;

using System;

// the row of the menu that chooses the song or switches the music off; the rows before it are the modes
const int _RowMusic = ModeCount;
// the row for the sound effects, drawn beside the music row
const int _RowSounds = ModeCount + 1;

// what the pointer can hit besides the rows
const int _ElSeed = ModeCount + 2;
const int _ElPlay = ModeCount + 3;
const int _ElNewSeed = ModeCount + 4;
const int _ElHelp = ModeCount + 5;

const int MenuW = 780;
const int MenuH = 600;
const int MenuX = (ScreenW - MenuW) / 2;
const int MenuY = (ScreenH - MenuH) / 2;
// the rows of the game modes
const int MenuRowX = MenuX + 24;
const int MenuRowW = MenuW - 48;
const int MenuRowY = MenuY + 108;
const int MenuRowPitch = 70;
const int MenuRowH = 62;
// the part at the right of a mode row that changes its option: its left half goes back, its right half on
const int MenuOptionW = 292;
// music and sounds beside each other
const int MenuSwitchY = MenuY + 390;
const int MenuSwitchH = 40;
const int MenuSwitchW = (MenuRowW - 12) / 2;
// the seed with its label
const int MenuSeedX = MenuX + 36;
const int MenuSeedY = MenuY + 440;
const int MenuSeedW = 340;
const int MenuSeedH = 40;
// the buttons shown instead of the key hints when the pointer is used
const int MenuButtonY = MenuY + MenuH - 64;
const int MenuButtonH = 44;
const int MenuPlayX = MenuX + 60;
const int MenuPlayW = 260;
const int MenuNewSeedX = MenuX + 336;
const int MenuNewSeedW = 220;
const int MenuHelpX = MenuX + 572;
const int MenuHelpW = 148;

// true while the menu is used with the mouse or a finger: it shows buttons instead of the key hints
bool _pointerMode;
// what the mouse is over (a row or one of the `_El` constants), -1 for nothing
int _menuHover = -1;

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
            // a phone or tablet starts with the buttons
            _pointerMode = Platform.IsTouch();
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
                _ToggleSounds();
            else
                _Start();
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

    /// What is at a pixel of the screen: a row of the menu, one of the `_El` constants, or -1.
    static int ElementAt(int x, int y)
    {
        if (x >= MenuRowX && x < MenuRowX + MenuRowW)
        {
            for (var row = 0; row < ModeCount; row += 1)
            {
                int ry = MenuRowY + row * MenuRowPitch;
                if (y >= ry && y < ry + MenuRowH)
                    return row;
            }
            if (y >= MenuSwitchY && y < MenuSwitchY + MenuSwitchH)
            {
                if (x < MenuRowX + MenuSwitchW)
                    return _RowMusic;
                if (x >= MenuRowX + MenuRowW - MenuSwitchW)
                    return _RowSounds;
            }
        }
        if (x >= MenuSeedX && x < MenuSeedX + MenuSeedW && y >= MenuSeedY && y < MenuSeedY + MenuSeedH)
            return _ElSeed;
        if (_pointerMode && y >= MenuButtonY && y < MenuButtonY + MenuButtonH)
        {
            if (x >= MenuPlayX && x < MenuPlayX + MenuPlayW)
                return _ElPlay;
            if (x >= MenuNewSeedX && x < MenuNewSeedX + MenuNewSeedW)
                return _ElNewSeed;
            if (x >= MenuHelpX && x < MenuHelpX + MenuHelpW)
                return _ElHelp;
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
        if (element < ModeCount)
        {
            bool wasSelected = _menuRow == element;
            _menuRow = element;
            bool hasOption = element == (int)Mode.Countdown || element == (int)Mode.Score;
            int optionX = MenuRowX + MenuRowW - MenuOptionW;
            // the option at the right changes; anywhere else, a second click on the selected mode starts it
            if (hasOption && x >= optionX)
                _ChangeOption(x < optionX + MenuOptionW / 2 ? -1 : 1);
            else if (wasSelected)
                _Start();
        }
        else if (element == _RowMusic)
        {
            _menuRow = element;
            _NextSong();
        }
        else if (element == _RowSounds)
        {
            _menuRow = element;
            _ToggleSounds();
        }
        else if (element == _ElPlay)
            _Start();
        else if (element == _ElNewSeed)
            _RandomSeed();
        else if (element == _ElHelp)
            _showHelp = true;
        // a tap on the seed opens the on-screen keyboard: the browser does that itself (web/shiftybits.js)
    }

    // starts the mode under the cursor; from the music and sound row, the mode played last
    static void _Start()
    {
        if (_menuRow < ModeCount)
            _mode = (Mode)_menuRow;
        Game.NewGame();
    }

    static void _ToggleSounds()
    {
        Music.SetSoundsOn(!Music.SoundsOn());
        SaveSettings();
        // lets the player hear that the sounds are back
        Music.Play(Sfx.Roll, 0);
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
