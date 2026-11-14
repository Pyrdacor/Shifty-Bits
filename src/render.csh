//! Drawing: night sky, the stone well, bit tiles, the falling block with its ghost, panels and overlays.
//! Everything that does not change (sky, well, panel frames, labels, the tiles themselves) is drawn once in `Init`;
//! a frame copies those pixels and only draws what moves.

namespace ShiftyBits;

using System;

/// Size of one cell in pixels.
const int CellSize = 30;
/// Left edge of the field.
const int FieldX = (ScreenW - BoardW * CellSize) / 2;
/// Top edge of the visible field (row 0); the spawn rows are above it.
const int FieldY = 160;

const int _WallW = 14;
const int _PanelLeftX = 40;
const int _PanelRightX = FieldX + BoardW * CellSize + _WallW + 30;
const int _PanelRightW = ScreenW - 40 - _PanelRightX;
const int _TileVariants = 4;
const double _ToastSeconds = 4.0;

// the key list of the side panel and of the help screen: key, then what it does
const ReadOnlySlice<string> _PanelKeys = [
    "← →", "MOVE", "A D", "ROLL ←→", "W S", "ROLL ↑↓", "↓", "FASTER", "SPACE", "DROP",
    "P", "PAUSE", "H", "HELP", "R", "RESTART", "F11", "FULLSCREEN", "M", "MUSIC", "ESC", "MENU",
];
const ReadOnlySlice<string> _HelpKeys = [
    "← →", "MOVE THE BLOCK",
    "A / D  (Z / X)", "ROLL ALL ROWS LEFT / RIGHT",
    "W / S  (↑)", "ROLL ALL COLUMNS UP / DOWN",
    "↓  /  SPACE", "FASTER  /  DROP",
    "P  R  ESC", "PAUSE  RESTART  MENU",
    "F11 / ALT+ENTER", "FULLSCREEN ON / OFF",
    "S  (GAME OVER)", "SAVE A SCREENSHOT OF YOUR SCORE",
    "M", "MUSIC ON / OFF",
    "CTRL+C", "COPY THE SEED OF THE GAME",
];
const ReadOnlySlice<string> _HelpRules = [
    "RECTANGULAR BLOCKS FULL OF BITS FALL DOWN.",
    "4 EQUAL BITS IN A ROW (HORIZONTAL OR VERTICAL)",
    "DISSOLVE. LONGER RUNS, SEVERAL RUNS AT ONCE AND",
    "CHAIN REACTIONS GIVE BONUS POINTS.",
    "A BLOCK THAT LANDS ABOVE THE RED LINE ENDS THE GAME.",
];

const ReadOnlySlice<string> _ModeNames = ["NORMAL MODE", "COUNTDOWN MODE", "SCORE MODE", "NON-ZERO MODE"];
const ReadOnlySlice<string> _ModeRules = [
    "PLAY UNTIL THE WELL IS FULL",
    "THE MOST POINTS BEFORE THE TIME RUNS OUT",
    "REACH THE TARGET SCORE IN THE SHORTEST TIME",
    "ONLY 1S SCORE: 4 ZEROS IN A ROW END THE GAME",
];

/// How a tile is drawn.
enum TileLook : uint8
{
    Resting,
    Falling,
    FlashWhite,
    FlashColor,
}

uint32[] _sky = [];
uint32* _background;        // sky, well, panel frames and the key list
uint32* _menuBackground;    // only the sky
uint32* _tileSprites;       // [bit][falling][variant], CellSize x CellSize each

bool _capturing;            // true while a screenshot frame is rendered (hides prompts)
string _toast = "";
double _toastTime;

