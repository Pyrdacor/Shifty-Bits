//! Shifty Bits on the desktop: window and keyboard via MiniFB, sound via winmm (audio.csh), the Windows clipboard for the
//! seed, files for the best values and the screenshots.

namespace ShiftyBits;

using System;
using Mfb from "MiniFB.h";

const string _BestFile = "shiftybits-best.txt";

const uint32 _CfText = 1;
const uint32 _GmemMoveable = 2;

extern "C" int OpenClipboard(void* owner);
extern "C" int CloseClipboard();
extern "C" int EmptyClipboard();
extern "C" void* GetClipboardData(uint32 format);
extern "C" void* SetClipboardData(uint32 format, void* memory);
extern "C" void* GlobalAlloc(uint32 flags, nuint bytes);
extern "C" void* GlobalLock(void* memory);
extern "C" int GlobalUnlock(void* memory);

bool _fullscreen;
bool _toggleFullscreen;
bool _quit;

/// What the game needs from the operating system.
struct Platform
{
    /// The value saved earlier in `slot`, a best value or the settings (0 if none).
    static int LoadBest(int slot)
    {
        return _LoadBests()[slot];
    }

    /// Saves the value of `slot`.
    static void SaveBest(int slot, int value)
    {
        var bests = _LoadBests();
        bests[slot] = value;
        string text = "";
        for (var i = 0; i < StoredSlots; i += 1)
        {
            text += bests[i].ToString() + "\n";
        }
        File.WriteAllText(_BestFile, text);
    }

    // one value per line: the best values, then the settings; a file of an older version has fewer lines (the first
    // version only one, the best score of the normal mode)
    static int[] _LoadBests()
    {
        var bests = new int[StoredSlots];
        if (!File.Exists(_BestFile))
            return bests;
        if (File.ReadAllText(_BestFile) is string text)
        {
            var lines = text.Split('\n');
            for (var i = 0; i < lines.Length && i < StoredSlots; i += 1)
            {
                if (lines[i].Trim().ParseInt() is int value)
                    bests[i] = value;
            }
        }
        return bests;
    }

    /// A song file beside the game (`SongFiles`) replaces the built-in song of that number, so that music from the
    /// editor can be tried without building.
    static void LoadSongFile(int index)
    {
        string path = SongFiles[index];
        if (!File.Exists(path))
            return;
        if (File.ReadAllText(path) is string text)
        {
            var lines = List<string>.Create();
            foreach (var line in text.Split('\n'))
            {
                lines.Add(line.ToString());
            }
            Music.LoadSong(lines.ToArray());
        }
    }

    /// Whether the game runs on a phone or tablet (never on the desktop).
    static bool IsTouch()
    {
        return false;
    }

    /// Puts `text` on the clipboard.
    static unsafe void CopyText(string text)
    {
        if (OpenClipboard(null) == 0)
            return;
        EmptyClipboard();
        void* memory = GlobalAlloc(_GmemMoveable, (nuint)(text.Length + 1));
        if (memory != null)
        {
            uint8* p = (uint8*)GlobalLock(memory);
            for (var i = 0; i < text.Length; i += 1)
            {
                p[i] = (uint8)text[i];
            }
            p[text.Length] = 0;
            GlobalUnlock(memory);
            // the clipboard owns the memory from here on
            SetClipboardData(_CfText, memory);
        }
        CloseClipboard();
    }

    /// The text on the clipboard ("" if there is none).
    static unsafe string PasteText()
    {
        if (OpenClipboard(null) == 0)
            return "";
        string text = "";
        void* memory = GetClipboardData(_CfText);
        if (memory != null)
        {
            char* p = (char*)GlobalLock(memory);
            if (p != null)
            {
                text = string.FromCStr(p);
                GlobalUnlock(memory);
            }
        }
        CloseClipboard();
        return text;
    }

    /// Stores a screenshot and returns the message for the player.
    static string StoreScreenshot(string name, uint8[] png)
    {
        if (!Directory.Exists("screenshots"))
            Directory.Create("screenshots");
        string path = "screenshots/" + name;
        if (File.WriteAllBytes(path, png) is error e)
            return "COULD NOT SAVE " + path;
        return "SAVED " + path;
    }

    /// Switches between window and fullscreen (done by the main loop).
    static void ToggleFullscreen()
    {
        _toggleFullscreen = true;
    }

