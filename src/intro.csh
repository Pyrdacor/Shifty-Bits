//! The intro: a little demo in the style of the Amiga and Atari ST scene. A sunset sky with copper bars, three layers
//! of mountains and a checkerboard floor scroll by, chains of 0s and 1s wind through the picture, the title flies in
//! letter by letter, words zoom towards the player and a sine scroller runs along the bottom, all to its own chip tune
//! (intro.txt). A click or a key skips it; it ends by itself when the song is over.

namespace ShiftyBits;

using System;

const ReadOnlySlice<string> _IntroSongLines = embed_lines("../intro.txt");

// the timing follows the song: 132 beats per minute, 4 beats per bar, 24 bars
const double _IntroBar = 4.0 * 60.0 / 132.0;
// the melody (and the scroller) start in bar 5, the zooming words fly in bars 13 to 20
const double _ScrollStart = 4.0 * _IntroBar;
const double _ZoomStart = 12.0 * _IntroBar;
const double _IntroEnd = 24.0 * _IntroBar;
const double _IntroFadeIn = 0.8;
const double _IntroFadeOut = 0.7;

// where the floor begins
const int _Horizon = 520;
// the mountains repeat after this many pixels
const int _LandW = 1024;
const int _LandLayers = 3;

const string _IntroTitle = "SHIFTY BITS";
const string _IntroByline = "BY PYRDACOR";
const ReadOnlySlice<string> _ZoomWords = ["ROLL", "SHIFT", "MATCH", "CLEAR", "CHAIN", "BITS", "1010", "PLAY!"];
const string _ScrollText = "*** SHIFTY BITS ***   THE BIT ROLLING PUZZLE GAME BY PYRDACOR ...   ROLL THE ROWS AND COLUMNS OF THE FALLING BLOCKS AND LINE UP FOUR EQUAL BITS TO DISSOLVE THEM ...   LONG RUNS, SEVERAL RUNS AT ONCE AND CHAIN REACTIONS GIVE BONUS POINTS ...   FIVE GAME MODES ARE WAITING FOR YOU ...   GREETINGS TO ALL BIT SHIFTERS OUT THERE !!!   PRESS ANY KEY TO PLAY ...";

// one winding chain of bits
struct _Chain
{
    int Y;          // the middle of the wave
    int Amp;        // its height
    double Wave;    // radians per pixel
    double Spin;    // radians per second
    double Speed;   // pixels per second, negative to the right
    int Scale;
    int Light;      // brightness, 256 for full
}

double _introTime;
uint32* _introSky;
int[] _land = [];
_Chain[] _chains = [];

/// The intro shown at the start and from the menu.
struct Intro
{
    /// Shows the intro from its beginning, with its song.
    static void Start()
    {
        if (_land.Length == 0)
            _Prepare();
        _state = State.Intro;
        _showHelp = false;
        _paused = false;
        Restart();
    }

    /// Starts the intro and its song again from the beginning (in the browser when the sound becomes possible).
    static void Restart()
    {
        _introTime = 0.0;
        Music.LoadSong(_IntroSongLines);
        Music.PlayFrom(0);
    }

    /// Leaves the intro for the menu; the song chosen in the menu comes back.
    static void Skip()
    {
        Music.Halt();
        Menu.RestoreSong();
        Menu.Open();
    }

    /// Handles a key press or a click while the intro runs.
    static void Input()
    {
        // in the browser the first key or click switches the sound on: the intro then starts again with its music
        if (_inputStartsSound)
            Restart();
        else
            Skip();
    }

    /// Advances the intro.
    static void Update(double dt)
    {
        _introTime += dt;
        if (_introTime >= _IntroEnd + _IntroFadeOut)
        {
            Achievements.Unlock(AchIntro);
            Skip();
        }
    }

