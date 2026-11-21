//! The game logic: falling rectangular blocks full of bits, rolling, locking, matching runs of four and cascades,
//! and the game modes with their clocks, goals and best values.

namespace ShiftyBits;

using System;

/// Board width in cells.
const int BoardW = 10;
/// Board height in cells (the visible field).
const int BoardH = 18;
/// Rows above the field where blocks appear.
const int SpawnRows = 4;

const int _Empty = -1;
// a run needs at least this many equal bits
const int _RunLength = 4;
const double _ClearTime = 0.35;
const double _FallSpeed = 14.0;   // cells per second while the board settles
const double _RollTime = 0.12;
const int _TilesPerLevel = 30;
// seconds per row at level 1 and at the level from which it gets no faster
const double _SlowestFall = 0.75;
const double _FastestFall = 0.07;
const int _FastestLevel = 20;
// the largest block (in tiles) per level; from the last entry on, everything up to 4x4
const ReadOnlySlice<int> _MaxAreaByLevel = [3, 4, 6, 8, 8, 12, 12, 16];

/// The durations of the countdown mode, in minutes.
const ReadOnlySlice<int> CountdownMinutes = [1, 3, 5, 10];
/// The target scores of the score mode.
const ReadOnlySlice<int> ScoreTargets = [1000, 10000, 50000, 100000];
/// The number of game modes.
const int ModeCount = 5;
/// Where the settings are kept, after the best values of the first modes: bit 0 set means music off, bit 1 sound
/// effects off, bits 2 to 4 are the number of the song.
const int SettingsSlot = 10;
/// Where the reached achievements are kept, one bit each.
const int AchievementSlot = 12;
/// Where the progress of the achievements for all songs and all modes is kept.
const int AchievementProgressSlot = 13;
/// Where the number of tiles cleared in all games is kept.
const int TotalTilesSlot = 14;
/// The number of values the platform stores: the best value of every mode and option (see `Game.BestSlot`), the
/// settings and the achievements.
const int StoredSlots = 15;
/// The largest seed (9 digits).
const int MaxSeed = 999999999;
/// The seed of the easter egg: "PYRDACOR" typed on the keys of a phone (P 7, Y 9, R 7, D 3, A 2, C 2, O 6, R 7).
/// Its tiles show swords and shields instead of 1s and 0s.
const int PyrdacorSeed = 79732267;

/// The rules of a game.
enum Mode : uint8
{
    /// Play until the well is full.
    Normal,
    /// The most points within a fixed time.
    Countdown,
    /// A target score in the shortest time.
    Score,
    /// Like `Normal`, but a run of zeros ends the game.
    NonZero,
    /// Like `Normal`, but 1s and 0s must be cleared in turn: clearing the same bit twice ends the game.
    Alternate,
}

/// Why a game ended.
enum End : uint8
{
    ToppedOut,
    TimeUp,
    TargetReached,
    Zeros,
    /// The same bit cleared twice in a row in the alternate mode.
    WrongBit,
}

/// What the game is doing at the moment.
enum State : uint8
{
    /// The intro (intro.csh).
    Intro,
    Menu,
    Playing,
    Clearing,
    Settling,
    GameOver,
}

/// A falling rectangular block. Bits are stored row by row, 0 or 1.
struct Piece
{
    int W;
    int H;
    int[] Bits;
    /// Column of the left edge.
    int X;
    /// Row of the top edge (negative while above the field).
    int Y;

    /// The bit at row `r`, column `c`.
    int Bit(int r, int c)
    {
        return Bits[r * W + c];
    }

    /// A copy with every row rolled one place; `dir` -1 rolls left, +1 rolls right.
    Piece Rolled(int dir)
    {
        var bits = new int[W * H];
        for (var r = 0; r < H; r += 1)
        {
            for (var c = 0; c < W; c += 1)
            {
                int from = (c - dir + W) % W;
                bits[r * W + c] = Bits[r * W + from];
            }
        }
        return Piece { W = W, H = H, Bits = bits, X = X, Y = Y };
    }

    /// A copy with every column rolled one place; `dir` -1 rolls up, +1 rolls down.
    Piece RolledVertical(int dir)
    {
        var bits = new int[W * H];
        for (var r = 0; r < H; r += 1)
        {
            int from = (r - dir + H) % H;
            for (var c = 0; c < W; c += 1)
            {
                bits[r * W + c] = Bits[from * W + c];
            }
        }
        return Piece { W = W, H = H, Bits = bits, X = X, Y = Y };
    }
}

