//! The clipboard on Linux, for copying and pasting the seed. X11 and Wayland keep the clipboard in the program that
//! copied, so the usual helpers do it: wl-copy/wl-paste (Wayland), xclip or xsel (X11), whichever is installed. Without
//! any of them, copying and pasting works within the game.

namespace ShiftyBits;

using System;

// what was copied last, for pasting when no helper is installed
string _copied = "";

/// The clipboard of the desktop.
struct Clipboard
{
    /// Puts `text` (the digits of a seed) on the clipboard.
    static void Copy(string text)
    {
        _copied = text;
        // only digits get here, so the text needs no quoting
        string digits = "";
        for (var i = 0; i < text.Length; i += 1)
        {
            if (text[i] >= '0' && text[i] <= '9')
                digits += text[i..i + 1].ToString();
        }
        string put = "printf %s " + digits;
        Process.Run("(" + put + " | wl-copy || " + put + " | xclip -selection clipboard || " + put + " | xsel -b -i) >/dev/null 2>&1");
    }

    /// The text on the clipboard ("" if there is none).
    static string Paste()
    {
        if (Process.RunCapture("wl-paste -n 2>/dev/null || xclip -selection clipboard -o 2>/dev/null || xsel -b -o 2>/dev/null") is string text)
        {
            if (text.Length > 0)
                return text;
        }
        return _copied;
    }
}
