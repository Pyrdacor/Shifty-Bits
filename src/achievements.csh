//! Achievements: 30 goals, each one bit of a stored value. The game reports what happens (a clear, the state of a
//! running game, a finished intro), this file unlocks what was reached, announces it and draws the list of the menu:
//! the reached ones first and in color, the others grey.

namespace ShiftyBits;

using System;

/// The number of achievements.
const int AchievementCount = 30;

// the icons, 9 x 9 pixels each ('X' is set)
const int _IconSize = 9;
const ReadOnlySlice<string> _Icons = [
    // 0 blocks
    ".........", ".XXX.XXX.", ".X.X.X.X.", ".XXX.XXX.", ".........", ".XXX.XXX.", ".X.X.X.X.", ".XXX.XXX.", ".........",
    // 1 a 0 and a 1
    ".........", ".XXX..X..", "X...X.XX.", "X...X..X.", "X...X..X.", "X...X..X.", "X...X..X.", ".XXX..XXX", ".........",
    // 2 star
    "....X....", "....X....", "...XXX...", "XXXXXXXXX", ".XXXXXXX.", "..XXXXX..", "..XX.XX..", ".XX...XX.", ".X.....X.",
    // 3 note
    "....XX...", "....X.X..", "....X..X.", "....X....", "....X....", "..XXX....", ".XXXX....", ".XXXX....", "..XX.....",
    // 4 chain
    ".........", "XXXX.....", "X..X.....", "X..XXXX..", "XXXX..X..", "...X..X..", "...XXXX..", ".........", ".........",
    // 5 arrow up
    "....X....", "...XXX...", "..XXXXX..", ".XXXXXXX.", "...XXX...", "...XXX...", "...XXX...", "...XXX...", ".........",
    // 6 pile
    ".........", "...XXX...", "...XXX...", ".XXXXXXX.", ".XXXXXXX.", "XXXXXXXXX", "XXXXXXXXX", "XXXXXXXXX", ".........",
    // 7 clock
    "..XXXXX..", ".X..X..X.", "X...X...X", "X...X...X", "X...XXX.X", "X.......X", "X.......X", ".X.....X.", "..XXXXX..",
    // 8 grid of the modes
    "XX.XX.XX.", "XX.XX.XX.", ".........", "XX.XX.XX.", "XX.XX.XX.", ".........", "XX.XX.XX.", "XX.XX.XX.", ".........",
    // 9 hourglass
    "XXXXXXXXX", ".X.....X.", "..X...X..", "...XXX...", "....X....", "...X.X...", "..X.X.X..", ".XXXXXXX.", "XXXXXXXXX",
    // 10 lightning
    ".....XX..", "....XX...", "...XX....", "..XXXXX..", "....XX...", "...XX....", "..XX.....", ".XX......", ".........",
    // 11 a 1
    "....X....", "...XX....", "..X.X....", "....X....", "....X....", "....X....", "....X....", "..XXXXX..", ".........",
    // 12 arrows both ways
    "..X......", ".XX......", "XXXXXXXX.", ".XX......", "..X...X..", "......XX.", ".XXXXXXXX", "......XX.", "......X..",
    // 13 sword
    "........X", ".......XX", "......XX.", ".....XX..", "X...XX...", ".X.XX....", "..XX.....", ".X.X.....", "X........",
    // 14 play
    "XXXXXXXXX", "X.......X", "X.XX....X", "X.XXXX..X", "X.XXXXX.X", "X.XXXX..X", "X.XX....X", "X.......X", "XXXXXXXXX",
];

