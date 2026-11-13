//! The Shifty Bits music editor: a window (MiniFB) with a piano roll for the song file of the game. It uses the game's
//! own synthesizer and sound output, so the music sounds here as it does in the game.
//! `MusicEditor.exe [song file]`; without an argument it looks for `song.txt` in this folder and the ones above.
//! `MusicEditor.exe --shot image.png [song file]` draws the editor into an image instead, and
//! `MusicEditor.exe --selftest [song file]` edits the song in memory and checks the results (both for testing).

namespace ShiftyBits;

using System;
using Mfb from "MiniFB.h";

Mfb.mfb_window* _window;

// the mouse position in pixels of the framebuffer (the window can be larger on a scaled display)
unsafe void _SetMouse(int x, int y)
{
    int w = (int)Mfb.mfb_get_window_width(_window);
    int h = (int)Mfb.mfb_get_window_height(_window);
    if (w > 0 && h > 0)
    {
        x = x * ScreenW / w;
        y = y * ScreenH / h;
    }
    Editor.MouseMove(x, y);
}

void OnKey(Mfb.mfb_window* window, Mfb.mfb_key key, Mfb.mfb_key_mod mod, bool pressed)
{
    if (pressed)
        Editor.Key((int)key, (int)mod);
}

void OnMouseButton(Mfb.mfb_window* window, Mfb.mfb_mouse_button button, Mfb.mfb_key_mod mod, bool pressed)
{
    Editor.MouseButton((int)button, pressed, (int)mod);
}

void OnMouseMove(Mfb.mfb_window* window, int x, int y)
{
    _SetMouse(x, y);
}

void OnScroll(Mfb.mfb_window* window, Mfb.mfb_key_mod mod, float dx, float dy)
{
    Editor.Scroll(dy > 0.0f ? 1 : dy < 0.0f ? -1 : 0, (int)mod);
}

bool OnClose(Mfb.mfb_window* window)
{
    return Editor.MayQuit();
}

int Main(string[] args)
{
    Gfx.Init();
    Music.Init(AudioRate);
    // for testing: draws the editor once into a PNG file, without a window
    if (args.Length >= 2 && args[0] == "--shot")
    {
        Editor.Open(args.Length >= 3 ? args[2] : "");
        Editor.MouseMove(500, 300);
        Editor.Frame(0.0);
        if (File.WriteAllBytes(args[1], Screenshot.Encode()) is error e)
            return 1;
        return 0;
    }
    if (args.Length >= 1 && args[0] == "--selftest")
    {
        Editor.Open(args.Length >= 2 ? args[1] : "");
        return Editor.SelfTest();
    }
    Audio.Init();
    Editor.Open(args.Length >= 1 ? args[0] : "");

    _window = Mfb.mfb_open_ex("Shifty Bits Music Editor", (uint32)ScreenW, (uint32)ScreenH, 0u);
    if (_window == null)
    {
        Console.WriteLine("cannot open the window");
        return 1;
    }
    Mfb.mfb_set_keyboard_callback(_window, OnKey);
    Mfb.mfb_set_mouse_button_callback(_window, OnMouseButton);
    Mfb.mfb_set_mouse_move_callback(_window, OnMouseMove);
    Mfb.mfb_set_mouse_scroll_callback(_window, OnScroll);
    Mfb.mfb_set_close_callback(_window, OnClose);
    Mfb.mfb_set_target_fps(60);

    var timer = Mfb.mfb_timer_create();
    while (true)
    {
        Editor.Frame(Math.Min(0.1, Mfb.mfb_timer_delta(timer)));
        Audio.Pump();
        if (Editor.Quitting())
            Mfb.mfb_close(_window);
        unsafe
        {
            if (Mfb.mfb_update_ex(_window, Gfx.Pixels(), (uint32)ScreenW, (uint32)ScreenH) != Mfb.mfb_update_state.MFB_STATE_OK)
                break;
        }
        if (!Mfb.mfb_wait_sync(_window))
            break;
    }
    Mfb.mfb_timer_destroy(timer);
    Audio.Shutdown();
    Gfx.Shutdown();
    return 0;
}