/// A floating score text.
struct Popup
{
    double X;
    double Y;
    string Text;
    double Life;
    uint32 Color;
}

/// A spark from a cleared tile.
struct Particle
{
    double X;
    double Y;
    double VX;
    double VY;
    double Life;
    uint32 Color;
}

State _state = State.Menu;
Mode _mode = Mode.Normal;
End _end = End.ToppedOut;
// index into CountdownMinutes or ScoreTargets
int _countdownChoice = 1;
int _scoreChoice = 1;
// every block is derived from the seed and its number, so a seed always gives the same blocks
int _seed = 1;
// true if the player entered the seed; a random one is replaced with every new game
bool _seedFixed;
int _pieceCount;
// true from the moment the block became part of the board until the next one appears
bool _pieceLanded;
// seconds played (not counting pauses)
double _playTime;
bool _newBest;
// the alternate mode: the bit that must be cleared next, -1 while either may be (at the start)
int _nextBit = -1;
int[] _cells = [];
bool[] _clearing = [];
double[] _fall = [];       // visual offset in cells, counts down to 0 while settling
Piece _piece;
Piece _next;
double _gravityTimer;
double _stateTimer;
int _score;
// the best score of the mode; in the score mode the best time in milliseconds (0: none yet)
int _best;
int _level = 1;
int _tilesCleared;
int _chain;
int _bestChain;
double _time;
bool _paused;
bool _showHelp;

// roll animation of the falling block
int[] _rollOld = [];
int _rollDir;
bool _rollVertical;
double _rollT = 1.0;

// only for effects and random seeds: the blocks must not depend on it
Random _rng = Random.Create();
List<Popup> _popups = List<Popup>.Create();
List<Particle> _particles = List<Particle>.Create();

/// Game rules and state changes.
struct Game
{
    /// Starts a game in the current mode: with the same seed if the player entered it, else with a new random one.
    static void Restart()
    {
        if (!_seedFixed)
            _seed = RandomSeed();
        NewGame();
    }

    /// Whether the easter egg is on: the seed is `PyrdacorSeed`.
    static bool SwordAndShield()
    {
        return _seed == PyrdacorSeed;
    }

    /// A random seed.
    static int RandomSeed()
    {
        return _rng.Next(1, MaxSeed + 1);
    }

    /// Where the best value of a mode with the given option is kept.
    static int BestSlot(Mode mode, int choice)
    {
        switch (mode)
        {
            case Mode.Normal:
                return 0;
            case Mode.Countdown:
                return 1 + choice;
            case Mode.Score:
                return 5 + choice;
            case Mode.NonZero:
                return 9;
            case Mode.Alternate:
                // the settings were kept in slot 10 before this mode existed
                return 11;
        }
        return 0;
    }

    /// The option of `mode` chosen in the menu (0 for modes without options).
    static int Choice(Mode mode)
    {
        if (mode == Mode.Countdown)
            return _countdownChoice;
        if (mode == Mode.Score)
            return _scoreChoice;
        return 0;
    }

    /// The name of the current mode with its option.
    static string ModeText()
    {
        switch (_mode)
        {
            case Mode.Normal:
                return "NORMAL MODE";
            case Mode.Countdown:
                return "COUNTDOWN " + CountdownMinutes[_countdownChoice].ToString() + " MIN";
            case Mode.Score:
                return "SCORE MODE " + ScoreTargets[_scoreChoice].ToString();
            case Mode.NonZero:
                return "NON-ZERO MODE";
            case Mode.Alternate:
                return "ALTERNATE MODE";
        }
        return "";
    }

    /// The score to reach in the score mode.
    static int Target()
    {
        return ScoreTargets[_scoreChoice];
    }

    /// The clock of the game in seconds: the time left in the countdown mode, else the time played.
    static double Clock()
    {
        if (_mode == Mode.Countdown)
            return Math.Max(0.0, CountdownMinutes[_countdownChoice] * 60.0 - _playTime);
        return _playTime;
    }