// per achievement: its icon, its color and what it asks for
const ReadOnlySlice<int> _AchIcon = [0, 0, 0, 0, 0, 1, 2, 2, 2, 2, 2, 2, 2, 3, 4, 4, 4, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 14];
const ReadOnlySlice<uint32> _AchColor = [
    0x50C8FF, 0x50C8FF, 0x50C8FF, 0x50C8FF, 0x50C8FF, 0xFF9A3C,
    0xFFD250, 0xFFD250, 0xFFD250, 0xFFD250, 0xFFD250, 0xFFD250, 0xFFD250,
    0xC88CFF, 0xFF7878, 0xFF7878, 0xFF7878, 0x78E678, 0x78E678, 0x78E678, 0xFFB45A, 0xFFB45A,
    0x96DCFF, 0xFFE68C, 0xFFAA50, 0xFFF064, 0x64C8FF, 0xFF8CC8, 0xC8C8DC, 0xAAE6FF,
];
const ReadOnlySlice<string> _AchText = [
    "CLEAR 5 BITS AT ONCE", "CLEAR 7 BITS AT ONCE", "CLEAR 9 BITS AT ONCE", "CLEAR 11 BITS AT ONCE",
    "CLEAR 15 BITS AT ONCE", "CLEAR 0S AND 1S AT ONCE",
    "SCORE 5000 POINTS", "SCORE 10000 POINTS", "SCORE 25000 POINTS", "SCORE 50000 POINTS", "SCORE 100000 POINTS",
    "SCORE 200000 POINTS", "SCORE 300000 POINTS", "1000 POINTS WITH EVERY SONG",
    "CHAIN REACTION OF 2", "CHAIN REACTION OF 3", "CHAIN REACTION OF 4",
    "REACH LEVEL 5", "REACH LEVEL 10", "REACH LEVEL 20", "CLEAR 1000 BITS IN ALL", "CLEAR 10000 BITS IN ALL",
    "SURVIVE 10 MINUTES", "1000 POINTS IN EVERY MODE", "COUNTDOWN 1 MIN: 10000 POINTS",
    "SCORE MODE: 10000 IN 3 MINUTES", "NON-ZERO MODE: 1500 POINTS", "ALTERNATE MODE: 20 SWITCHES",
    "PLAY THE SECRET SEED", "WATCH THE WHOLE INTRO",
];
// the numbers of some of them
const int _AchClearAll = 5;
const int _AchFirstScore = 6;
const int _AchSongs = 13;
const int _AchFirstChain = 14;
const int _AchFirstLevel = 17;
const int _AchFirstTotal = 20;
const int _AchSurvive = 22;
const int _AchModes = 23;
const int _AchCountdown = 24;
const int _AchSprint = 25;
const int _AchNonZero = 26;
const int _AchAlternate = 27;
/// The secret one: its text stays hidden until it is reached.
const int AchSecret = 28;
/// Watching the intro to its end.
const int AchIntro = 29;

const ReadOnlySlice<int> _ClearSizes = [5, 7, 9, 11, 15];
const ReadOnlySlice<int> _ScoreGoals = [5000, 10000, 25000, 50000, 100000, 200000, 300000];
const ReadOnlySlice<int> _ChainGoals = [2, 3, 4];
const ReadOnlySlice<int> _LevelGoals = [5, 10, 20];
const ReadOnlySlice<int> _TotalGoals = [1000, 10000];

// the reached achievements, one bit each
int _achieved;
// bits 0-3: the songs played to 1000 points, bits 4-8: the modes
int _achProgress;
// the tiles cleared in all games
int _totalTiles;
bool _achLoaded;
// the right switches of the current game in the alternate mode
int _altSwitches;
// newly reached achievements, announced one after the other
List<int> _achNews = List<int>.Create();
double _achNewsTime = -10.0;
// true while the list is shown
bool _showAwards;

/// Unlocking, announcing and showing achievements.
struct Achievements
{
    /// Reads what was reached before (once).
    static void Load()
    {
        if (_achLoaded)
            return;
        _achLoaded = true;
        _achieved = Platform.LoadBest(AchievementSlot);
        _achProgress = Platform.LoadBest(AchievementProgressSlot);
        _totalTiles = Platform.LoadBest(TotalTilesSlot);
    }

    /// Whether achievement `index` was reached.
    static bool Has(int index)
    {
        return (_achieved & (1 << index)) != 0;
    }

    /// The number of reached achievements.
    static int Count()
    {
        int n = 0;
        for (var i = 0; i < AchievementCount; i += 1)
        {
            if (Has(i))
                n += 1;
        }
        return n;
    }

    /// Reaches achievement `index`: it is kept and announced.
    static void Unlock(int index)
    {
        if (Has(index))
            return;
        _achieved |= 1 << index;
        Platform.SaveBest(AchievementSlot, _achieved);
        _achNews.Add(index);
        Music.Play(Sfx.Achievement, 0);
    }

    /// A new game starts.
    static void GameStarted()
    {
        _altSwitches = 0;
        if (Game.SwordAndShield())
            Unlock(AchSecret);
    }

    /// Tiles were cleared: `tiles` in one step, of zeros and/or ones, as step `chain` of a chain reaction.
    static void Cleared(int tiles, bool zeros, bool ones, int chain)
    {
        for (var i = 0; i < _ClearSizes.Length; i += 1)
        {
            if (tiles >= _ClearSizes[i])
                Unlock(i);
        }
        if (zeros && ones)
            Unlock(_AchClearAll);
        for (var i = 0; i < _ChainGoals.Length; i += 1)
        {
            if (chain >= _ChainGoals[i])
                Unlock(_AchFirstChain + i);
        }
        _totalTiles += tiles;
        for (var i = 0; i < _TotalGoals.Length; i += 1)
        {
            if (_totalTiles >= _TotalGoals[i])
                Unlock(_AchFirstTotal + i);
        }
    }

    /// A right switch in the alternate mode.
    static void Switched()
    {
        _altSwitches += 1;
        if (_altSwitches >= 20)
            Unlock(_AchAlternate);
    }