    /// Draws a frame of the intro.
    static unsafe void Draw()
    {
        double t = _introTime;
        Gfx.Restore(_introSky);
        _DrawStars(t);
        _DrawCopperBars(t);
        _DrawLand(t);
        _DrawFloor(t);
        for (var i = 0; i < 4; i += 1)
        {
            _DrawChain(i, t);
        }
        _DrawZoom(t);
        _DrawChain(4, t);
        _DrawTitle(t);
        _DrawByline(t);
        _DrawScroller(t);

        string version = "V" + GameVersion;
        Gfx.TextShadow(ScreenW - 12 - Gfx.TextWidth(version, 2), ScreenH - 22, version, 2, Gfx.Rgb(200, 190, 230));
        string hint = Platform.SoundWaiting() ? "CLICK OR PRESS A KEY FOR SOUND     ESC: SKIP" : "CLICK OR PRESS ANY KEY TO SKIP";
        if (t > 1.5 && (int)(_time * 1.5) % 3 != 0)
            Gfx.TextCentered(ScreenW / 2, ScreenH - 22, hint, 2, Gfx.Rgb(200, 190, 230));

        int dark = 0;
        if (t < _IntroFadeIn)
            dark = (int)((1.0 - t / _IntroFadeIn) * 256.0);
        else if (t > _IntroEnd)
            dark = (int)(Math.Min(1.0, (t - _IntroEnd) / _IntroFadeOut) * 256.0);
        if (dark > 0)
            Gfx.BlendRect(0, 0, ScreenW, ScreenH, 0, dark);
    }

    // ---- drawn once ----

    // the sky with its sun, the shapes of the mountains and the chains
    static unsafe void _Prepare()
    {
        ReadOnlySlice<uint32> sky = [0x08041E, 0x3C145A, 0xBE3C78, 0xFF9646];
        ReadOnlySlice<int> stops = [0, 230, 410, _Horizon];
        for (var y = 0; y < ScreenH; y += 1)
        {
            uint32 c = 0;
            for (var i = 0; i + 1 < stops.Length; i += 1)
            {
                if (y >= stops[i] && y < stops[i + 1])
                    c = Gfx.Mix(sky[i], sky[i + 1], (y - stops[i]) * 256 / (stops[i + 1] - stops[i]));
            }
            Gfx.FillRect(0, y, ScreenW, 1, c);
        }
        // the sun: a gradient from yellow to pink, cut by stripes that grow towards the horizon
        int cx = ScreenW / 2;
        int cy = 360;
        int r = 150;
        Gfx.Glow(cx, cy, r + 90, Gfx.Rgb(255, 120, 90), 70);
        for (var y = cy - r; y < Math.Min(cy + r, _Horizon); y += 1)
        {
            int d = y - (cy - 20);
            if (d > 0 && d % 22 < 4 + d / 14)
                continue;
            int half = (int)Math.Sqrt((double)(r * r - (y - cy) * (y - cy)));
            uint32 c = Gfx.Mix(Gfx.Rgb(255, 240, 120), Gfx.Rgb(255, 50, 150), (y - cy + r) * 256 / (2 * r));
            Gfx.FillRect(cx - half, y, half * 2, 1, c);
        }
        _introSky = Gfx.Snapshot();

        // ridges: sums of |sin| waves that fit the width a whole number of times, so the mountains repeat seamlessly
        _land = new int[_LandLayers * _LandW];
        ReadOnlySlice<int> bases = [430, 468, 500];
        ReadOnlySlice<int> heights = [120, 90, 60];
        for (var l = 0; l < _LandLayers; l += 1)
        {
            for (var x = 0; x < _LandW; x += 1)
            {
                double a = Math.PI * x / _LandW;
                double h = 0.55 * (1.0 - Math.Abs(Math.Sin(a * (3 + l) + l))) + 0.3 * (1.0 - Math.Abs(Math.Sin(a * (7 + 2 * l) + 2.0 * l))) + 0.15 * (1.0 - Math.Abs(Math.Sin(a * (17 + 4 * l))));
                _land[l * _LandW + x] = bases[l] - (int)(h * heights[l]) + (Gfx.Hash(x / 3, l) - 128) / 64;
            }
        }

        _chains = [
            _Chain { Y = 290, Amp = 24, Wave = 0.010, Spin = 1.3, Speed = 45.0, Scale = 2, Light = 120 },
            _Chain { Y = 350, Amp = 20, Wave = 0.013, Spin = -1.1, Speed = -60.0, Scale = 2, Light = 120 },
            _Chain { Y = 320, Amp = 44, Wave = 0.008, Spin = 1.7, Speed = 95.0, Scale = 3, Light = 185 },
            _Chain { Y = 410, Amp = 34, Wave = 0.011, Spin = -1.5, Speed = -120.0, Scale = 3, Light = 185 },
            _Chain { Y = 470, Amp = 52, Wave = 0.007, Spin = 2.1, Speed = 180.0, Scale = 4, Light = 256 },
        ];
    }