    /// `seconds` as `m:ss`, or as `m:ss.cc` with `hundredths`.
    static string TimeText(double seconds, bool hundredths)
    {
        int cs = (int)(seconds * 100.0);
        string text = (cs / 6000).ToString() + ":" + (cs / 100 % 60).ToString().PadLeft(2, '0');
        if (hundredths)
            text += "." + (cs % 100).ToString().PadLeft(2, '0');
        return text;
    }

    /// Starts a new game in the current mode with the current seed.
    static void NewGame()
    {
        _cells = new int[BoardW * BoardH];
        _clearing = new bool[BoardW * BoardH];
        _fall = new double[BoardW * BoardH];
        for (var i = 0; i < _cells.Length; i += 1)
        {
            _cells[i] = _Empty;
        }
        _score = 0;
        _level = 1;
        _tilesCleared = 0;
        _chain = 0;
        _bestChain = 0;
        _paused = false;
        _pieceCount = 0;
        _playTime = 0.0;
        _newBest = false;
        _nextBit = -1;
        _popups = List<Popup>.Create();
        _particles = List<Particle>.Create();
        _best = Platform.LoadBest(BestSlot(_mode, Choice(_mode)));
        Music.SetLevel(1);
        Music.Start();
        _next = _RandomPiece();
        _Spawn();
        Achievements.GameStarted();
    }

    /// The cell value at (`x`, `y`): -1 empty, else the bit.
    static int Cell(int x, int y)
    {
        return _cells[y * BoardW + x];
    }

    /// Seconds per row of falling at the current level.
    static double GravityInterval()
    {
        // an even speed-up by the same factor per level, from the slowest to the fastest
        double t = Math.Min(1.0, (_level - 1) / (double)(_FastestLevel - 1));
        return _SlowestFall * Math.Pow(_FastestFall / _SlowestFall, t);
    }

    /// Whether `p` fits at its position.
    static bool Fits(Piece p)
    {
        for (var r = 0; r < p.H; r += 1)
        {
            for (var c = 0; c < p.W; c += 1)
            {
                int x = p.X + c;
                int y = p.Y + r;
                if (x < 0 || x >= BoardW || y >= BoardH)
                    return false;
                if (y >= 0 && _cells[y * BoardW + x] != _Empty)
                    return false;
            }
        }
        return true;
    }

    /// The row the falling block would land on.
    static int DropRow()
    {
        var p = _piece;
        p.Y += 1;
        while (Fits(p))
        {
            p.Y += 1;
        }
        return p.Y - 1;
    }

    /// Moves the block sideways if possible.
    static void Move(int dx)
    {
        if (_CanControl())
            _TryMove(dx, 0);
    }

    /// Rolls all rows of the block left (-1) or right (+1); the bits never leave the block.
    static void Roll(int dir)
    {
        if (_CanControl() && _piece.W >= 2)
            _StartRoll(_piece.Rolled(dir), dir, false);
    }

    /// Rolls all columns of the block up (-1) or down (+1); the bits never leave the block.
    static void RollVertical(int dir)
    {
        if (_CanControl() && _piece.H >= 2)
            _StartRoll(_piece.RolledVertical(dir), dir, true);
    }

    /// Moves the block one row down (soft drop).
    static void SoftDrop()
    {
        if (!_CanControl())
            return;
        if (_TryMove(0, 1))
            _score += 1;
        _gravityTimer = 0.0;
    }

    /// Drops the block to the bottom and locks it.
    static void HardDrop()
    {
        if (!_CanControl())
            return;
        int rows = DropRow() - _piece.Y;
        _piece.Y += rows;
        _score += rows * 2;
        _Lock();
    }

