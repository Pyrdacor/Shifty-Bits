//! Encoding the framebuffer as a PNG file (uncompressed deflate blocks, so no compression library is needed).

namespace ShiftyBits;

using System;

uint32[] _crcTable = [];

/// Writes the framebuffer to PNG files.
struct Screenshot
{
    /// The current framebuffer as the bytes of a PNG file.
    static uint8[] Encode()
    {
        int rowBytes = 1 + ScreenW * 3;
        int raw = ScreenH * rowBytes;
        int blocks = (raw + 65534) / 65535;
        int zlib = 2 + raw + blocks * 5 + 4;
        int size = 8 + (12 + 13) + (12 + zlib) + 12;
        var b = new uint8[size];

        uint8[] signature = [137, 80, 78, 71, 13, 10, 26, 10];
        for (var i = 0; i < 8; i += 1)
        {
            b[i] = signature[i];
        }
        int at = 8;

        // IHDR: size, 8 bit RGB, no interlace
        _Put32(b, at, 13);
        _Tag(b, at + 4, "IHDR");
        _Put32(b, at + 8, ScreenW);
        _Put32(b, at + 12, ScreenH);
        b[at + 16] = 8;
        b[at + 17] = 2;
        _Put32(b, at + 21, (int)_Crc(b, at + 4, 17));
        at += 25;

        // IDAT: a zlib stream of stored blocks over the filtered rows (filter 0 = none)
        _Put32(b, at, zlib);
        _Tag(b, at + 4, "IDAT");
        int data = at + 8;
        int w = data;
        b[w] = 0x78;
        b[w + 1] = 0x01;
        w += 2;
        uint32 s1 = 1;
        uint32 s2 = 0;
        int left = raw;
        int pos = 0;   // position in the raw (filtered) image
        while (left > 0)
        {
            int n = Math.Min(left, 65535);
            left -= n;
            b[w] = left == 0 ? (uint8)1 : (uint8)0;
            b[w + 1] = (uint8)(n & 0xff);
            b[w + 2] = (uint8)(n >> 8);
            b[w + 3] = (uint8)(~n & 0xff);
            b[w + 4] = (uint8)((~n >> 8) & 0xff);
            w += 5;
            for (var k = 0; k < n; k += 1)
            {
                int y = pos / rowBytes;
                int col = pos % rowBytes;
                uint8 v = 0;
                if (col > 0)
                {
                    int x = (col - 1) / 3;
                    uint32 c = Gfx.Peek(x, y);
                    int channel = (col - 1) % 3;
                    v = (uint8)((c >> (16 - channel * 8)) & 0xff);
                }
                b[w] = v;
                w += 1;
                pos += 1;
                s1 = (s1 + v) % 65521;
                s2 = (s2 + s1) % 65521;
            }
        }
        _Put32(b, w, (int)((s2 << 16) | s1));
        w += 4;
        _Put32(b, w, (int)_Crc(b, at + 4, 4 + zlib));
        at = w + 4;

        _Put32(b, at, 0);
        _Tag(b, at + 4, "IEND");
        _Put32(b, at + 8, (int)_Crc(b, at + 4, 4));

        return b;
    }

    static void _Put32(uint8[] b, int at, int v)
    {
        b[at] = (uint8)((v >> 24) & 0xff);
        b[at + 1] = (uint8)((v >> 16) & 0xff);
        b[at + 2] = (uint8)((v >> 8) & 0xff);
        b[at + 3] = (uint8)(v & 0xff);
    }

    static void _Tag(uint8[] b, int at, string tag)
    {
        for (var i = 0; i < 4; i += 1)
        {
            b[at + i] = (uint8)tag[i];
        }
    }

    static uint32 _Crc(uint8[] b, int start, int count)
    {
        if (_crcTable.Length == 0)
        {
            _crcTable = new uint32[256];
            for (var n = 0; n < 256; n += 1)
            {
                uint32 c = (uint32)n;
                for (var k = 0; k < 8; k += 1)
                {
                    c = (c & 1) != 0 ? 0xedb88320u ^ (c >> 1) : c >> 1;
                }
                _crcTable[n] = c;
            }
        }
        uint32 crc = 0xffffffffu;
        for (var i = start; i < start + count; i += 1)
        {
            crc = _crcTable[(int)((crc ^ b[i]) & 0xff)] ^ (crc >> 8);
        }
        return crc ^ 0xffffffffu;
    }
}