/// Draws a complete frame.
struct Render
{
    /// Draws everything that never changes.
    static void Init()
    {
        _sky = new uint32[ScreenW * ScreenH];
        for (var y = 0; y < ScreenH; y += 1)
        {
            uint32 row = Gfx.Mix(Gfx.Rgb(8, 10, 28), Gfx.Rgb(40, 28, 60), y * 256 / ScreenH);
            for (var x = 0; x < ScreenW; x += 1)
            {
                int n = Gfx.Noise(x, y * 2, 90) + Gfx.Noise(x + 500, y * 2, 37) / 2;
                _sky[y * ScreenW + x] = Gfx.Mix(row, Gfx.Rgb(70, 60, 110), Math.Max(0, n - 230) / 3);
            }
        }
        // distant hills
        for (var x = 0; x < ScreenW; x += 1)
        {
            int h = ScreenH - 140 - Gfx.Noise(x, 0, 160) / 3 - Gfx.Noise(x, 7, 40) / 10;
            for (var y = Math.Max(0, h); y < ScreenH; y += 1)
            {
                _sky[y * ScreenW + x] = Gfx.Mix(Gfx.Rgb(30, 24, 44), Gfx.Rgb(14, 12, 22), Math.Min(256, (y - h) * 3));
            }
        }
        _BakeTiles();
        _BakeBackground();
    }

    /// Shows a short message at the bottom of the screen.
    static void Toast(string text)
    {
        _toast = text;
        _toastTime = _time;
    }

    /// Draws everything.
    static void Frame()
    {
        _DrawBackground();
        if (_state == State.Menu)
            _DrawMenu();
        else
            _DrawGame();
        if (_showHelp)
            _DrawHelp();
        if (!_capturing && _toast.Length > 0 && _time - _toastTime < _ToastSeconds)
        {
            Gfx.BlendRect(0, ScreenH - 40, ScreenW, 32, Gfx.Rgb(6, 8, 20), 200);
            Gfx.TextCentered(ScreenW / 2, ScreenH - 32, _toast, 2, Gfx.Rgb(170, 255, 170));
        }
    }

    static void _DrawGame()
    {
        _DrawBoard();
        if (_state == State.Playing && !_showHelp)
        {
            _DrawGhost();
            _DrawPiece();
        }
        else if (_state == State.GameOver && !_pieceLanded)
        {
            // the block that did not fit, or that was still falling
            _DrawPiece();
        }
        _DrawEffects();
        _DrawPanels();
        if (_state == State.GameOver)
            _DrawGameOver();
        else if (_paused)
            _DrawBanner("PAUSED", "P: CONTINUE");
    }

    // ---- drawn once ----

    // draws every kind of tile once and keeps the pixels, so a frame only copies them
    static unsafe void _BakeTiles()
    {
        int size = CellSize * CellSize;
        _tileSprites = (uint32*)Memory.Allocate(2 * 2 * _TileVariants * size * sizeof(uint32));
        for (var bit = 0; bit < 2; bit += 1)
        {
            for (var falling = 0; falling < 2; falling += 1)
            {
                for (var v = 0; v < _TileVariants; v += 1)
                {
                    Gfx.FillRect(0, 0, CellSize, CellSize, 0);
                    _DrawTilePixels(bit, falling == 1, v * 37 + 5);
                    uint32* sprite = _Sprite(bit, falling == 1, v);
                    for (var y = 0; y < CellSize; y += 1)
                    {
                        for (var x = 0; x < CellSize; x += 1)
                        {
                            sprite[y * CellSize + x] = Gfx.Peek(x, y);
                        }
                    }
                }
            }
        }
    }

    static unsafe uint32* _Sprite(int bit, bool falling, int variant)
    {
        int index = (bit * 2 + (falling ? 1 : 0)) * _TileVariants + variant;
        return _tileSprites + index * CellSize * CellSize;
    }