    /// Advances the game by `dt` seconds.
    static void Update(double dt)
    {
        _time += dt;
        _UpdateEffects(dt);
        Achievements.Update();
        if (_state == State.Intro)
        {
            Intro.Update(dt);
            return;
        }
        if (_paused || _showHelp || _state == State.Menu || _state == State.GameOver)
            return;
        _playTime += dt;
        if (_rollT < 1.0)
            _rollT = Math.Min(1.0, _rollT + dt / _RollTime);

        switch (_state)
        {
            case State.Playing:
                // a cascade that is still running when the time is up counts: the game ends once the board is calm
                if (_mode == Mode.Countdown && Clock() <= 0.0)
                {
                    _Finish(End.TimeUp);
                    break;
                }
                _gravityTimer += dt;
                if (_gravityTimer >= GravityInterval())
                {
                    _gravityTimer = 0.0;
                    if (!_TryMove(0, 1))
                        _Lock();
                }
                break;
            case State.Clearing:
                _stateTimer += dt;
                if (_stateTimer >= _ClearTime)
                    _RemoveCleared();
                break;
            case State.Settling:
                bool moving = false;
                for (var i = 0; i < _fall.Length; i += 1)
                {
                    if (_fall[i] > 0.0)
                    {
                        _fall[i] = Math.Max(0.0, _fall[i] - dt * _FallSpeed);
                        moving = true;
                    }
                }
                if (!moving)
                {
                    if (!_FindRuns())
                        _Spawn();
                }
                break;
            default:
                break;
        }
        if (_state == State.GameOver)
            return;
        if (_mode == Mode.Score)
        {
            if (_score >= Target())
                _Finish(End.TargetReached);
        }
        else
        {
            _best = Math.Max(_best, _score);
        }
        if (_state != State.GameOver)
            Achievements.CheckGame();
    }

    static bool _CanControl()
    {
        return _state == State.Playing && !_paused && !_showHelp;
    }

    // moves the block if it fits there
    static bool _TryMove(int dx, int dy)
    {
        var p = _piece;
        p.X += dx;
        p.Y += dy;
        if (!Fits(p))
            return false;
        _piece = p;
        return true;
    }

    // replaces the block by its rolled version and starts the slide animation
    static void _StartRoll(Piece rolled, int dir, bool vertical)
    {
        _rollOld = _piece.Bits;
        _rollDir = dir;
        _rollVertical = vertical;
        _rollT = 0.0;
        _piece = rolled;
        Music.Play(Sfx.Roll, 0);
    }

    // the next block: it depends only on the seed, its number and the level
    static Piece _RandomPiece()
    {
        // a generator of its own per block, so that the size of earlier blocks does not shift the sequence
        uint64 h = unchecked(((uint64)_seed + 1ul) * 0x9E3779B97F4A7C15ul + (uint64)_pieceCount * 0xBF58476D1CE4E5B9ul);
        h = unchecked((h ^ (h >> 30)) * 0x94D049BB133111EBul);
        h ^= h >> 31;
        var rng = Random.Create((int64)(h >> 1) + 1);
        _pieceCount += 1;
        // larger blocks join the mix as the level rises
        int maxArea = _MaxAreaByLevel[Math.Min(_level, _MaxAreaByLevel.Length) - 1];
        // every possible size, encoded as width * 10 + height
        var sizes = List<int>.Create();
        for (var w = 1; w <= 4; w += 1)
        {
            for (var h = 1; h <= 4; h += 1)
            {
                int area = w * h;
                if (area >= 2 && area <= maxArea)
                {
                    // small blocks stay more common than big ones
                    int weight = area <= 4 ? 3 : area <= 8 ? 2 : 1;
                    for (var k = 0; k < weight; k += 1)
                    {
                        sizes.Add(w * 10 + h);
                    }
                }
            }
        }
        int pick = sizes[rng.Next(0, sizes.Count())];
        int pw = pick / 10;
        int ph = pick % 10;
        var bits = new int[pw * ph];
        for (var i = 0; i < bits.Length; i += 1)
        {
            // in the non-zero mode a few more 1s; the other modes keep the blocks of their seeds as they were
            bits[i] = _mode == Mode.NonZero ? (rng.Next(0, 100) < 55 ? 1 : 0) : rng.Next(0, 2);
        }
        if (_mode == Mode.NonZero)
            _BreakZeroRuns(bits, pw, ph, rng);
        return Piece { W = pw, H = ph, Bits = bits };
    }

    // In the non-zero mode a block must not hold 4 zeros in a row: rolling only moves the bits along their row or
    // column, so such a block would end the game wherever it lands. One zero of such a row or column becomes a 1.
    static void _BreakZeroRuns(int[] bits, int w, int h, Random rng)
    {
        if (w >= _RunLength)
        {
            for (var r = 0; r < h; r += 1)
            {
                bool zeros = true;
                for (var c = 0; c < w; c += 1)
                {
                    zeros = zeros && bits[r * w + c] == 0;
                }
                if (zeros)
                    bits[r * w + rng.Next(0, w)] = 1;
            }
        }
        if (h >= _RunLength)
        {
            for (var c = 0; c < w; c += 1)
            {
                bool zeros = true;
                for (var r = 0; r < h; r += 1)
                {
                    zeros = zeros && bits[r * w + c] == 0;
                }
                if (zeros)
                    bits[rng.Next(0, h) * w + c] = 1;
            }
        }
    }