    /// Ends the program.
    static void Quit()
    {
        _quit = true;
    }
}

void OnKey(Mfb.mfb_window* window, Mfb.mfb_key key, Mfb.mfb_key_mod mod, bool pressed)
{
    if (pressed)
        Input.Key((int)key, (int)mod);
}

// a pixel of the window as a pixel of the screen: the image is scaled to fit the window and centered in it
unsafe void _ToScreen(Mfb.mfb_window* window, int x, int y, bool click)
{
    double w = (double)Mfb.mfb_get_window_width(window);
    double h = (double)Mfb.mfb_get_window_height(window);
    if (w <= 0.0 || h <= 0.0)
        return;
    double scale = Math.Min(w / ScreenW, h / ScreenH);
    int sx = (int)((x - (w - ScreenW * scale) / 2.0) / scale);
    int sy = (int)((y - (h - ScreenH * scale) / 2.0) / scale);
    if (click)
        Input.Pointer(sx, sy);
    else
        Input.PointerMove(sx, sy);
}

void OnMouseButton(Mfb.mfb_window* window, Mfb.mfb_mouse_button button, Mfb.mfb_key_mod mod, bool pressed)
{
    if (pressed && (int)button == 1)
        _ToScreen(window, Mfb.mfb_get_mouse_x(window), Mfb.mfb_get_mouse_y(window), true);
}

void OnMouseMove(Mfb.mfb_window* window, int x, int y)
{
    _ToScreen(window, x, y, false);
}

bool OnClose(Mfb.mfb_window* window)
{
    return true;
}

// opens the game window, either as a window or as a borderless fullscreen window with the image scaled to fit
Mfb.mfb_window* _OpenWindow()
{
    uint32 flags = _fullscreen ? (uint32)Mfb.MFB_WF_FULLSCREEN_DESKTOP : 0u;
    var window = Mfb.mfb_open_ex("Shifty Bits", (uint32)ScreenW, (uint32)ScreenH, flags);
    if (window == null)
        return window;
    Mfb.mfb_set_keyboard_callback(window, OnKey);
    Mfb.mfb_set_mouse_button_callback(window, OnMouseButton);
    Mfb.mfb_set_mouse_move_callback(window, OnMouseMove);
    Mfb.mfb_set_close_callback(window, OnClose);
    if (_fullscreen)
        Mfb.mfb_set_viewport_best_fit(window, (uint32)ScreenW, (uint32)ScreenH);
    return window;
}

// ---- main loop ----

int Main(string[] args)
{
    if (args.Length >= 2 && args[0] == "--shot")
        return TestOutput.Write(args[1], args.Length >= 3 ? args[2] : "");

    _fullscreen = args.Length >= 1 && args[0] == "--fullscreen";
    Gfx.Init();
    Render.Init();
    Music.Init(AudioRate);
    Audio.Init();
    Menu.Open();
    Mfb.mfb_set_target_fps(60);

    var timer = Mfb.mfb_timer_create();
    bool running = true;
    while (running)
    {
        var window = _OpenWindow();
        if (window == null)
        {
            Console.WriteLine("cannot open the window");
            return 1;
        }
        _toggleFullscreen = false;
        while (true)
        {
            double dt = Math.Min(0.1, Mfb.mfb_timer_delta(timer));
            Game.Update(dt);
            Render.Frame();
            Audio.Pump();
            if (_quit)
                Mfb.mfb_close(window);
            unsafe
            {
                if (Mfb.mfb_update_ex(window, Gfx.Pixels(), (uint32)ScreenW, (uint32)ScreenH) != Mfb.mfb_update_state.MFB_STATE_OK)
                {
                    running = false;
                    break;
                }
            }
            if (_toggleFullscreen)
            {
                // MiniFB cannot change the mode of an open window: close it and open a new one
                _fullscreen = !_fullscreen;
                Mfb.mfb_close(window);
                unsafe
                {
                    Mfb.mfb_update_ex(window, Gfx.Pixels(), (uint32)ScreenW, (uint32)ScreenH);
                }
                break;
            }
            if (!Mfb.mfb_wait_sync(window))
            {
                running = false;
                break;
            }
        }
    }
    Mfb.mfb_timer_destroy(timer);
    Audio.Shutdown();
    Gfx.Shutdown();
    return 0;
}
