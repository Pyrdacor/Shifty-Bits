//! Software rendering into a 32-bit framebuffer: rectangles, blending, glows and a 5x7 pixel font.

namespace ShiftyBits;

using System;

/// Width of the framebuffer in pixels.
const int ScreenW = 960;
/// Height of the framebuffer in pixels.
const int ScreenH = 720;

const ReadOnlySlice<string> _FontLines = embed_lines("../font.txt");
const int _GlyphRows = 7;
const int _GlyphCols = 5;

extern "C" void* memcpy(void* dest, void* source, nuint count);

uint32* _pix;
int _clipX0;
int _clipY0;
int _clipX1 = ScreenW;
int _clipY1 = ScreenH;

// glyph rows (5 bits each), _GlyphRows per glyph; index by codepoint through _glyphIndex
uint8[] _glyphs = [];
Dictionary<int, int> _glyphIndex = Dictionary<int, int>.Create();

/// Drawing primitives on the global framebuffer.
struct Gfx
{
    /// Allocates the framebuffer and parses the embedded font.
    static unsafe void Init()
    {
        _pix = (uint32*)Memory.Allocate(ScreenW * ScreenH * sizeof(uint32));
        _LoadFont();
    }

    /// The framebuffer, for handing it to the window.
    static unsafe uint32* Pixels()
    {
        return _pix;
    }

    /// A copy of the whole framebuffer (for backgrounds drawn once).
    static unsafe uint32* Snapshot()
    {
        uint32* copy = (uint32*)Memory.Allocate(ScreenW * ScreenH * sizeof(uint32));
        memcpy((void*)copy, (void*)_pix, (nuint)(ScreenW * ScreenH * sizeof(uint32)));
        return copy;
    }

    /// Copies a snapshot back into the framebuffer.
    static unsafe void Restore(uint32* copy)
    {
        memcpy((void*)_pix, (void*)copy, (nuint)(ScreenW * ScreenH * sizeof(uint32)));
    }

    /// Copies a `w` x `h` sprite to (`x`, `y`), clipped.
    static unsafe void Blit(uint32* sprite, int w, int h, int x, int y)
    {
        int x0 = Math.Max(x, _clipX0);
        int y0 = Math.Max(y, _clipY0);
        int x1 = Math.Min(x + w, _clipX1);
        int y1 = Math.Min(y + h, _clipY1);
        if (x0 >= x1)
            return;
        for (var yy = y0; yy < y1; yy += 1)
        {
            memcpy((void*)(_pix + yy * ScreenW + x0), (void*)(sprite + (yy - y) * w + (x0 - x)), (nuint)((x1 - x0) * sizeof(uint32)));
        }
    }

    /// Releases the framebuffer.
    static unsafe void Shutdown()
    {
        Memory.Free(_pix);
    }

    static void _LoadFont()
    {
        int count = _FontLines.Length / (_GlyphRows + 1);
        _glyphs = new uint8[count * _GlyphRows];
        for (var g = 0; g < count; g += 1)
        {
            int line = g * (_GlyphRows + 1);
            var header = _FontLines[line];
            int pos = 0;
            int cp = _DecodeUtf8(header, ref pos);
            _glyphIndex[cp] = g;
            for (var r = 0; r < _GlyphRows; r += 1)
            {
                var row = _FontLines[line + 1 + r];
                int bits = 0;
                for (var c = 0; c < _GlyphCols && c < row.Length; c += 1)
                {
                    if (row[c] == '#')
                        bits |= 1 << (_GlyphCols - 1 - c);
                }
                _glyphs[g * _GlyphRows + r] = (uint8)bits;
            }
        }
    }

    // decodes one UTF-8 character at `pos` and advances `pos` past it
    static int _DecodeUtf8(string s, ref int pos)
    {
        int b0 = (int)(uint8)s[pos];
        if (b0 < 0x80 || pos + 1 >= s.Length)
        {
            pos += 1;
            return b0;
        }
        int b1 = (int)(uint8)s[pos + 1] & 0x3f;
        if ((b0 & 0xe0) == 0xc0)
        {
            pos += 2;
            return ((b0 & 0x1f) << 6) | b1;
        }
        if (pos + 2 >= s.Length)
        {
            pos += 2;
            return '?';
        }
        int b2 = (int)(uint8)s[pos + 2] & 0x3f;
        pos += 3;
        return ((b0 & 0x0f) << 12) | (b1 << 6) | b2;
    }

