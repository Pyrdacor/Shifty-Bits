//! The Windows clipboard, for copying and pasting the seed.

namespace ShiftyBits;

using System;

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

/// The clipboard of the operating system.
struct Clipboard
{
    /// Puts `text` on the clipboard.
    static unsafe void Copy(string text)
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
    static unsafe string Paste()
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
}