    static void _Spawn()
    {
        _piece = _next;
        _piece.X = (BoardW - _piece.W) / 2;
        _piece.Y = -_piece.H;
        _next = _RandomPiece();
        _gravityTimer = 0.0;
        _rollT = 1.0;
        _pieceLanded = false;
        _state = State.Playing;
    }

    static void _Lock()
    {
        bool outside = false;
        for (var r = 0; r < _piece.H; r += 1)
        {
            for (var c = 0; c < _piece.W; c += 1)
            {
                int y = _piece.Y + r;
                if (y < 0)
                    outside = true;
                else
                    _cells[y * BoardW + _piece.X + c] = _piece.Bit(r, c);
            }
        }
        _rollT = 1.0;
        if (outside)
        {
            _Finish(End.ToppedOut);
            return;
        }
        _pieceLanded = true;
        Music.Play(Sfx.Lock, 0);
        _chain = 0;
        if (!_FindRuns())
            _Spawn();
    }

    // marks all runs of 4+ equal bits; scores them and starts the clear animation
    static bool _FindRuns()
    {
        int runs = 0;
        int points = 0;
        bool zeros = false;
        bool ones = false;
        int sumX = 0;
        int sumY = 0;
        int marked = 0;
        for (var i = 0; i < _clearing.Length; i += 1)
        {
            _clearing[i] = false;
        }
        // horizontal
        for (var y = 0; y < BoardH; y += 1)
        {
            int x = 0;
            while (x < BoardW)
            {
                int v = Cell(x, y);
                int end = x + 1;
                while (end < BoardW && v != _Empty && Cell(end, y) == v)
                {
                    end += 1;
                }
                int len = end - x;
                if (v != _Empty && len >= _RunLength)
                {
                    zeros = zeros || v == 0;
                    ones = ones || v == 1;
                    runs += 1;
                    points += _RunPoints(len);
                    for (var k = x; k < end; k += 1)
                    {
                        _clearing[y * BoardW + k] = true;
                    }
                }
                x = end;
            }
        }
        // vertical
        for (var x = 0; x < BoardW; x += 1)
        {
            int y = 0;
            while (y < BoardH)
            {
                int v = Cell(x, y);
                int end = y + 1;
                while (end < BoardH && v != _Empty && Cell(x, end) == v)
                {
                    end += 1;
                }
                int len = end - y;
                if (v != _Empty && len >= _RunLength)
                {
                    zeros = zeros || v == 0;
                    ones = ones || v == 1;
                    runs += 1;
                    points += _RunPoints(len);
                    for (var k = y; k < end; k += 1)
                    {
                        _clearing[k * BoardW + x] = true;
                    }
                }
                y = end;
            }
        }
        if (runs == 0)
            return false;
        if (zeros && _mode == Mode.NonZero)
        {
            // only the zeros that ended the game stay marked
            for (var i = 0; i < _clearing.Length; i += 1)
            {
                _clearing[i] = _clearing[i] && _cells[i] == 0;
            }
            _Finish(End.Zeros);
            return true;
        }
        if (_mode == Mode.Alternate && zeros != ones)
        {
            // runs of one kind only: they must be the bit whose turn it is, then the other one comes next; runs of
            // both kinds at once are always allowed and leave the turn as it is
            int bit = ones ? 1 : 0;
            if (_nextBit >= 0 && bit != _nextBit)
            {
                // the runs that ended the game stay marked
                _Finish(End.WrongBit);
                return true;
            }
            _nextBit = 1 - bit;
            Achievements.Switched();
        }

        for (var i = 0; i < _clearing.Length; i += 1)
        {
            if (_clearing[i])
            {
                marked += 1;
                sumX += i % BoardW;
                sumY += i / BoardW;
            }
        }
        _chain += 1;
        _bestChain = Math.Max(_bestChain, _chain);
        Achievements.Cleared(marked, zeros, ones, _chain);
        // several runs at once and chain reactions multiply
        int total = points * runs * _chain * _level;
        _score += total;

        string text = "+" + total.ToString();
        if (runs > 1)
            text += " ×" + runs.ToString();
        if (_chain > 1)
            text += " CHAIN " + _chain.ToString();
        _popups.Add(Popup
        {
            X = (double)sumX / marked + 0.5, Y = (double)sumY / marked,
            Text = text, Life = 1.6,
            Color = runs > 1 || _chain > 1 ? Gfx.Rgb(255, 215, 100) : Gfx.Rgb(235, 235, 255),
        });

        Music.Play(Sfx.Clear, _chain + runs - 1);
        _state = State.Clearing;
        _stateTimer = 0.0;
        return true;
    }