    // ---- drawn every frame ----

    static void _DrawStars(double t)
    {
        for (var s = 0; s < 90; s += 1)
        {
            int x = Gfx.Hash(s, 11) * ScreenW / 256 + Gfx.Hash(s, 12) % 4;
            int y = Gfx.Hash(s, 13) * 220 / 256;
            double twinkle = 0.5 + 0.5 * Math.Sin(t * (1.5 + Gfx.Hash(s, 14) / 64.0) + s);
            Gfx.AddPixel(x, y, Gfx.Rgb(230, 230, 255), (int)(40.0 + 200.0 * twinkle));
        }
    }

    // bars of light that swing up and down behind the title, as the copper of the Amiga drew them
    static void _DrawCopperBars(double t)
    {
        ReadOnlySlice<uint32> colors = [0xFF3C50, 0xFFAA28, 0x50E65A, 0x3CAAFF, 0xBE5AFF];
        double appear = Math.Clamp((t - 0.5) / 1.5, 0.0, 1.0);
        for (var i = 0; i < colors.Length; i += 1)
        {
            int y = 150 + (int)(105.0 * Math.Sin(t * 1.6 + i * 0.5) * appear);
            for (var k = 0; k < 20; k += 1)
            {
                int light = 256 - Math.Abs(k * 2 - 19) * 12;
                Gfx.BlendRect(0, y + k - 10, ScreenW, 1, Gfx.Scale(colors[i], light), (int)(210.0 * appear));
            }
        }
    }

    // three ranges of mountains, the nearer ones darker and faster
    static void _DrawLand(double t)
    {
        ReadOnlySlice<uint32> colors = [0x5A2878, 0x3A1A5A, 0x22103A];
        ReadOnlySlice<uint32> rims = [0x9A4CA0, 0x6A3A8A, 0x4A2A6A];
        ReadOnlySlice<int> speeds = [12, 30, 60];
        for (var l = 0; l < _LandLayers; l += 1)
        {
            int offset = (int)(t * speeds[l]);
            for (var x = 0; x < ScreenW; x += 1)
            {
                int h = _land[l * _LandW + ((x + offset) & (_LandW - 1))];
                Gfx.FillRect(x, h, 1, _Horizon - h, colors[l]);
                Gfx.Plot(x, h, rims[l]);
            }
        }
    }

    // a checkerboard floor in perspective that rushes towards the player, fading into the haze at the horizon
    static unsafe void _DrawFloor(double t)
    {
        uint32* pix = Gfx.Pixels();
        uint32 haze = Gfx.Rgb(255, 130, 110);
        double camX = Math.Sin(t * 0.45) * 2.5;
        double camZ = t * 5.0;
        int rows = ScreenH - _Horizon;
        for (var y = _Horizon; y < ScreenH; y += 1)
        {
            int d = y - _Horizon + 1;
            double z = (double)rows / d;
            int v = (int)(z + camZ + 1000.0);
            int fog = Math.Min(256, (int)(Math.Sqrt((double)d / rows) * 300.0));
            uint32 a = Gfx.Mix(haze, Gfx.Rgb(40, 12, 70), fog);
            uint32 b = Gfx.Mix(haze, Gfx.Rgb(170, 50, 150), fog);
            double du = z / 240.0;
            double u = camX + 1000.0 - (ScreenW / 2) * du;
            uint32* row = pix + y * ScreenW;
            for (var x = 0; x < ScreenW; x += 1)
            {
                row[x] = (((int)u + v) & 1) == 0 ? a : b;
                u += du;
            }
        }
        // a bright line along the horizon
        Gfx.BlendRect(0, _Horizon, ScreenW, 2, Gfx.Rgb(255, 220, 160), 160);
    }