    // a tile at (0, 0): textured stone, a recessed plate and the glowing digit
    static void _DrawTilePixels(int bit, bool falling, int seed)
    {
        uint32 stone = bit == 1 ? Gfx.Rgb(88, 102, 130) : Gfx.Rgb(140, 108, 80);
        int boost = falling ? 30 : 0;
        for (var y = 0; y < CellSize; y += 1)
        {
            for (var x = 0; x < CellSize; x += 1)
            {
                int n = Gfx.Noise(x + seed * 31, y * 2 + seed * 17, 4) / 3 + Gfx.Hash(x + seed, y) / 8;
                int f = 170 + n / 2 + boost;
                if (y < 2 || x < 2)
                    f += 70;
                else if (y >= CellSize - 2 || x >= CellSize - 2)
                    f -= 90;
                Gfx.Plot(x, y, Gfx.Scale(stone, f));
            }
        }
        Gfx.BlendRect(5, 4, CellSize - 10, CellSize - 8, Gfx.Rgb(10, 8, 6), 90);
        Gfx.BlendRect(5, 4, CellSize - 10, 1, Gfx.Rgb(0, 0, 0), 140);

        string digit = bit == 1 ? "1" : "0";
        uint32 ink = bit == 1 ? Gfx.Rgb(175, 245, 255) : Gfx.Rgb(255, 215, 150);
        Gfx.Glow(CellSize / 2, CellSize / 2, CellSize / 2 + 3, _GlowColor(bit), falling ? 130 : 90);
        int dx = (CellSize - Gfx.TextWidth(digit, 3)) / 2 + 1;
        int dy = (CellSize - Gfx.TextHeight(3)) / 2;
        Gfx.Text(dx, dy, digit, 3, ink);
    }

    static uint32 _GlowColor(int bit)
    {
        return bit == 1 ? Gfx.Rgb(50, 170, 255) : Gfx.Rgb(255, 130, 30);
    }

    static unsafe void _BakeBackground()
    {
        uint32* p = Gfx.Pixels();
        for (var i = 0; i < ScreenW * ScreenH; i += 1)
        {
            p[i] = _sky[i];
        }
        _menuBackground = Gfx.Snapshot();
        _DrawWell();
        _DrawPanelFrames();
        _background = Gfx.Snapshot();
    }

    // a textured block of stone with a bevel
    static void _StoneRect(int x, int y, int w, int h, uint32 color, int seed)
    {
        for (var yy = 0; yy < h; yy += 1)
        {
            for (var xx = 0; xx < w; xx += 1)
            {
                int n = Gfx.Noise(xx + seed * 977, yy * 2 + seed * 131, 5) / 2 + Gfx.Hash(xx + seed, yy) / 6;
                int f = 190 + n / 2;
                if (yy < 2 || xx < 2)
                    f += 50;
                else if (yy >= h - 2 || xx >= w - 2)
                    f -= 70;
                Gfx.Plot(x + xx, y + yy, Gfx.Scale(color, f));
            }
        }
    }

    static void _DrawWell()
    {
        int w = BoardW * CellSize;
        int h = BoardH * CellSize;
        // stone walls and floor
        _StoneRect(FieldX - _WallW, FieldY - 6, _WallW, h + 6, Gfx.Rgb(96, 88, 78), 1);
        _StoneRect(FieldX + w, FieldY - 6, _WallW, h + 6, Gfx.Rgb(96, 88, 78), 2);
        _StoneRect(FieldX - 30, FieldY + h, w + 60, 20, Gfx.Rgb(86, 78, 70), 3);
        // the well and its grid
        Gfx.BlendRect(FieldX, FieldY, w, h, Gfx.Rgb(4, 4, 12), 190);
        for (var x = 1; x < BoardW; x += 1)
        {
            Gfx.BlendRect(FieldX + x * CellSize, FieldY, 1, h, Gfx.Rgb(120, 110, 160), 28);
        }
        for (var y = 1; y < BoardH; y += 1)
        {
            Gfx.BlendRect(FieldX, FieldY + y * CellSize, w, 1, Gfx.Rgb(120, 110, 160), 28);
        }
        // the spawn zone above the field; a block that locks here ends the game
        Gfx.BlendRect(FieldX, FieldY - SpawnRows * CellSize, w, SpawnRows * CellSize, Gfx.Rgb(60, 10, 30), 70);
        for (var x = 0; x < w; x += 12)
        {
            Gfx.FillRect(FieldX + x, FieldY - 2, 7, 2, Gfx.Rgb(200, 70, 80));
        }
    }

    static void _Panel(int x, int y, int w, int h)
    {
        Gfx.BlendRect(x, y, w, h, Gfx.Rgb(10, 8, 24), 170);
        Gfx.FrameRect(x, y, w, h, 2, Gfx.Rgb(150, 120, 70));
    }