    static int _RunPoints(int len)
    {
        // longer runs are worth more than their length
        return len * 10 + (len - _RunLength) * 25;
    }

    static void _RemoveCleared()
    {
        int removed = 0;
        for (var i = 0; i < _cells.Length; i += 1)
        {
            if (_clearing[i])
            {
                _Sparks(i % BoardW, i / BoardW, _cells[i]);
                _cells[i] = _Empty;
                _clearing[i] = false;
                removed += 1;
            }
        }
        _tilesCleared += removed;
        int level = 1 + _tilesCleared / _TilesPerLevel;
        if (level > _level)
        {
            Music.Play(Sfx.LevelUp, 0);
            Music.SetLevel(level);
        }
        _level = level;

        // tiles above the gaps fall down, column by column
        for (var x = 0; x < BoardW; x += 1)
        {
            int write = BoardH - 1;
            for (var y = BoardH - 1; y >= 0; y -= 1)
            {
                int v = Cell(x, y);
                if (v == _Empty)
                    continue;
                if (write != y)
                {
                    _cells[write * BoardW + x] = v;
                    _cells[y * BoardW + x] = _Empty;
                    _fall[write * BoardW + x] = write - y;
                }
                write -= 1;
            }
        }
        _state = State.Settling;
    }

    // ends the game and keeps a new best value
    static void _Finish(End end)
    {
        Achievements.CheckGame();
        Achievements.Save();
        _state = State.GameOver;
        _end = end;
        Music.Stop();
        Music.Play(end == End.TimeUp || end == End.TargetReached ? Sfx.LevelUp : Sfx.GameOver, 0);
        if (_mode == Mode.Score)
        {
            // only a reached target counts, and the shorter time wins
            int ms = (int)(_playTime * 1000.0);
            if (end != End.TargetReached || (_best > 0 && ms >= _best))
                return;
            _best = ms;
        }
        else
        {
            if (_score == 0 || _score < _best)
                return;
            _best = _score;
        }
        _newBest = true;
        Platform.SaveBest(BestSlot(_mode, Choice(_mode)), _best);
    }

    static void _Sparks(int cx, int cy, int bit)
    {
        uint32 color = Gfx.Mix(Render.TileGlow(bit), Gfx.Rgb(255, 255, 255), 90);
        for (var i = 0; i < 10; i += 1)
        {
            double angle = _rng.NextDouble() * Math.PI * 2.0;
            double speed = 1.5 + _rng.NextDouble() * 5.0;
            _particles.Add(Particle
            {
                X = cx + 0.5, Y = cy + 0.5,
                VX = Math.Cos(angle) * speed, VY = Math.Sin(angle) * speed - 3.0,
                Life = 0.5 + _rng.NextDouble() * 0.6, Color = color,
            });
        }
    }

    static void _UpdateEffects(double dt)
    {
        var alive = List<Particle>.Create();
        foreach (var p in _particles)
        {
            var q = p;
            q.X += q.VX * dt;
            q.Y += q.VY * dt;
            q.VY += 12.0 * dt;
            q.Life -= dt;
            if (q.Life > 0.0)
                alive.Add(q);
        }
        _particles = alive;

        var popups = List<Popup>.Create();
        foreach (var p in _popups)
        {
            var q = p;
            q.Y -= dt * 1.2;
            q.Life -= dt;
            if (q.Life > 0.0)
                popups.Add(q);
        }
        _popups = popups;
    }
}