    // a chain of 0s and 1s that winds across the screen
    static void _DrawChain(int index, double t)
    {
        var chain = _chains[index];
        int s = chain.Scale;
        int spacing = s * 8;
        double offset = t * chain.Speed;
        int first = (int)Math.Floor(offset / spacing);
        int count = ScreenW / spacing + 2;
        for (var j = 0; j <= count; j += 1)
        {
            int n = first + j;
            int x = (int)(n * spacing - offset);
            if (x < -spacing || x > ScreenW)
                continue;
            int bit = Gfx.Hash(n, index + 40) & 1;
            int y = chain.Y + (int)(chain.Amp * Math.Sin(x * chain.Wave + t * chain.Spin + index));
            uint32 c = Gfx.Scale(bit == 1 ? Gfx.Rgb(80, 190, 255) : Gfx.Rgb(255, 150, 50), chain.Light);
            string digit = bit == 1 ? "1" : "0";
            if (s >= 3)
                Gfx.Text(x + s / 2 + 1, y + s / 2 + 1, digit, s, Gfx.Rgb(20, 6, 40));
            Gfx.Text(x, y, digit, s, c);
        }
    }

    // one big letter of the title, block by block; `bob` makes the columns wave
    static void _BigLetter(int cp, int x, int y, int s, double t, double bob, bool shadow, ReadOnlySlice<uint32> rows, int flash)
    {
        for (var r = 0; r < 7; r += 1)
        {
            int bits = Gfx.GlyphRow(cp, r);
            if (bits == 0)
                continue;
            for (var c = 0; c < 5; c += 1)
            {
                if ((bits & (1 << (4 - c))) == 0)
                    continue;
                int px = x + c * s;
                int py = y + r * s + (int)(bob * Math.Sin(t * 2.6 + px * 0.011));
                if (shadow)
                {
                    Gfx.BlendRect(px + s / 2, py + s / 2, s, s, Gfx.Rgb(20, 0, 30), 190);
                    continue;
                }
                uint32 color = Gfx.Mix(rows[r], Gfx.Rgb(255, 255, 255), flash);
                Gfx.FillRect(px, py, s, s, color);
                // a light upper edge and a dark lower one: the blocks look chiseled, like the chrome logos of old
                Gfx.FillRect(px, py, s, Math.Max(1, s / 6), Gfx.Mix(color, Gfx.Rgb(255, 255, 255), 140));
                Gfx.FillRect(px, py + s - Math.Max(1, s / 6), s, Math.Max(1, s / 6), Gfx.Scale(color, 150));
            }
        }
    }

    // "SHIFTY BITS": the letters fly in from the right one after the other, then the title waves and flashes in time
    static void _DrawTitle(double t)
    {
        ReadOnlySlice<uint32> rows = [0xFFFAC8, 0xFFE68C, 0xFFC850, 0xFFA032, 0xFF7828, 0xE65028, 0xB43228];
        int s = 12;
        int width = _IntroTitle.Length * 6 * s - s;
        int x0 = (ScreenW - width) / 2;
        int y0 = 64;
        // a flash on every bar once the melody has begun
        int flash = 0;
        if (t >= _ScrollStart)
        {
            double inBar = (t - _ScrollStart) % _IntroBar;
            flash = Math.Max(0, (int)(150.0 * (1.0 - inBar / 0.25)));
        }
        for (var pass = 0; pass < 2; pass += 1)
        {
            for (var k = 0; k < _IntroTitle.Length; k += 1)
            {
                double p = Math.Clamp((t - 1.0 - k * 0.13) / 0.9, 0.0, 1.0);
                if (p <= 0.0)
                    continue;
                double e = 1.0 - (1.0 - p) * (1.0 - p) * (1.0 - p);
                int x = x0 + k * 6 * s + (int)((1.0 - e) * 1100.0);
                int y = y0 - (int)((1.0 - e) * 170.0 * Math.Sin(k * 1.7 + 1.0));
                _BigLetter((int)(uint8)_IntroTitle[k], x, y, s, t, 10.0 * e, pass == 0, rows, flash);
            }
        }
    }

    // "BY PYRDACOR": the letters drop from above and bounce
    static void _DrawByline(double t)
    {
        ReadOnlySlice<uint32> rows = [0xFFFFFF, 0xDCF8FF, 0xB4F0FF, 0x8CE6FF, 0x64D2FF, 0x46B4F0, 0x3296DC];
        int s = 5;
        int width = _IntroByline.Length * 6 * s - s;
        int x0 = (ScreenW - width) / 2;
        int y0 = 196;
        for (var pass = 0; pass < 2; pass += 1)
        {
            for (var k = 0; k < _IntroByline.Length; k += 1)
            {
                double p = Math.Clamp((t - 3.4 - k * 0.09) / 0.8, 0.0, 1.0);
                if (p <= 0.0)
                    continue;
                int y = y0 - (int)((1.0 - _Bounce(p)) * 260.0);
                _BigLetter((int)(uint8)_IntroByline[k], x0 + k * 6 * s, y, s, t, 0.0, pass == 0, rows, 0);
            }
        }
    }