    /// Checks what the running game has reached: points, level, time and the goals of the modes.
    static void CheckGame()
    {
        for (var i = 0; i < _ScoreGoals.Length; i += 1)
        {
            if (_score >= _ScoreGoals[i])
                Unlock(_AchFirstScore + i);
        }
        for (var i = 0; i < _LevelGoals.Length; i += 1)
        {
            if (_level >= _LevelGoals[i])
                Unlock(_AchFirstLevel + i);
        }
        if (_playTime >= 600.0)
            Unlock(_AchSurvive);
        if (_score >= 1000)
        {
            int progress = _achProgress | (1 << (4 + (int)_mode));
            if (Music.IsOn())
                progress |= 1 << Music.SongIndex();
            if (progress != _achProgress)
            {
                _achProgress = progress;
                Platform.SaveBest(AchievementProgressSlot, _achProgress);
            }
            if ((_achProgress & 15) == 15)
                Unlock(_AchSongs);
            if (((_achProgress >> 4) & 31) == 31)
                Unlock(_AchModes);
        }
        if (_mode == Mode.Countdown && _countdownChoice == 0 && _score >= 10000)
            Unlock(_AchCountdown);
        if (_mode == Mode.Score && _score >= 10000 && _playTime < 180.0)
            Unlock(_AchSprint);
        if (_mode == Mode.NonZero && _score >= 1500)
            Unlock(_AchNonZero);
    }

    /// Keeps the count of all cleared tiles (at the end of a game: it changes too often to write it every time).
    static void Save()
    {
        if (_achLoaded)
            Platform.SaveBest(TotalTilesSlot, _totalTiles);
    }

    /// Announces the next new achievement once the one before has been shown for a while.
    static void Update()
    {
        if (_achNews.Count() == 0 || _time - _achNewsTime < 2.5)
            return;
        int index = _achNews[0];
        Render.Announce(_AchIcon[index], _AchColor[index], _AchText[index]);
        _achNews.RemoveAt(0);
        _achNewsTime = _time;
    }

    /// Draws an icon at (`x`, `y`) with pixels of `scale`.
    static void DrawIcon(int icon, int x, int y, int scale, uint32 color)
    {
        for (var r = 0; r < _IconSize; r += 1)
        {
            var row = _Icons[icon * _IconSize + r];
            for (var c = 0; c < _IconSize; c += 1)
            {
                if (row[c] == 'X')
                    Gfx.FillRect(x + c * scale, y + r * scale, scale, scale, color);
            }
        }
    }

    /// The list of the menu: two columns, the reached achievements first.
    static void Draw()
    {
        int w = 900;
        int h = 684;
        int x = (ScreenW - w) / 2;
        int y = (ScreenH - h) / 2;
        Gfx.BlendRect(0, 0, ScreenW, ScreenH, Gfx.Rgb(0, 0, 0), 160);
        Gfx.BlendRect(x, y, w, h, Gfx.Rgb(14, 12, 30), 252);
        Gfx.FrameRect(x, y, w, h, 2, Gfx.Rgb(200, 160, 70));
        Gfx.TextCentered(ScreenW / 2, y + 18, "ACHIEVEMENTS", 4, Gfx.Rgb(255, 205, 90));
        string count = Count().ToString() + " / " + AchievementCount.ToString();
        Gfx.TextCentered(ScreenW / 2, y + 54, count, 2, Gfx.Rgb(170, 160, 200));

        // the reached ones first, each group in its own order
        var order = List<int>.Create();
        for (var pass = 0; pass < 2; pass += 1)
        {
            for (var i = 0; i < AchievementCount; i += 1)
            {
                if (Has(i) == (pass == 0))
                    order.Add(i);
            }
        }
        int rows = (AchievementCount + 1) / 2;
        for (var k = 0; k < order.Count(); k += 1)
        {
            int i = order[k];
            int cx = x + 24 + (k / rows) * (w / 2);
            int cy = y + 84 + (k % rows) * 37;
            bool reached = Has(i);
            uint32 color = reached ? _AchColor[i] : Gfx.Rgb(70, 66, 90);
            if (reached)
                Gfx.Glow(cx + 13, cy + 13, 18, color, 60);
            DrawIcon(_AchIcon[i], cx, cy, 3, color);
            string text = !reached && i == AchSecret ? "???" : _AchText[i];
            Gfx.TextShadow(cx + 40, cy + 7, text, 2, reached ? Gfx.Rgb(240, 235, 250) : Gfx.Rgb(105, 100, 125));
        }
        Gfx.TextCentered(ScreenW / 2, y + h - 30, "PRESS ANY KEY OR CLICK", 2, Gfx.Rgb(170, 230, 255));
    }
}
