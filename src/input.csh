//! Keyboard handling shared by all platforms. Key codes are those of MiniFB (letters are their ASCII capitals); the
//! web platform translates browser key codes to them.

namespace ShiftyBits;

using System;

const int KeyEscape = 256;
const int KeyEnter = 257;
const int KeyBackspace = 259;
const int KeyDelete = 261;
const int KeyRight = 262;
const int KeyLeft = 263;
const int KeyDown = 264;
const int KeyUp = 265;
const int KeyF1 = 290;
const int KeyF11 = 300;
const int KeyF12 = 301;
/// The 0 of the number pad; the other digits follow.
const int KeyPad0 = 320;
const int KeyPadEnter = 335;
/// Not a key: the platform has new text for the seed (`Platform.PasteText`), typed on an on-screen keyboard.
const int KeySeedInput = 1000;
/// Modifier bit for Ctrl.
const int ModCtrl = 2;
/// Modifier bit for Alt.
const int ModAlt = 4;

// set by the platform while it hands over the first key press or click of the player: in the browser, that is the
// moment the sound can start
bool _inputStartsSound;
// true while the game asks whether to quit the running game; it is paused meanwhile
bool _confirmQuit;
bool _pausedBeforeQuit;
// what the pointer is over during a game: 1 the MENU button, 2 YES, 3 NO, 0 nothing
int _gameHover;

/// Turns key presses into game actions.
struct Input
{
    /// Handles one key press.
    static void Key(int k, int mods)
    {
        if (k == KeyF11 || (k == KeyEnter && (mods & ModAlt) != 0))
        {
            Platform.ToggleFullscreen();
            return;
        }
        if (_state == State.Intro)
        {
            // Esc always skips, even the key that switches the sound on
            if (k == KeyEscape)
                _inputStartsSound = false;
            Intro.Input();
            return;
        }
        if (k == 'C' && (mods & ModCtrl) != 0)
        {
            Platform.CopyText(_seed.ToString());
            Render.Toast("SEED " + _seed.ToString() + " COPIED");
            return;
        }
        if (k == 'M')
        {
            Music.Toggle();
            Menu.SaveSettings();
            Render.Toast(Music.IsOn() ? "MUSIC ON" : "MUSIC OFF");
            return;
        }
        if (_showHelp || _showAwards)
        {
            _showHelp = false;
            _showAwards = false;
            return;
        }
        if (_state == State.Menu)
        {
            Menu.Key(k, mods);
            return;
        }
        if (_confirmQuit)
        {
            if (k == KeyEnter || k == KeyPadEnter || k == ' ' || k == 'Y')
                _Quit();
            else if (k == KeyEscape || k == 'N')
                _Stay();
            return;
        }
        if (k == KeyEscape)
        {
            if (_state == State.GameOver)
                Menu.Open();
            else
                _AskQuit();
            return;
        }
        if (_state == State.GameOver)
        {
            if (k == KeyEnter || k == KeyPadEnter || k == ' ' || k == 'R')
                Game.Restart();
            else if (k == 'S' || k == KeyF12)
                TakeScreenshot();
            return;
        }
        if (k == 'P')
        {
            _paused = !_paused;
            Music.SetPaused(_paused);
            return;
        }
        if (_paused)
            return;
        if (k == KeyLeft)
            Game.Move(-1);
        else if (k == KeyRight)
            Game.Move(1);
        else if (k == KeyDown)
            Game.SoftDrop();
        else if (k == ' ')
            Game.HardDrop();
        else if (k == 'A' || k == 'Z' || k == 'Y')
            Game.Roll(-1);
        else if (k == 'D' || k == 'X')
            Game.Roll(1);
        else if (k == 'W' || k == KeyUp)
            Game.RollVertical(-1);
        else if (k == 'S')
            Game.RollVertical(1);
        else if (k == 'R')
            Game.Restart();
        else if (k == 'H' || k == KeyF1)
            _showHelp = true;
    }

    /// Handles a click or tap at a pixel of the screen.
    static void Pointer(int x, int y)
    {
        if (_state == State.Intro)
            Intro.Input();
        else if (_showHelp || _showAwards)
        {
            _showHelp = false;
            _showAwards = false;
        }
        else if (_state == State.Menu)
            Menu.Pointer(x, y);
        else
        {
            int element = _GameElementAt(x, y);
            if (element == 2)
                _Quit();
            else if (element == 3)
                _Stay();
            else if (element == 1)
            {
                // after a game there is nothing to lose
                if (_state == State.GameOver)
                    Menu.Open();
                else
                    _AskQuit();
            }
        }
    }

    /// Handles the mouse moving to a pixel of the screen.
    static void PointerMove(int x, int y)
    {
        Menu.Hover(x, y);
        _gameHover = _state == State.Menu || _state == State.Intro ? 0 : _GameElementAt(x, y);
    }

    // the button of a game at a pixel: 1 MENU, 2 YES, 3 NO (only while the question is shown), 0 none
    static int _GameElementAt(int x, int y)
    {
        if (_confirmQuit)
        {
            if (y >= QuitButtonY && y < QuitButtonY + QuitButtonH)
            {
                if (x >= QuitYesX && x < QuitYesX + QuitButtonW)
                    return 2;
                if (x >= QuitNoX && x < QuitNoX + QuitButtonW)
                    return 3;
            }
            return 0;
        }
        if (x >= GameMenuX && x < GameMenuX + GameMenuW && y >= GameMenuY && y < GameMenuY + GameMenuH)
            return 1;
        return 0;
    }

    // asks whether to quit the running game, and pauses it meanwhile
    static void _AskQuit()
    {
        _pausedBeforeQuit = _paused;
        _paused = true;
        Music.SetPaused(true);
        _confirmQuit = true;
    }

    static void _Quit()
    {
        _confirmQuit = false;
        Menu.Open();
    }

    // back to the game, paused if it was paused before
    static void _Stay()
    {
        _confirmQuit = false;
        _paused = _pausedBeforeQuit;
        Music.SetPaused(_paused);
    }

    /// Renders the screen without prompts, encodes it as PNG and hands it to the platform to store.
    static void TakeScreenshot()
    {
        string name = "shiftybits-" + DateTime.Now().ToString("yyyyMMdd-HHmmss") + ".png";
        _capturing = true;
        Render.Frame();
        _capturing = false;
        Render.Toast(Platform.StoreScreenshot(name, Screenshot.Encode()));
    }
}
