//! Shifty Bits in the browser (wasm backend): JavaScript calls `_Frame` once per animation frame, draws the framebuffer
//! into a canvas and plays the samples with Web Audio. All `web_*` functions are imported from JavaScript
//! (web/shiftybits.js).

namespace ShiftyBits;

using System;

extern "C" void web_set_frame(Action<double> frame);
extern "C" void web_run();
extern "C" void web_present(uint32* pixels, int count);
extern "C" int web_poll_key();
extern "C" int web_poll_pointer();
extern "C" int web_touch();
extern "C" int web_sound_waiting();
extern "C" void web_seed_rect(int x, int y, int w, int h);
extern "C" void web_state(int state);
extern "C" int web_audio_rate();
extern "C" int web_audio_wanted();
extern "C" void web_audio_write(float* samples, int count);
extern "C" int web_load_best(int slot);
extern "C" void web_save_best(int slot, int value);
extern "C" void web_copy(char* text);
extern "C" int web_paste(uint8* buffer, int size);
extern "C" void web_download(char* name, uint8* data, int length);
extern "C" void web_fullscreen();

const int _ChunkSamples = 1024;

float* _audioChunk;

/// What the game needs from the browser.
struct Platform
{
    /// The value of `slot` kept in the browser, a best value or the settings (0 if none).
    static int LoadBest(int slot)
    {
        return web_load_best(slot);
    }

    /// Keeps the value of `slot` in the browser.
    static void SaveBest(int slot, int value)
    {
        web_save_best(slot, value);
    }

    /// The browser version only has its built-in songs.
    static void LoadSongFile(int index)
    {
    }

    /// Whether the browser runs on a phone or tablet (its main pointer is a finger).
    static bool IsTouch()
    {
        return web_touch() != 0;
    }

    /// Whether the browser still waits for a key or a click before it may play sound.
    static bool SoundWaiting()
    {
        return web_sound_waiting() != 0;
    }

    /// Puts `text` on the clipboard.
    static unsafe void CopyText(string text)
    {
        web_copy(text.CStr());
    }

    /// The text of the last paste: the browser hands it over with its paste event, then sends Ctrl+V to the game.
    static unsafe string PasteText()
    {
        var buffer = new uint8[64];
        int n = web_paste(&buffer[0], buffer.Length);
        return string.FromBytes(buffer, 0, n);
    }

    /// Offers the screenshot as a download and returns the message for the player.
    static unsafe string StoreScreenshot(string name, uint8[] png)
    {
        // JavaScript copies the bytes during the call
        web_download(name.CStr(), &png[0], png.Length);
        return "DOWNLOADED " + name;
    }

    /// Switches fullscreen on or off.
    static void ToggleFullscreen()
    {
        web_fullscreen();
    }

    /// A browser tab is closed by the player, not by the game.
    static void Quit()
    {
    }
}

// called by JavaScript for every animation frame
unsafe void _Frame(double dt)
{
    while (true)
    {
        int key = web_poll_key();
        if (key < 0)
            break;
        // bit 20 marks the first key press of the player, which switches the sound on
        _inputStartsSound = (key & (1 << 20)) != 0;
        Input.Key(key & 0xffff, (key >> 16) & 0xf);
        _inputStartsSound = false;
    }
    while (true)
    {
        // x in the low 12 bits, then y, then 1 for a click or tap and 0 for a move, then 1 for the first click of the
        // player, which switches the sound on
        int pointer = web_poll_pointer();
        if (pointer < 0)
            break;
        _inputStartsSound = ((pointer >> 25) & 1) != 0;
        if (((pointer >> 24) & 1) != 0)
            Input.Pointer(pointer & 0xfff, (pointer >> 12) & 0xfff);
        else
            Input.PointerMove(pointer & 0xfff, (pointer >> 12) & 0xfff);
        _inputStartsSound = false;
    }
    // the page shows the touch buttons that fit: 0 menu, 1 playing, 2 paused, 3 game over, 4 help, 5 intro
    int state = 1;
    if (_state == State.Intro)
        state = 5;
    else if (_showHelp)
        state = 4;
    else if (_state == State.Menu)
        state = 0;
    else if (_state == State.GameOver)
        state = 3;
    else if (_paused)
        state = 2;
    web_state(state);
    // where a tap opens the on-screen keyboard for the seed: only in the menu
    if (_state == State.Menu && !_showHelp)
        web_seed_rect(MenuSeedX, Menu.SeedY(), MenuSeedW, MenuSeedH);
    else
        web_seed_rect(0, 0, 0, 0);
    Game.Update(Math.Min(0.1, dt));
    Render.Frame();
    int wanted = web_audio_wanted();
    while (wanted > 0)
    {
        int n = Math.Min(wanted, _ChunkSamples);
        Music.Render(_audioChunk, n);
        web_audio_write(_audioChunk, n);
        wanted -= n;
    }
    web_present(Gfx.Pixels(), ScreenW * ScreenH);
}

unsafe int Main()
{
    Gfx.Init();
    Render.Init();
    Music.Init(web_audio_rate());
    _audioChunk = (float*)Memory.Allocate(_ChunkSamples * sizeof(float));
    Menu.Open();
    Intro.Start();
    web_set_frame(_Frame);
    // hands control to the browser; Main never returns, so nothing is cleaned up
    web_run();
    return 0;
}