    // the panels and the key list; the labels and values depend on the mode and are drawn every frame by _DrawPanels
    static void _DrawPanelFrames()
    {
        Gfx.TextCentered(ScreenW / 2, 14, "SHIFTY BITS", 4, Gfx.Rgb(255, 205, 90));

        int lx = _PanelLeftX;
        _Panel(lx, 120, FieldX - _WallW - 30 - lx, 502);

        int rx = _PanelRightX;
        _Panel(rx, 120, _PanelRightW, 200);
        Gfx.TextCentered(rx + _PanelRightW / 2, 134, "NEXT", 2, Gfx.Rgb(170, 160, 200));

        _Panel(rx, 340, _PanelRightW, 282);
        _KeyList(_PanelKeys, rx + 16, rx + 90, 354, 23);
    }

    static void _KeyList(ReadOnlySlice<string> pairs, int keyX, int textX, int y, int lineHeight)
    {
        for (var i = 0; i + 1 < pairs.Length; i += 2)
        {
            Gfx.TextShadow(keyX, y, pairs[i], 2, Gfx.Rgb(255, 215, 120));
            Gfx.TextShadow(textX, y, pairs[i + 1], 2, Gfx.Rgb(215, 210, 235));
            y += lineHeight;
        }
    }

    // ---- drawn every frame ----

    static unsafe void _DrawBackground()
    {
        Gfx.Restore(_state == State.Menu ? _menuBackground : _background);
        for (var s = 0; s < 120; s += 1)
        {
            int x = Gfx.Hash(s, 1) * ScreenW / 256 + Gfx.Hash(s, 2) % 4;
            int y = Gfx.Hash(s, 3) * (ScreenH - 200) / 256;
            // twinkling stars, only where the sky is not covered by the well or a panel
            if (x >= ScreenW || Gfx.Peek(x, y) != _sky[y * ScreenW + x])
                continue;
            double twinkle = 0.5 + 0.5 * Math.Sin(_time * (1.0 + Gfx.Hash(s, 4) / 64.0) + s);
            Gfx.AddPixel(x, y, Gfx.Rgb(220, 220, 255), (int)(60.0 + 170.0 * twinkle));
        }
    }

    static unsafe void _DrawTile(int px, int py, int bit, TileLook look, int variant)
    {
        Gfx.Blit(_Sprite(bit, look == TileLook.Falling, variant & (_TileVariants - 1)), CellSize, CellSize, px, py);
        if (look == TileLook.FlashWhite)
            Gfx.BlendRect(px, py, CellSize, CellSize, Gfx.Rgb(255, 255, 255), 200);
        else if (look == TileLook.FlashColor)
            Gfx.BlendRect(px, py, CellSize, CellSize, _GlowColor(bit), 120);
    }

    static void _DrawBoard()
    {
        // tiles about to dissolve blink between white and their glow color
        var flash = (int)(_time * 20.0) % 2 == 0 ? TileLook.FlashWhite : TileLook.FlashColor;
        for (var y = 0; y < BoardH; y += 1)
        {
            for (var x = 0; x < BoardW; x += 1)
            {
                int v = Game.Cell(x, y);
                if (v < 0)
                    continue;
                int i = y * BoardW + x;
                int py = FieldY + y * CellSize - (int)(_fall[i] * CellSize);
                // after the game, the tiles that ended it keep blinking
                var look = (_state == State.Clearing || _state == State.GameOver) && _clearing[i] ? flash : TileLook.Resting;
                _DrawTile(FieldX + x * CellSize, py, v, look, x * 7 + y * 13);
            }
        }
    }