    // an easing that falls, hits the ground and bounces twice (0 to 1)
    static double _Bounce(double p)
    {
        if (p < 0.55)
            return p * p / (0.55 * 0.55);
        if (p < 0.8)
        {
            double q = (p - 0.675) / 0.125;
            return 1.0 - 0.12 * (1.0 - q * q);
        }
        double q2 = (p - 0.9) / 0.1;
        return 1.0 - 0.03 * (1.0 - q2 * q2);
    }

    // words that fly towards the player, one per bar
    static void _DrawZoom(double t)
    {
        if (t < _ZoomStart)
            return;
        int index = (int)((t - _ZoomStart) / _IntroBar);
        if (index >= _ZoomWords.Length)
            return;
        double p = (t - _ZoomStart) / _IntroBar - index;
        int s = 1 + (int)(p * p * 44.0);
        int alpha = (int)(Math.Min(1.0, p * 6.0) * (1.0 - p) * 230.0);
        string word = _ZoomWords[index];
        int w = word.Length * 6 * s - s;
        int x0 = (ScreenW - w) / 2;
        int y0 = 340 - 7 * s / 2;
        uint32 color = index % 2 == 0 ? Gfx.Rgb(120, 220, 255) : Gfx.Rgb(255, 190, 90);
        for (var k = 0; k < word.Length; k += 1)
        {
            int cp = (int)(uint8)word[k];
            for (var r = 0; r < 7; r += 1)
            {
                int bits = Gfx.GlyphRow(cp, r);
                for (var c = 0; c < 5; c += 1)
                {
                    if ((bits & (1 << (4 - c))) != 0)
                        Gfx.BlendRect(x0 + (k * 6 + c) * s, y0 + r * s, s, s, color, alpha);
                }
            }
        }
    }

    // the text along the bottom: every column of pixels rides on a sine wave, in the colors of the rainbow
    static void _DrawScroller(double t)
    {
        if (t < _ScrollStart)
            return;
        int s = 6;
        int advance = 6 * s;
        double speed = (double)(_ScrollText.Length * advance + ScreenW) / (_IntroEnd - _ScrollStart);
        int start = ScreenW - (int)((t - _ScrollStart) * speed);
        int first = Math.Max(0, -start / advance - 1);
        for (var pass = 0; pass < 2; pass += 1)
        {
            for (var k = first; k < _ScrollText.Length; k += 1)
            {
                int x = start + k * advance;
                if (x > ScreenW)
                    break;
                int cp = (int)(uint8)_ScrollText[k];
                for (var c = 0; c < 5; c += 1)
                {
                    int px = x + c * s;
                    int py = 600 + (int)(30.0 * Math.Sin(t * 3.2 + px * 0.009));
                    uint32 color = _Rainbow(px * 0.004 - t * 0.5);
                    for (var r = 0; r < 7; r += 1)
                    {
                        if ((Gfx.GlyphRow(cp, r) & (1 << (4 - c))) == 0)
                            continue;
                        if (pass == 0)
                            Gfx.BlendRect(px + 4, py + r * s + 4, s, s, Gfx.Rgb(20, 0, 30), 170);
                        else
                            Gfx.FillRect(px, py + r * s, s, s, Gfx.Mix(color, Gfx.Rgb(255, 255, 255), 150 - r * 20));
                    }
                }
            }
        }
    }

    // a color of the rainbow; the hue goes once around for every 1.0 of `h`
    static uint32 _Rainbow(double h)
    {
        double a = h * Math.PI * 2.0;
        return Gfx.Rgb((int)(128.0 + 127.0 * Math.Sin(a)), (int)(128.0 + 127.0 * Math.Sin(a + 2.094)), (int)(128.0 + 127.0 * Math.Sin(a + 4.189)));
    }
}
