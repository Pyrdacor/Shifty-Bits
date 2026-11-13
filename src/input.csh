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
/// Modifier bit for Ctrl.
const int ModCtrl = 2;
/// Modifier bit for Alt.
const int ModAlt = 4;

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
        if (_showHelp)
        {
            _showHelp = false;
            return;
        }
        if (_state == State.Menu)
        {
            Menu.Key(k, mods);
            return;
        }
        if (k == KeyEscape)
        {
            Menu.Open();
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