    static void _DrawPiece()
    {
        var p = _piece;
        int px = FieldX + p.X * CellSize;
        int py = FieldY + p.Y * CellSize;
        Gfx.FrameRect(px - 2, py - 2, p.W * CellSize + 4, p.H * CellSize + 4, 2, Gfx.Rgb(255, 210, 90));
        if (_rollT >= 1.0 || _rollOld.Length != p.W * p.H)
        {
            for (var r = 0; r < p.H; r += 1)
            {
                for (var c = 0; c < p.W; c += 1)
                {
                    _DrawTile(px + c * CellSize, py + r * CellSize, p.Bit(r, c), TileLook.Falling, r * 5 + c);
                }
            }
            return;
        }

        // while rolling, the old bits slide by one cell and the row or column that wraps around comes in from the
        // other side; the block's rectangle clips them
        double t = _rollT * _rollT * (3.0 - 2.0 * _rollT);
        int off = (int)(_rollDir * t * CellSize);
        int dx = _rollVertical ? 0 : off;
        int dy = _rollVertical ? off : 0;
        Gfx.SetClip(px, py, p.W * CellSize, p.H * CellSize);
        for (var r = 0; r < p.H; r += 1)
        {
            for (var c = 0; c < p.W; c += 1)
            {
                _DrawTile(px + c * CellSize + dx, py + r * CellSize + dy, _rollOld[r * p.W + c], TileLook.Falling, r * 5 + c);
            }
        }
        if (_rollVertical)
        {
            int entry = _rollDir < 0 ? p.H : -1;
            int wrapped = _rollDir < 0 ? 0 : p.H - 1;
            for (var c = 0; c < p.W; c += 1)
            {
                _DrawTile(px + c * CellSize, py + entry * CellSize + off, _rollOld[wrapped * p.W + c], TileLook.Falling, wrapped * 5 + c);
            }
        }
        else
        {
            int entry = _rollDir < 0 ? p.W : -1;
            int wrapped = _rollDir < 0 ? 0 : p.W - 1;
            for (var r = 0; r < p.H; r += 1)
            {
                _DrawTile(px + entry * CellSize + off, py + r * CellSize, _rollOld[r * p.W + wrapped], TileLook.Falling, r * 5 + wrapped);
            }
        }
        Gfx.ResetClip();
    }

    // where the block would land
    static void _DrawGhost()
    {
        int row = Game.DropRow();
        if (row == _piece.Y)
            return;
        int px = FieldX + _piece.X * CellSize;
        int py = FieldY + row * CellSize;
        int w = _piece.W * CellSize;
        int h = _piece.H * CellSize;
        Gfx.BlendRect(px, py, w, h, Gfx.Rgb(255, 210, 90), 30);
        Gfx.FrameRect(px, py, w, h, 1, Gfx.Rgb(255, 210, 90));
    }

    static void _DrawEffects()
    {
        foreach (var p in _particles)
        {
            int a = (int)(Math.Min(1.0, p.Life * 2.0) * 255.0);
            int x = FieldX + (int)(p.X * CellSize);
            int y = FieldY + (int)(p.Y * CellSize);
            Gfx.AddPixel(x, y, p.Color, a);
            Gfx.AddPixel(x + 1, y, p.Color, a);
            Gfx.AddPixel(x, y + 1, p.Color, a);
            Gfx.AddPixel(x + 1, y + 1, p.Color, a);
        }
        foreach (var p in _popups)
        {
            int w = Gfx.TextWidth(p.Text, 3);
            // keep the text on the screen
            int x = Math.Clamp(FieldX + (int)(p.X * CellSize) - w / 2, 4, ScreenW - w - 4) + w / 2;
            Gfx.TextCentered(x, FieldY + (int)(p.Y * CellSize), p.Text, 3, p.Color);
        }
    }

    // one labelled value of the left panel
    static void _PanelValue(int index, string label, string value, uint32 color)
    {
        int y = 166 + index * 66;
        Gfx.TextShadow(_PanelLeftX + 20, y, label, 2, Gfx.Rgb(170, 160, 200));
        Gfx.TextShadow(_PanelLeftX + 20, y + 20, value, 4, color);
    }

    // the best value of a mode as text: a time in the score mode, else a score
    static string _BestText(Mode mode, int best)
    {
        if (mode != Mode.Score)
            return best.ToString();
        return best > 0 ? Game.TimeText(best / 1000.0, true) : "-";
    }

