//! Test output without a window: a rendered screenshot or a WAV file of the music
//! (`ShiftyBits.exe --shot <file> [play|over|help|menu|pointer|countdown|score|nonzero|music]`).

namespace ShiftyBits;

using System;

/// Renders game screens and music into files.
struct TestOutput
{
    /// Writes `path`: the menu (`mode` menu), a screenshot after a few automatic moves (`mode` play, over or help),
    /// a game played to its end in another game mode (`mode` countdown, score or nonzero), or 40 seconds of music as
    /// a WAV file (`mode` music).
    static int Write(string path, string mode)
    {
        Gfx.Init();
        Render.Init();
        Music.Init(AudioRate);
        if (mode == "music2" || mode == "music3" || mode == "music4")
        {
            // the other built-in songs
            Music.SelectSong(mode == "music2" ? 1 : mode == "music3" ? 2 : 3);
            return _MusicWav(path);
        }
        if (mode == "music" || mode == "sounds")
        {
            // "sounds": the same file without the music, to check the sound effects alone
            Music.SetOn(mode == "music");
            return _MusicWav(path);
        }
        Menu.Open();
        _seed = 12345;
        _countdownChoice = 0;
        _scoreChoice = 0;
        bool menu = mode == "menu" || mode == "pointer";
        if (mode == "pointer")
        {
            // the menu used with the mouse: the next countdown option, the score mode, its option before the first
            // one (the last), then the mouse over the PLAY button
            int rowY = MenuRowY + 20;
            Input.Pointer(MenuRowX + MenuRowW - 40, rowY + MenuRowPitch);
            Input.Pointer(MenuRowX + 100, rowY + 2 * MenuRowPitch);
            Input.Pointer(MenuRowX + MenuRowW - MenuOptionW + 10, rowY + 2 * MenuRowPitch);
            Input.PointerMove(MenuPlayX + 10, MenuButtonY + 10);
            Console.WriteLine("countdown option " + _countdownChoice.ToString() + ", score option " + _scoreChoice.ToString() + ", row " + _menuRow.ToString());
        }
        bool toEnd = mode == "over";
        if (mode == "countdown" || mode == "score" || mode == "nonzero")
        {
            _mode = mode == "countdown" ? Mode.Countdown : mode == "score" ? Mode.Score : Mode.NonZero;
            _menuRow = (int)_mode;
            toEnd = true;
        }
        if (!menu)
            Game.NewGame();
        _showHelp = mode == "help";
        if (mode != "help" && !menu)
        {
            int drops = toEnd ? 4000 : 30;
            for (var i = 0; i < drops && _state != State.GameOver; i += 1)
            {
                if (_state == State.Playing)
                {
                    Game.Move(_rng.Next(-5, 6));
                    Game.HardDrop();
                }
                for (var s = 0; s < 120 && _state != State.Playing && _state != State.GameOver; s += 1)
                {
                    Game.Update(1.0 / 60.0);
                }
            }
            if (_state == State.Playing)
            {
                Game.Roll(-1);
                Game.Update(0.3);
            }
        }
        _capturing = mode == "over" && _state == State.GameOver;
        Console.WriteLine(Game.ModeText() + ": score " + _score.ToString() + ", time " + Game.TimeText(_playTime, true));
        Render.Frame();
        _capturing = false;
        if (mode == "pointer")
        {
            // after the image: PLAY must start the selected mode
            Input.Pointer(MenuPlayX + 10, MenuButtonY + 10);
            Console.WriteLine("after PLAY: " + (_state == State.Playing ? "playing " : "not playing ") + Game.ModeText());
        }
        if (File.WriteAllBytes(path, Screenshot.Encode()) is error e)
            return 1;
        return 0;
    }

    // 40 seconds of music with a few sound effects
    static unsafe int _MusicWav(string path)
    {
        Music.Start();
        int count = AudioRate * 40;
        var bytes = new uint8[44 + count * 2];
        _Tag(bytes, 0, "RIFF");
        _Tag(bytes, 8, "WAVE");
        _Tag(bytes, 12, "fmt ");
        _Tag(bytes, 36, "data");
        _Le32(bytes, 4, 36 + count * 2);
        _Le32(bytes, 16, 16);
        bytes[20] = 1;
        bytes[22] = 1;
        _Le32(bytes, 24, AudioRate);
        _Le32(bytes, 28, AudioRate * 2);
        bytes[32] = 2;
        bytes[34] = 16;
        _Le32(bytes, 40, count * 2);
        float* buf = (float*)Memory.Allocate(1024 * sizeof(float));
        int pos = 0;
        int second = -1;
        while (pos < count)
        {
            int n = Math.Min(1024, count - pos);
            if (pos / AudioRate != second)
            {
                second = pos / AudioRate;
                if (second % 5 == 2)
                    Music.Play(Sfx.Lock, 0);
                if (second % 7 == 4)
                    Music.Play(Sfx.Clear, second % 3 + 1);
                if (second == 20)
                    Music.Play(Sfx.LevelUp, 0);
            }
            Music.Render(buf, n);
            for (var i = 0; i < n; i += 1)
            {
                int v = (int)(buf[i] * 32000.0f);
                bytes[44 + (pos + i) * 2] = (uint8)(v & 0xff);
                bytes[45 + (pos + i) * 2] = (uint8)((v >> 8) & 0xff);
            }
            pos += n;
        }
        Memory.Free(buf);
        if (File.WriteAllBytes(path, bytes) is error e)
            return 1;
        return 0;
    }

    static void _Tag(uint8[] b, int at, string tag)
    {
        for (var i = 0; i < 4; i += 1)
        {
            b[at + i] = (uint8)tag[i];
        }
    }

    static void _Le32(uint8[] b, int at, int v)
    {
        b[at] = (uint8)(v & 0xff);
        b[at + 1] = (uint8)((v >> 8) & 0xff);
        b[at + 2] = (uint8)((v >> 16) & 0xff);
        b[at + 3] = (uint8)((v >> 24) & 0xff);
    }
}