    /// Packs a color.
    static uint32 Rgb(int r, int g, int b)
    {
        return ((uint32)Math.Clamp(r, 0, 255) << 16) | ((uint32)Math.Clamp(g, 0, 255) << 8) | (uint32)Math.Clamp(b, 0, 255);
    }

    static int _R(uint32 c)
    {
        return (int)((c >> 16) & 0xff);
    }

    static int _G(uint32 c)
    {
        return (int)((c >> 8) & 0xff);
    }

    static int _B(uint32 c)
    {
        return (int)(c & 0xff);
    }

    /// Mixes `a` and `b`; `t` goes from 0 (only `a`) to 256 (only `b`).
    static uint32 Mix(uint32 a, uint32 b, int t)
    {
        int u = 256 - t;
        return Rgb((_R(a) * u + _R(b) * t) >> 8, (_G(a) * u + _G(b) * t) >> 8, (_B(a) * u + _B(b) * t) >> 8);
    }

    /// Scales the brightness of `c` by `f` / 256.
    static uint32 Scale(uint32 c, int f)
    {
        return Rgb((_R(c) * f) >> 8, (_G(c) * f) >> 8, (_B(c) * f) >> 8);
    }

    /// Restricts drawing to a rectangle (intersected with the screen).
    static void SetClip(int x, int y, int w, int h)
    {
        _clipX0 = Math.Max(0, x);
        _clipY0 = Math.Max(0, y);
        _clipX1 = Math.Min(ScreenW, x + w);
        _clipY1 = Math.Min(ScreenH, y + h);
    }

    /// Allows drawing on the whole screen again.
    static void ResetClip()
    {
        _clipX0 = 0;
        _clipY0 = 0;
        _clipX1 = ScreenW;
        _clipY1 = ScreenH;
    }

    /// Sets one pixel (clipped).
    static unsafe void Plot(int x, int y, uint32 c)
    {
        if (x < _clipX0 || y < _clipY0 || x >= _clipX1 || y >= _clipY1)
            return;
        _pix[y * ScreenW + x] = c;
    }

    /// Reads one pixel (0 outside the screen).
    static unsafe uint32 Peek(int x, int y)
    {
        if (x < 0 || y < 0 || x >= ScreenW || y >= ScreenH)
            return 0;
        return _pix[y * ScreenW + x];
    }

    /// Adds `c` scaled by `a` / 256 to a pixel, saturating (clipped).
    static unsafe void AddPixel(int x, int y, uint32 c, int a)
    {
        if (x < _clipX0 || y < _clipY0 || x >= _clipX1 || y >= _clipY1 || a <= 0)
            return;
        int i = y * ScreenW + x;
        uint32 p = _pix[i];
        _pix[i] = Rgb(_R(p) + ((_R(c) * a) >> 8), _G(p) + ((_G(c) * a) >> 8), _B(p) + ((_B(c) * a) >> 8));
    }

    /// Fills a rectangle (clipped).
    static unsafe void FillRect(int x, int y, int w, int h, uint32 c)
    {
        int x0 = Math.Max(x, _clipX0);
        int y0 = Math.Max(y, _clipY0);
        int x1 = Math.Min(x + w, _clipX1);
        int y1 = Math.Min(y + h, _clipY1);
        for (var yy = y0; yy < y1; yy += 1)
        {
            uint32* row = _pix + yy * ScreenW;
            for (var xx = x0; xx < x1; xx += 1)
            {
                row[xx] = c;
            }
        }
    }

    /// Blends a rectangle towards `c` by `a` / 256 (clipped).
    static unsafe void BlendRect(int x, int y, int w, int h, uint32 c, int a)
    {
        int x0 = Math.Max(x, _clipX0);
        int y0 = Math.Max(y, _clipY0);
        int x1 = Math.Min(x + w, _clipX1);
        int y1 = Math.Min(y + h, _clipY1);
        if (a <= 0)
            return;
        uint32 t = (uint32)Math.Min(a, 256);
        uint32 u = 256u - t;
        // red and blue are mixed in one multiplication, green separately
        uint32 crb = (c & 0xff00ffu) * t;
        uint32 cg = (c & 0xff00u) * t;
        for (var yy = y0; yy < y1; yy += 1)
        {
            uint32* row = _pix + yy * ScreenW;
            for (var xx = x0; xx < x1; xx += 1)
            {
                uint32 p = row[xx];
                uint32 rb = (((p & 0xff00ffu) * u + crb) >> 8) & 0xff00ffu;
                uint32 g = (((p & 0xff00u) * u + cg) >> 8) & 0xff00u;
                row[xx] = rb | g;
            }
        }
    }