    // the values in the panels and the next block
    static void _DrawPanels()
    {
        int lx = _PanelLeftX + 20;
        Gfx.TextShadow(lx, 136, Game.ModeText(), 2, Gfx.Rgb(255, 205, 90));
        _PanelValue(0, "SCORE", _score.ToString(), Gfx.Rgb(255, 245, 225));
        _PanelValue(1, _mode == Mode.Score ? "BEST TIME" : "BEST", _BestText(_mode, _best), Gfx.Rgb(255, 215, 120));
        uint32 clock = Gfx.Rgb(190, 255, 190);
        // the last ten seconds of a countdown blink red
        if (_mode == Mode.Countdown && Game.Clock() < 10.0 && (int)(_time * 4.0) % 2 == 0)
            clock = Gfx.Rgb(255, 110, 100);
        _PanelValue(2, _mode == Mode.Countdown ? "TIME LEFT" : "TIME", Game.TimeText(Game.Clock(), _mode == Mode.Score), clock);
        _PanelValue(3, "LEVEL", _level.ToString(), Gfx.Rgb(170, 230, 255));
        _PanelValue(4, "TILES CLEARED", _tilesCleared.ToString(), Gfx.Rgb(235, 225, 210));
        _PanelValue(5, "BEST CHAIN", _bestChain.ToString(), Gfx.Rgb(255, 170, 120));
        Gfx.TextShadow(lx, 590, "SEED " + _seed.ToString(), 2, Gfx.Rgb(170, 160, 200));

        int nx = _PanelRightX + (_PanelRightW - _next.W * CellSize) / 2;
        int ny = 160 + (4 - _next.H) * CellSize / 2;
        for (var r = 0; r < _next.H; r += 1)
        {
            for (var c = 0; c < _next.W; c += 1)
            {
                _DrawTile(nx + c * CellSize, ny + r * CellSize, _next.Bit(r, c), TileLook.Resting, r * 5 + c);
            }
        }
        string off = Music.IsOn() ? "" : "MUSIC OFF (M)   ";
        if (!Music.SoundsOn())
            off += "SOUNDS OFF";
        if (off.Length > 0)
            Gfx.TextShadow(_PanelLeftX, ScreenH - 30, off, 2, Gfx.Rgb(170, 160, 200));
    }

    // a dark band across the screen with a big title
    static void _Band(int h, uint32 line)
    {
        int y = ScreenH / 2 - h / 2;
        Gfx.BlendRect(0, y, ScreenW, h, Gfx.Rgb(6, 8, 20), 215);
        Gfx.FillRect(0, y, ScreenW, 2, line);
        Gfx.FillRect(0, y + h - 2, ScreenW, 2, line);
    }

    static void _DrawBanner(string title, string sub)
    {
        int y = ScreenH / 2 - 70;
        _Band(140, Gfx.Rgb(255, 210, 90));
        Gfx.TextCentered(ScreenW / 2, y + 22, title, 7, Gfx.Rgb(255, 215, 100));
        Gfx.TextCentered(ScreenW / 2, y + 96, sub, 2, Gfx.Rgb(170, 230, 255));
    }

    static void _DrawGameOver()
    {
        int y = ScreenH / 2 - 105;
        bool won = _end == End.TimeUp || _end == End.TargetReached;
        _Band(210, won ? Gfx.Rgb(255, 210, 90) : Gfx.Rgb(255, 90, 90));
        string title = "GAME OVER";
        if (_end == End.TimeUp)
            title = "TIME UP";
        else if (_end == End.TargetReached)
            title = "TARGET REACHED";
        Gfx.TextCentered(ScreenW / 2, y + 20, title, 7, won ? Gfx.Rgb(255, 215, 100) : Gfx.Rgb(255, 120, 110));

        string info = "SCORE " + _score.ToString();
        if (_end == End.TargetReached)
            info = "TIME " + Game.TimeText(_playTime, true);
        else if (_mode == Mode.Score)
            info += " OF " + Game.Target().ToString();
        if (_end == End.Zeros)
            info = "4 ZEROS IN A ROW   " + info;
        if (_newBest)
            info += "   NEW BEST!";
        Gfx.TextCentered(ScreenW / 2, y + 90, info, 3, Gfx.Rgb(240, 235, 250));
        string details = Game.ModeText() + "   LEVEL " + _level.ToString() + "   BEST CHAIN " + _bestChain.ToString();
        Gfx.TextCentered(ScreenW / 2, y + 128, details, 2, Gfx.Rgb(200, 195, 220));
        Gfx.TextCentered(ScreenW / 2, y + 152, "SEED " + _seed.ToString(), 2, Gfx.Rgb(200, 195, 220));
        // a screenshot shows the date instead of the prompt
        if (_capturing)
            Gfx.TextCentered(ScreenW / 2, y + 180, DateTime.Now().ToString("yyyy-MM-dd HH:mm"), 2, Gfx.Rgb(170, 160, 200));
        else
            Gfx.TextCentered(ScreenW / 2, y + 180, "ENTER: NEW GAME    ESC: MENU    S: SAVE SCREENSHOT", 2, Gfx.Rgb(170, 230, 255));
    }

    // an on/off setting of the menu
    static void _MenuSwitch(int x, int y, int w, string name, string state, bool on, bool selected)
    {
        if (selected)
        {
            Gfx.BlendRect(x, y, w, 40, Gfx.Rgb(110, 80, 30), 110);
            Gfx.FrameRect(x, y, w, 40, 2, Gfx.Rgb(255, 205, 90));
        }
        else
        {
            Gfx.BlendRect(x, y, w, 40, Gfx.Rgb(0, 0, 0), 70);
        }
        Gfx.TextShadow(x + 20, y + 10, name, 3, selected ? Gfx.Rgb(255, 245, 225) : Gfx.Rgb(190, 185, 210));
        Gfx.TextShadow(x + w - 20 - Gfx.TextWidth(state, 3), y + 10, state, 3, on ? Gfx.Rgb(190, 255, 190) : Gfx.Rgb(255, 130, 120));
    }

    static void _DrawMenu()
    {
        int w = 780;
        int h = 600;
        int x = (ScreenW - w) / 2;
        int y = (ScreenH - h) / 2;
        uint32 gold = Gfx.Rgb(255, 205, 90);
        uint32 dim = Gfx.Rgb(170, 160, 200);
        Gfx.BlendRect(x, y, w, h, Gfx.Rgb(14, 12, 30), 225);
        Gfx.FrameRect(x, y, w, h, 2, Gfx.Rgb(200, 160, 70));
        Gfx.TextCentered(ScreenW / 2, y + 22, "SHIFTY BITS", 6, gold);
        Gfx.TextCentered(ScreenW / 2, y + 78, "SELECT A GAME MODE", 2, dim);

        int left = x + 44;
        int right = x + w - 44;
        for (var row = 0; row < ModeCount; row += 1)
        {
            int ry = y + 108 + row * 70;
            bool selected = row == _menuRow;
            var mode = (Mode)row;
            if (selected)
            {
                Gfx.BlendRect(x + 24, ry, w - 48, 62, Gfx.Rgb(110, 80, 30), 110);
                Gfx.FrameRect(x + 24, ry, w - 48, 62, 2, gold);
            }
            else
            {
                Gfx.BlendRect(x + 24, ry, w - 48, 62, Gfx.Rgb(0, 0, 0), 70);
            }
            Gfx.TextShadow(left, ry + 8, _ModeNames[row], 3, selected ? Gfx.Rgb(255, 245, 225) : Gfx.Rgb(190, 185, 210));

            string option = "";
            if (mode == Mode.Countdown)
                option = CountdownMinutes[_countdownChoice].ToString() + (_countdownChoice == 0 ? " MINUTE" : " MINUTES");
            else if (mode == Mode.Score)
                option = ScoreTargets[_scoreChoice].ToString() + " POINTS";
            if (option.Length > 0)
            {
                // the arrows show that the left and right keys change the option of the selected mode
                if (selected)
                    option = "◄ " + option + " ►";
                Gfx.TextShadow(right - Gfx.TextWidth(option, 3), ry + 8, option, 3, selected ? Gfx.Rgb(170, 230, 255) : Gfx.Rgb(130, 160, 185));
            }

            Gfx.TextShadow(left, ry + 38, _ModeRules[row], 2, selected ? Gfx.Rgb(225, 220, 240) : dim);
            int best = _menuBest[Game.BestSlot(mode, Game.Choice(mode))];
            if (best > 0)
            {
                string text = "BEST " + _BestText(mode, best);
                Gfx.TextShadow(right - Gfx.TextWidth(text, 2), ry + 38, text, 2, Gfx.Rgb(255, 215, 120));
            }
        }

        // music and sounds beside each other
        int half = (w - 48 - 12) / 2;
        // the music switch shows the name of the chosen song, as far as it fits
        string song = _songName.Length > 11 ? _songName[..11].ToString() : _songName;
        _MenuSwitch(x + 24, y + 390, half, "MUSIC", Music.IsOn() ? song : "OFF", Music.IsOn(), _menuRow == ModeCount);
        _MenuSwitch(x + 24 + half + 12, y + 390, half, "SOUNDS", Music.SoundsOn() ? "ON" : "OFF", Music.SoundsOn(), _menuRow == ModeCount + 1);

        int sy = y + 446;
        string seed = _seed.ToString();
        Gfx.TextShadow(left, sy + 8, "SEED", 2, dim);
        Gfx.TextShadow(left + 70, sy, seed, 4, _seedFixed ? Gfx.Rgb(170, 230, 255) : Gfx.Rgb(255, 245, 225));
        if ((int)(_time * 2.5) % 2 == 0)
            Gfx.FillRect(left + 70 + Gfx.TextWidth(seed, 4) + 6, sy, 4, Gfx.TextHeight(4), gold);
        string kind = _seedFixed ? "ENTERED: STAYS FOR EVERY GAME" : "RANDOM: A NEW ONE FOR EVERY GAME";
        Gfx.TextShadow(right - Gfx.TextWidth(kind, 2), sy + 8, kind, 2, dim);
        Gfx.TextShadow(left, sy + 40, "THE SAME SEED ALWAYS GIVES THE SAME BLOCKS", 2, dim);

        Gfx.FillRect(x + 24, y + h - 78, w - 48, 1, Gfx.Rgb(120, 100, 60));
        Gfx.TextCentered(ScreenW / 2, y + h - 62, _menuRow < ModeCount ? "↑ ↓: MODE   ← →: OPTION   ENTER: PLAY   H: HELP   ESC: QUIT" : _menuRow == ModeCount ? "↑ ↓ ← →: SELECT   ENTER: NEXT SONG / OFF   H: HELP   ESC: QUIT" : "↑ ↓ ← →: SELECT   ENTER: ON / OFF   H: HELP   ESC: QUIT", 2, Gfx.Rgb(170, 230, 255));
        Gfx.TextCentered(ScreenW / 2, y + h - 36, "0-9: TYPE A SEED   DEL: RANDOM   CTRL+C: COPY   CTRL+V: PASTE", 2, Gfx.Rgb(170, 230, 255));
    }

    static void _DrawHelp()
    {
        int w = 780;
        int h = 546;
        int x = (ScreenW - w) / 2;
        int y = (ScreenH - h) / 2;
        Gfx.BlendRect(0, 0, ScreenW, ScreenH, Gfx.Rgb(0, 0, 0), 120);
        Gfx.BlendRect(x, y, w, h, Gfx.Rgb(14, 12, 30), 238);
        Gfx.FrameRect(x, y, w, h, 2, Gfx.Rgb(200, 160, 70));
        Gfx.TextCentered(ScreenW / 2, y + 22, "SHIFTY BITS", 5, Gfx.Rgb(255, 205, 90));
        for (var i = 0; i < _HelpRules.Length; i += 1)
        {
            Gfx.TextShadow(x + 36, y + 84 + i * 22, _HelpRules[i], 2, Gfx.Rgb(225, 220, 240));
        }
        _KeyList(_HelpKeys, x + 36, x + 256, y + 214, 26);
        Gfx.TextCentered(ScreenW / 2, y + h - 40, "PRESS ANY KEY", 2, Gfx.Rgb(170, 230, 255));
    }
}