    /// Draws a rectangle outline of the given thickness.
    static void FrameRect(int x, int y, int w, int h, int t, uint32 c)
    {
        FillRect(x, y, w, t, c);
        FillRect(x, y + h - t, w, t, c);
        FillRect(x, y, t, h, c);
        FillRect(x + w - t, y, t, h, c);
    }

    /// Adds a soft round glow around (`cx`, `cy`).
    static void Glow(int cx, int cy, int radius, uint32 c, int strength)
    {
        int r2 = radius * radius;
        for (var y = -radius; y <= radius; y += 1)
        {
            for (var x = -radius; x <= radius; x += 1)
            {
                int d2 = x * x + y * y;
                if (d2 < r2)
                {
                    int f = 256 - d2 * 256 / r2;
                    AddPixel(cx + x, cy + y, c, (f * f / 256) * strength / 256);
                }
            }
        }
    }

    /// A deterministic hash of a position, 0 to 255.
    static int Hash(int x, int y)
    {
        uint32 h = unchecked((uint32)x * 374761393u + (uint32)y * 668265263u);
        h = unchecked((h ^ (h >> 13)) * 1274126177u);
        return (int)((h ^ (h >> 16)) & 0xff);
    }

    /// Smooth value noise, 0 to 255, with a cell size of `cell` pixels.
    static int Noise(int x, int y, int cell)
    {
        int gx = x / cell;
        int gy = y / cell;
        int fx = (x % cell) * 256 / cell;
        int fy = (y % cell) * 256 / cell;
        int a = Hash(gx, gy);
        int b = Hash(gx + 1, gy);
        int c = Hash(gx, gy + 1);
        int d = Hash(gx + 1, gy + 1);
        int top = a + ((b - a) * fx >> 8);
        int bottom = c + ((d - c) * fx >> 8);
        return top + ((bottom - top) * fy >> 8);
    }

    // ---- text ----

    static int _Glyph(int cp)
    {
        if (cp >= 'a' && cp <= 'z')
            cp -= 32;
        else if (cp >= 0xe0 && cp <= 0xfe && cp != 0xf7)
            cp -= 32;
        if (_glyphIndex.ContainsKey(cp))
            return _glyphIndex[cp];
        return -1;
    }

    /// The width of `text` in pixels at the given scale.
    static int TextWidth(string text, int scale)
    {
        int n = 0;
        int pos = 0;
        while (pos < text.Length)
        {
            _DecodeUtf8(text, ref pos);
            n += 1;
        }
        if (n == 0)
            return 0;
        return (n * (_GlyphCols + 1) - 1) * scale;
    }

    /// Draws `text` with its top left corner at (`x`, `y`).
    static void Text(int x, int y, string text, int scale, uint32 c)
    {
        int pos = 0;
        int cx = x;
        while (pos < text.Length)
        {
            int g = _Glyph(_DecodeUtf8(text, ref pos));
            if (g >= 0)
            {
                for (var r = 0; r < _GlyphRows; r += 1)
                {
                    int bits = (int)_glyphs[g * _GlyphRows + r];
                    if (bits == 0)
                        continue;
                    for (var col = 0; col < _GlyphCols; col += 1)
                    {
                        if ((bits & (1 << (_GlyphCols - 1 - col))) != 0)
                            FillRect(cx + col * scale, y + r * scale, scale, scale, c);
                    }
                }
            }
            cx += (_GlyphCols + 1) * scale;
        }
    }

    /// Draws `text` with a drop shadow.
    static void TextShadow(int x, int y, string text, int scale, uint32 c)
    {
        int off = Math.Max(1, scale / 2);
        Text(x + off, y + off, text, scale, Rgb(0, 0, 0));
        Text(x, y, text, scale, c);
    }

    /// Draws `text` horizontally centered on `cx`, with a shadow.
    static void TextCentered(int cx, int y, string text, int scale, uint32 c)
    {
        TextShadow(cx - TextWidth(text, scale) / 2, y, text, scale, c);
    }

    /// Row `r` (0 at the top) of the glyph of the character `cp`: one bit per column, the leftmost column in bit 4
    /// (0 for a character the font does not have).
    static int GlyphRow(int cp, int r)
    {
        int g = _Glyph(cp);
        return g < 0 ? 0 : (int)_glyphs[g * _GlyphRows + r];
    }

    /// The height of a line of text at the given scale.
    static int TextHeight(int scale)
    {
        return _GlyphRows * scale;
    }
}
