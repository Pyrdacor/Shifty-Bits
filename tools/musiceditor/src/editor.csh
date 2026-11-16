//! The editor: its state, the keyboard and mouse handling and the drawing. The screen is drawn anew every frame, and
//! a button handles its click while it is drawn (`_click` holds the mouse button pressed since the last frame), so
//! the place of every control is written down only once.

namespace ShiftyBits;

using System;

const int KeyEscape = 256;
const int KeyEnter = 257;
const int KeyBackspace = 259;
const int KeyDelete = 261;
const int KeyRight = 262;
const int KeyLeft = 263;
const int KeyDown = 264;
const int KeyUp = 265;
const int KeyPageUp = 266;
const int KeyPageDown = 267;
const int KeyHome = 268;
const int KeyEnd = 269;
const int KeyF2 = 291;
const int KeyPadEnter = 335;
const int ModShift = 1;
const int ModCtrl = 2;

// ---- layout ----

const int _LeftW = 220;
const int _TrackY = 52;
const int _TrackRowH = 24;
const int _TrackButtonsY = 346;
const int _ParamY = 384;
const int _ParamRowH = 19;
const int _KeysX = 228;
const int _GridX = 272;
const int _StepW = 21;
const int _ViewBars = 2;
const int _HeaderY = 52;
const int _GridY = 70;
const int _RowH = 12;
const int _Rows = 40;
const int _GridW = _ViewBars * StepsPerBar * _StepW;
const int _GridH = _Rows * _RowH;
const int _OverviewY = _GridY + _GridH + 12;
const int _OverviewRowH = 9;
const int _HintY = 676;
const int _StatusY = 702;

const int _NameLength = 10;
const int _UndoSteps = 200;
const double _StatusSeconds = 5.0;

const ReadOnlySlice<string> _ParamNames = [
    "WAVE", "VOLUME", "ATTACK", "DECAY", "SUSTAIN", "RELEASE", "VIBRATO", "SWEEP", "ECHO", "GATE", "FOLLOW", "TRANSP.",
    "DETUNE", "CUTOFF", "PLUCK",
];
const ReadOnlySlice<string> _WaveLabels = ["SINE", "TRI", "PULSE", "SQUARE", "NOISE", "SAW"];
// one color per track, for its notes
const ReadOnlySlice<uint32> _TrackColors = [
    0x5ac8ffu, 0xffb45au, 0x8ce678u, 0xff7896u, 0xc8a0ffu, 0xffe66eu,
    0x64e6d2u, 0xff9664u, 0xa0b4ffu, 0xdcdc8cu, 0xff82dcu, 0x96dc96u,
];

// what a drag in the grid does
enum _Drag : uint8
{
    None,
    Place,
    Erase,
}

// ---- state ----

string _path = "song.txt";
bool _dirty;
bool _quit;
bool _quitAsked;

int _sel;                   // the selected track
int _bar;                   // the selected bar: play starts here, copy, paste and clear work on it
int _viewBar;               // the first bar shown in the grid
int _topNote = 88;          // the note of the top row of the grid
int _lastNote = 69;         // the note clicked last, for the preview of an instrument
bool _loopView;
bool _renaming;

int _mouseX;
int _mouseY;
bool _mouseLeft;
bool _mouseRight;
bool _shiftDown;
int _click;                 // 1 or 2: the left or right button was pressed since the last frame
int _wheel;                 // steps of the mouse wheel since the last frame

_Drag _drag = _Drag.None;
int _dragStep;
int _dragNote;
bool _dragChanged;
int[] _dragBackup = [];

List<string> _undo = List<string>.Create();
List<string> _redo = List<string>.Create();
List<int[]> _clip = List<int[]>.Create();

string _status = "";
double _statusTime;
double _now;

/// The music editor.
struct Editor
{
    // ---- file ----

    /// Loads the song file `path`; without a name, `song.txt` from this folder or one of the folders above it.
    static void Open(string path)
    {
        if (path.Length == 0)
        {
            path = "song.txt";
            string up = "";
            for (var i = 0; i < 4; i += 1)
            {
                if (File.Exists(up + "song.txt"))
                {
                    path = up + "song.txt";
                    break;
                }
                up += "../";
            }
        }
        _path = path;
        if (!File.Exists(path))
            _Say("NEW FILE " + path + ": STARTING WITH THE SONG OF THE GAME");
        else if (File.ReadAllText(path) is string text)
        {
            _Apply(text);
            _Say("LOADED " + path);
        }
        else
            _Say("CANNOT READ " + path);
        if (_tracks.Count() == 0)
            _tracks.Add(Song.NewTrack("TRACK 1"));
        _CenterOnTrack();
    }

    static void _Save()
    {
        if (File.WriteAllText(_path, Song.ToText()) is error e)
        {
            _Say("CANNOT WRITE " + _path);
            return;
        }
        _dirty = false;
        _quitAsked = false;
        _Say("SAVED " + _path + ". THE GAME PLAYS IT AT ITS NEXT START.");
    }

    /// Whether the window may close: with unsaved changes only when asked a second time.
    static bool MayQuit()
    {
        if (!_dirty || _quitAsked)
            return true;
        _quitAsked = true;
        _Say("UNSAVED CHANGES: CTRL+S SAVES, CLOSING AGAIN DISCARDS THEM");
        return false;
    }

    /// Whether the editor wants to end.
    static bool Quitting()
    {
        return _quit;
    }

    static void _Say(string text)
    {
        _status = text;
        _statusTime = _now;
    }

    // ---- undo ----

    // call before every change of the song
    static void _Touch()
    {
        _undo.Add(Song.ToText());
        if (_undo.Count() > _UndoSteps)
            _undo.RemoveAt(0);
        _redo.Clear();
        _dirty = true;
        _quitAsked = false;
    }

    static void _Undo(List<string> from, List<string> to)
    {
        if (from.Count() == 0)
            return;
        to.Add(Song.ToText());
        string text = from[from.Count() - 1];
        from.RemoveAt(from.Count() - 1);
        _Apply(text);
        _dirty = true;
    }

    // replaces the song by the one in `text` and keeps the view valid
    static void _Apply(string text)
    {
        var lines = List<string>.Create();
        foreach (var line in text.Split('\n'))
        {
            lines.Add(line.ToString());
        }
        Music.LoadSong(lines.ToArray());
        if (_tracks.Count() == 0)
            _tracks.Add(Song.NewTrack("TRACK 1"));
        _SongChanged();
    }

    // after the number of tracks or bars or the tempo changed
    static void _SongChanged()
    {
        Music.SongChanged();
        _sel = Math.Clamp(_sel, 0, _tracks.Count() - 1);
        _bar = Math.Clamp(_bar, 0, _songBars - 1);
        _viewBar = Math.Clamp(_viewBar, 0, Math.Max(0, _songBars - _ViewBars));
        if (_soloTrack >= _tracks.Count())
            Music.SetSolo(-1);
        _UpdateLoop();
    }

    // ---- playing ----

    static void _UpdateLoop()
    {
        if (_loopView)
            Music.SetLoop(_viewBar * StepsPerBar, (_viewBar + _ViewBars) * StepsPerBar);
        else
            Music.SetLoop(0, Song.Steps());
    }

    static void _TogglePlay()
    {
        if (Music.IsPlaying())
        {
            Music.Halt();
            return;
        }
        _UpdateLoop();
        Music.PlayFrom((_loopView ? _viewBar : _bar) * StepsPerBar);
    }

    static void _SelectBar(int bar)
    {
        _bar = Math.Clamp(bar, 0, _songBars - 1);
        if (_bar < _viewBar)
            _viewBar = _bar;
        else if (_bar >= _viewBar + _ViewBars)
            _viewBar = _bar - _ViewBars + 1;
        _UpdateLoop();
    }

    static void _SelectTrack(int track)
    {
        _sel = Math.Clamp(track, 0, _tracks.Count() - 1);
        _renaming = false;
        _CenterOnTrack();
    }

    // the track whose notes the selected track plays: itself, or the one it follows
    static int _Source()
    {
        int follow = _tracks[_sel].Follow;
        return follow >= 0 ? follow : _sel;
    }

    // scrolls the grid so that the notes of the selected track are in the middle
    static void _CenterOnTrack()
    {
        var notes = _tracks[_Source()].Notes;
        int low = 1000;
        int high = 0;
        foreach (var n in notes)
        {
            if (n > 0)
            {
                low = Math.Min(low, n);
                high = Math.Max(high, n);
            }
        }
        if (high == 0)
            return;
        _SetTopNote((low + high) / 2 + _Rows / 2);
    }

    static void _SetTopNote(int note)
    {
        _topNote = Math.Clamp(note, LowestNote + _Rows - 1, HighestNote);
    }

    // ---- notes ----

    static int[] _Copy(int[] notes)
    {
        var copy = new int[notes.Length];
        for (var i = 0; i < notes.Length; i += 1)
        {
            copy[i] = notes[i];
        }
        return copy;
    }

    // a note of `len` steps at `start`; what it covers is replaced
    static void _Place(int[] notes, int start, int len, int note)
    {
        int end = Math.Min(start + len, notes.Length);
        notes[start] = note;
        for (var i = start + 1; i < end; i += 1)
        {
            notes[i] = NoteHold;
        }
        // the rest of a longer note that was here before would lengthen the new one
        for (var i = end; i < notes.Length && notes[i] == NoteHold; i += 1)
        {
            notes[i] = NoteOff;
        }
    }

    // removes the note that sounds at `step`, if it is `note`
    static void _Erase(int step, int note)
    {
        var notes = _tracks[_sel].Notes;
        int start = Song.NoteStart(notes, step);
        if (start < 0 || notes[start] != note)
            return;
        if (!_dragChanged)
        {
            _Touch();
            _dragChanged = true;
        }
        int len = Song.NoteLength(notes, start);
        for (var i = start; i < start + len; i += 1)
        {
            notes[i] = NoteOff;
        }
    }

    // holds without a note before them mean nothing: they become silence
    static void _Tidy(int[] notes)
    {
        bool sounding = false;
        for (var i = 0; i < notes.Length; i += 1)
        {
            if (notes[i] > 0)
                sounding = true;
            else if (notes[i] == NoteOff)
                sounding = false;
            else if (!sounding)
                notes[i] = NoteOff;
        }
    }

    // copies the selected bar of the selected track, or of all tracks
    static void _CopyBar(bool all)
    {
        _clip = List<int[]>.Create();
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            if (!all && t != _sel)
                continue;
            var notes = _tracks[t].Notes;
            var bar = new int[StepsPerBar];
            for (var s = 0; s < StepsPerBar; s += 1)
            {
                bar[s] = notes[_bar * StepsPerBar + s];
            }
            // a note that comes over from the bar before starts with the copy
            int start = Song.NoteStart(notes, _bar * StepsPerBar);
            if (bar[0] == NoteHold && start >= 0)
                bar[0] = notes[start];
            _clip.Add(bar);
        }
        _Say(all ? "COPIED BAR " + (_bar + 1).ToString() + " OF ALL TRACKS" : "COPIED BAR " + (_bar + 1).ToString() + " OF " + _tracks[_sel].Name);
    }

    static void _PasteBar()
    {
        if (_clip.Count() == 0)
            return;
        bool all = _clip.Count() > 1;
        if (all && _clip.Count() != _tracks.Count())
        {
            _Say("THE COPY IS FROM A SONG WITH ANOTHER NUMBER OF TRACKS");
            return;
        }
        _Touch();
        for (var c = 0; c < _clip.Count(); c += 1)
        {
            var notes = _tracks[all ? c : _sel].Notes;
            for (var s = 0; s < StepsPerBar; s += 1)
            {
                notes[_bar * StepsPerBar + s] = _clip[c][s];
            }
            _Tidy(notes);
        }
        _Say("PASTED INTO BAR " + (_bar + 1).ToString());
    }

    static void _ClearBar(bool all)
    {
        _Touch();
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            if (!all && t != _sel)
                continue;
            var notes = _tracks[t].Notes;
            for (var s = 0; s < StepsPerBar; s += 1)
            {
                notes[_bar * StepsPerBar + s] = NoteOff;
            }
            _Tidy(notes);
        }
    }

    // ---- tracks ----

    static void _AddTrack(bool copy)
    {
        if (_tracks.Count() >= MaxTracks)
        {
            _Say("A SONG HAS AT MOST " + MaxTracks.ToString() + " TRACKS");
            return;
        }
        _Touch();
        var track = Song.NewTrack("TRACK " + (_tracks.Count() + 1).ToString());
        if (copy)
        {
            track = _tracks[_sel];
            track.Notes = _Copy(track.Notes);
        }
        _tracks.Add(track);
        _sel = _tracks.Count() - 1;
        _SongChanged();
    }

    static void _DeleteTrack()
    {
        if (_tracks.Count() <= 1)
            return;
        _Touch();
        _tracks.RemoveAt(_sel);
        // the tracks behind it moved up; a track that followed it plays its own notes again
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            var track = _tracks[t];
            if (track.Follow == _sel)
                track.Follow = -1;
            else if (track.Follow > _sel)
                track.Follow -= 1;
            _tracks[t] = track;
        }
        Music.SetSolo(-1);
        _SongChanged();
    }

    static void _ToggleMute(int t)
    {
        _Touch();
        var track = _tracks[t];
        track.Muted = !track.Muted;
        _tracks[t] = track;
    }

    // ---- instrument ----

    static double _Step(double value, int delta, double step, double min, double max)
    {
        // rounded, so that many small steps do not add up to 0.30000000000000004
        return Math.Clamp(Math.Round((value + delta * step) * 10000.0) / 10000.0, min, max);
    }

    static string _ParamText(Track t, int param)
    {
        switch (param)
        {
            case 0:
                return _WaveLabels[(int)t.Sound.Wave];
            case 1:
                return Song.Number(t.Sound.Volume);
            case 2:
                return Song.Number(t.Sound.Attack);
            case 3:
                return Song.Number(t.Sound.Decay);
            case 4:
                return Song.Number(t.Sound.Sustain);
            case 5:
                return Song.Number(t.Sound.Release);
            case 6:
                return Song.Number(t.Sound.Vibrato);
            case 7:
                return Song.Number(t.Sound.SweepTo);
            case 8:
                return t.Sound.Echo ? "ON" : "OFF";
            case 9:
                return Song.Number(t.Gate);
            case 10:
                return t.Follow >= 0 ? "TRK " + (t.Follow + 1).ToString() : "-";
            case 11:
                return (t.Transpose > 0 ? "+" : "") + t.Transpose.ToString();
            case 12:
                return Song.Number(t.Sound.Detune);
            case 13:
                return t.Sound.Cutoff > 0.0 ? Song.Number(t.Sound.Cutoff) : "OFF";
            case 14:
                return Song.Number(t.Sound.Pluck);
        }
        return "";
    }

    // changes a value of the selected track by `delta` steps (10 or -10 with Shift)
    static void _ChangeParam(int param, int delta)
    {
        _Touch();
        var t = _tracks[_sel];
        int one = delta > 0 ? 1 : -1;
        switch (param)
        {
            case 0:
                t.Sound.Wave = (Wave)(((int)t.Sound.Wave + one + WaveNames.Length) % WaveNames.Length);
                break;
            case 1:
                t.Sound.Volume = _Step(t.Sound.Volume, delta, 0.005, 0.0, 0.6);
                break;
            case 2:
                t.Sound.Attack = _Step(t.Sound.Attack, delta, 0.001, 0.001, 0.5);
                break;
            case 3:
                t.Sound.Decay = _Step(t.Sound.Decay, delta, 0.01, 0.01, 3.0);
                break;
            case 4:
                t.Sound.Sustain = _Step(t.Sound.Sustain, delta, 0.05, 0.0, 1.0);
                break;
            case 5:
                t.Sound.Release = _Step(t.Sound.Release, delta, 0.01, 0.01, 2.0);
                break;
            case 6:
                t.Sound.Vibrato = _Step(t.Sound.Vibrato, delta, 0.0005, 0.0, 0.05);
                break;
            case 7:
                t.Sound.SweepTo = _Step(t.Sound.SweepTo, delta, 0.05, 0.0, 1.0);
                break;
            case 8:
                t.Sound.Echo = !t.Sound.Echo;
                break;
            case 9:
                t.Gate = _Step(t.Gate, delta, 0.05, 0.05, 1.0);
                break;
            case 10:
                t.Follow = _NextFollow(t.Follow, one);
                break;
            case 11:
                // Shift moves by an octave
                t.Transpose = Math.Clamp(t.Transpose + (delta == one ? one : one * 12), -36, 36);
                break;
            case 12:
                t.Sound.Detune = _Step(t.Sound.Detune, delta, 0.001, 0.0, 0.03);
                break;
            case 13:
                t.Sound.Cutoff = _Step(t.Sound.Cutoff, delta, 50.0, 0.0, 8000.0);
                break;
            case 14:
                t.Sound.Pluck = _Step(t.Sound.Pluck, delta, 0.5, 0.0, 16.0);
                break;
        }
        _tracks[_sel] = t;
        Music.Preview(Math.Clamp(_lastNote + t.Transpose, LowestNote, HighestNote), t.Sound, 0.25);
    }

    // the next track the selected one can follow: one with notes of its own, and only if nothing follows the selected
    static int _NextFollow(int follow, int dir)
    {
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            if (_tracks[t].Follow == _sel)
            {
                _Say("ANOTHER TRACK FOLLOWS THIS ONE, SO IT CANNOT FOLLOW ITSELF");
                return -1;
            }
        }
        int count = _tracks.Count() + 1;
        // position 0 is "none", position n is track n - 1
        int pos = follow + 1;
        for (var i = 0; i < count; i += 1)
        {
            pos = (pos + dir + count) % count;
            if (pos == 0)
                return -1;
            if (pos - 1 != _sel && _tracks[pos - 1].Follow < 0)
                return pos - 1;
        }
        return -1;
    }

    // ---- input ----

    /// Handles one key press.
    static void Key(int k, int mods)
    {
        bool ctrl = (mods & ModCtrl) != 0;
        bool shift = (mods & ModShift) != 0;
        if (_renaming)
        {
            _RenameKey(k);
            return;
        }
        if (ctrl)
        {
            if (k == 'S')
                _Save();
            else if (k == 'Z')
            {
                _Undo(_undo, _redo);
            }
            else if (k == 'Y')
            {
                _Undo(_redo, _undo);
            }
            else if (k == 'C')
                _CopyBar(shift);
            else if (k == 'V')
                _PasteBar();
            return;
        }
        if (k == ' ')
            _TogglePlay();
        else if (k == KeyLeft)
            _SelectBar(_bar - 1);
        else if (k == KeyRight)
            _SelectBar(_bar + 1);
        else if (k == KeyHome)
            _SelectBar(0);
        else if (k == KeyEnd)
            _SelectBar(_songBars - 1);
        else if (k == KeyUp)
            _SelectTrack(_sel - 1);
        else if (k == KeyDown)
            _SelectTrack(_sel + 1);
        else if (k == KeyPageUp)
            _SetTopNote(_topNote + 12);
        else if (k == KeyPageDown)
            _SetTopNote(_topNote - 12);
        else if (k == KeyDelete)
            _ClearBar(shift);
        else if (k == KeyF2)
            _StartRename();
        else if (k == 'M')
            _ToggleMute(_sel);
        else if (k == 'S')
            Music.SetSolo(_soloTrack == _sel ? -1 : _sel);
        else if (k == 'L')
        {
            _loopView = !_loopView;
            _UpdateLoop();
        }
        else if (k == KeyEscape)
            _quit = MayQuit();
    }

    static void _StartRename()
    {
        _Touch();
        _renaming = true;
        _Say("TYPE THE NAME OF THE TRACK, THEN ENTER");
    }

    static void _RenameKey(int k)
    {
        var t = _tracks[_sel];
        if (k == KeyEnter || k == KeyPadEnter || k == KeyEscape)
        {
            _renaming = false;
            if (t.Name.Length == 0)
                t.Name = "TRACK " + (_sel + 1).ToString();
        }
        else if (k == KeyBackspace)
        {
            if (t.Name.Length > 0)
                t.Name = t.Name[..t.Name.Length - 1].ToString();
        }
        else if (((k >= 'A' && k <= 'Z') || (k >= '0' && k <= '9') || k == ' ' || k == '-') && t.Name.Length < _NameLength)
        {
            var letter = new uint8[1];
            letter[0] = (uint8)k;
            t.Name += string.FromBytes(letter);
        }
        _tracks[_sel] = t;
    }

    /// Handles a mouse button going down or up.
    static void MouseButton(int button, bool pressed, int mods)
    {
        _shiftDown = (mods & ModShift) != 0;
        if (button == 1)
            _mouseLeft = pressed;
        else if (button == 2)
            _mouseRight = pressed;
        else
            return;
        if (pressed)
            _click = button;
        else
            _drag = _Drag.None;
    }

    /// Handles the mouse moving to a pixel of the screen.
    static void MouseMove(int x, int y)
    {
        _mouseX = x;
        _mouseY = y;
    }

    /// Handles the mouse wheel: `steps` is 1 for up, -1 for down.
    static void Scroll(int steps, int mods)
    {
        _shiftDown = (mods & ModShift) != 0;
        _wheel += steps;
    }

    // ---- self test ----

    static bool _Check(string what, bool ok)
    {
        Console.WriteLine((ok ? "ok    " : "FAILED ") + what);
        return ok;
    }

    // a click or drag in the grid of the selected track, as the mouse would do it
    static void _TestDrag(int button, int fromStep, int toStep, int note)
    {
        int y = _GridY + (_topNote - note) * _RowH + 5;
        MouseMove(_GridX + (fromStep - _viewBar * StepsPerBar) * _StepW + 5, y);
        MouseButton(button, true, 0);
        Frame(0.016);
        MouseMove(_GridX + (toStep - _viewBar * StepsPerBar) * _StepW + 5, y);
        Frame(0.016);
        MouseButton(button, false, 0);
        Frame(0.016);
    }

    /// Edits the loaded song the way the mouse and the keyboard would and checks the result; returns the number of
    /// failed checks. Nothing is saved.
    static int SelfTest()
    {
        int failed = 0;
        string before = Song.ToText();
        _Apply(before);
        if (!_Check("a song that is written and read again is the same", Song.ToText() == before))
            failed += 1;

        _SelectTrack(0);
        _SelectBar(1);
        _viewBar = 0;
        int a = _topNote - 5;
        var old = _Copy(_tracks[0].Notes);
        // the step behind the new note stays, unless it held a note that the new one cut off
        int after = old[24] == NoteHold ? NoteOff : old[24];
        _TestDrag(1, 20, 23, a);
        var n = _tracks[0].Notes;
        if (!_Check("dragging places a note of 4 steps", n[20] == a && n[21] == NoteHold && n[22] == NoteHold && n[23] == NoteHold && n[24] == after))
            failed += 1;
        _TestDrag(2, 22, 22, a);
        n = _tracks[0].Notes;
        if (!_Check("a right click removes the whole note", n[20] == NoteOff && n[21] == NoteOff && n[22] == NoteOff && n[23] == NoteOff))
            failed += 1;
        Key('Z', ModCtrl);
        Key('Z', ModCtrl);
        if (!_Check("undoing twice restores the song", Song.ToText() == before))
            failed += 1;
        Key('Y', ModCtrl);
        if (!_Check("redo brings the note back", _tracks[0].Notes[20] == a))
            failed += 1;
        Key('Z', ModCtrl);

        _SelectBar(0);
        Key('C', ModCtrl);
        _SelectBar(3);
        Key('V', ModCtrl);
        n = _tracks[0].Notes;
        bool same = true;
        for (var s = 0; s < StepsPerBar; s += 1)
        {
            same = same && n[3 * StepsPerBar + s] == n[s];
        }
        if (!_Check("a copied bar is pasted into another bar", same))
            failed += 1;
        Key(KeyDelete, 0);
        bool empty = true;
        for (var s = 0; s < StepsPerBar; s += 1)
        {
            empty = empty && _tracks[0].Notes[3 * StepsPerBar + s] == NoteOff;
        }
        if (!_Check("Del clears the bar", empty))
            failed += 1;

        int tracks = _tracks.Count();
        // what the second track follows must survive adding and deleting a track behind it
        int follow = _tracks.Count() > 1 ? _tracks[1].Follow : -1;
        _AddTrack(false);
        if (tracks >= MaxTracks)
        {
            // a song that is full has no room for the track this test adds and deletes again
            if (!_Check("a full song refuses another track", _tracks.Count() == tracks))
                failed += 1;
        }
        else
        {
            _ChangeParam(1, 10);
            if (!_Check("a new track is added and its volume changes", _tracks.Count() == tracks + 1 && _tracks[_sel].Sound.Volume == 0.2))
                failed += 1;
            _DeleteTrack();
            _SelectTrack(1);
            if (!_Check("adding and deleting a track leaves the other tracks as they are", _tracks.Count() == tracks && (tracks < 2 || _tracks[1].Follow == follow)))
                failed += 1;
        }
        Song.SetBars(_songBars + 2);
        _SongChanged();
        if (!_Check("more bars make every track longer", _tracks[0].Notes.Length == Song.Steps()))
            failed += 1;
        return failed;
    }

    // ---- drawing and mouse ----

    static bool _In(int x, int y, int w, int h)
    {
        return _mouseX >= x && _mouseX < x + w && _mouseY >= y && _mouseY < y + h;
    }

    // draws a button and tells whether it was clicked
    static bool _Button(int x, int y, int w, int h, string label, bool active)
    {
        bool hover = _In(x, y, w, h);
        uint32 back = active ? Gfx.Rgb(150, 105, 35) : hover ? Gfx.Rgb(64, 60, 92) : Gfx.Rgb(40, 38, 60);
        Gfx.FillRect(x, y, w, h, back);
        Gfx.FrameRect(x, y, w, h, 1, hover ? Gfx.Rgb(255, 205, 90) : Gfx.Rgb(96, 90, 130));
        Gfx.Text(x + (w - Gfx.TextWidth(label, 2)) / 2, y + (h - Gfx.TextHeight(2)) / 2, label, 2, Gfx.Rgb(235, 232, 245));
        return hover && _click == 1;
    }

    /// Advances the editor by `dt` seconds and draws it.
    static void Frame(double dt)
    {
        _now += dt;
        // the view follows the music
        if (Music.IsPlaying() && !_loopView)
        {
            int bar = Music.Position() / StepsPerBar;
            if (bar < _viewBar || bar >= _viewBar + _ViewBars)
                _viewBar = Math.Clamp(bar, 0, Math.Max(0, _songBars - _ViewBars));
        }
        Gfx.FillRect(0, 0, ScreenW, ScreenH, Gfx.Rgb(20, 19, 32));
        _DrawTop();
        _DrawTracks();
        _DrawParams();
        _DrawRoll();
        _DrawOverview();
        _DrawStatus();
        _click = 0;
        _wheel = 0;
    }

    static void _DrawTop()
    {
        Gfx.FillRect(0, 0, ScreenW, 44, Gfx.Rgb(30, 28, 48));
        Gfx.Text(12, 15, "MUSIC EDITOR", 2, Gfx.Rgb(255, 205, 90));
        if (_Button(170, 8, 76, 28, Music.IsPlaying() ? "STOP" : "PLAY", Music.IsPlaying()))
            _TogglePlay();
        if (_Button(252, 8, 70, 28, _dirty ? "SAVE*" : "SAVE", false))
            _Save();
        if (_Button(328, 8, 60, 28, "UNDO", false))
            _Undo(_undo, _redo);
        if (_Button(394, 8, 60, 28, "REDO", false))
            _Undo(_redo, _undo);

        int step = _shiftDown ? 10 : 1;
        Gfx.Text(468, 15, "BPM", 2, Gfx.Rgb(170, 160, 200));
        int bpm = _songBpm;
        if (_Button(510, 8, 22, 28, "-", false))
            bpm -= step;
        if (_Button(578, 8, 22, 28, "+", false))
            bpm += step;
        if (_In(510, 8, 90, 28))
            bpm += _wheel;
        bpm = Math.Clamp(bpm, 40, 240);
        if (bpm != _songBpm)
        {
            _Touch();
            _songBpm = bpm;
            _SongChanged();
        }
        Gfx.Text(555 - Gfx.TextWidth(_songBpm.ToString(), 2) / 2, 15, _songBpm.ToString(), 2, Gfx.Rgb(235, 232, 245));

        Gfx.Text(614, 15, "BARS", 2, Gfx.Rgb(170, 160, 200));
        int bars = _songBars;
        if (_Button(668, 8, 22, 28, "-", false))
            bars -= 1;
        if (_Button(724, 8, 22, 28, "+", false))
            bars += 1;
        bars = Math.Clamp(bars, 1, MaxBars);
        if (bars != _songBars)
        {
            _Touch();
            Song.SetBars(bars);
            _SongChanged();
        }
        Gfx.Text(707 - Gfx.TextWidth(_songBars.ToString(), 2) / 2, 15, _songBars.ToString(), 2, Gfx.Rgb(235, 232, 245));

        if (_Button(760, 8, 190, 28, _loopView ? "LOOP: 2 BARS" : "LOOP: SONG", _loopView))
        {
            _loopView = !_loopView;
            _UpdateLoop();
        }
    }

    static void _DrawTracks()
    {
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            var track = _tracks[t];
            int y = _TrackY + t * _TrackRowH;
            if (t == _sel)
                Gfx.FillRect(4, y - 1, _LeftW - 4, _TrackRowH - 2, Gfx.Rgb(52, 48, 80));
            if (_Button(8, y, 22, 20, "M", track.Muted))
                _ToggleMute(t);
            if (_Button(32, y, 22, 20, "S", _soloTrack == t))
                Music.SetSolo(_soloTrack == t ? -1 : t);
            Gfx.FillRect(58, y, 4, 20, _TrackColors[t % _TrackColors.Length]);
            string name = track.Name;
            // a blinking cursor while the name is typed
            if (_renaming && t == _sel && (int)(_now * 3.0) % 2 == 0)
                name += "|";
            Gfx.Text(68, y + 3, name, 2, track.Muted ? Gfx.Rgb(120, 115, 140) : Gfx.Rgb(235, 232, 245));
            if (_click == 1 && _In(56, y, _LeftW - 56, _TrackRowH - 2))
                _SelectTrack(t);
        }
        if (_Button(8, _TrackButtonsY, 50, 24, "NEW", false))
            _AddTrack(false);
        if (_Button(62, _TrackButtonsY, 50, 24, "DUP", false))
            _AddTrack(true);
        if (_Button(116, _TrackButtonsY, 50, 24, "DEL", false))
            _DeleteTrack();
        if (_Button(170, _TrackButtonsY, 50, 24, "NAME", _renaming))
            _StartRename();
    }

    static void _DrawParams()
    {
        var track = _tracks[_sel];
        int step = _shiftDown ? 10 : 1;
        for (var p = 0; p < _ParamNames.Length; p += 1)
        {
            int y = _ParamY + p * _ParamRowH;
            bool hover = _In(4, y - 2, _LeftW, _ParamRowH);
            if (hover)
                Gfx.FillRect(4, y - 2, _LeftW, _ParamRowH, Gfx.Rgb(36, 34, 56));
            Gfx.Text(8, y + 1, _ParamNames[p], 2, Gfx.Rgb(170, 160, 200));
            Gfx.Text(98, y + 1, _ParamText(track, p), 2, Gfx.Rgb(235, 232, 245));
            int delta = 0;
            if (_Button(178, y - 1, 20, 17, "-", false))
                delta = -step;
            if (_Button(200, y - 1, 20, 17, "+", false))
                delta = step;
            if (hover && _wheel != 0)
                delta = _wheel * step;
            if (delta != 0)
            {
                _ChangeParam(p, delta);
                track = _tracks[_sel];
            }
        }
    }

    static bool _IsBlackKey(int note)
    {
        int n = note % 12;
        return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
    }

    // the notes of a track in the visible part of the grid
    static void _DrawNotes(int[] notes, int transpose, uint32 color, bool ghost)
    {
        int first = _viewBar * StepsPerBar;
        int last = Math.Min(first + _ViewBars * StepsPerBar, notes.Length);
        for (var s = 0; s < last; s += 1)
        {
            if (notes[s] <= 0)
                continue;
            int len = Song.NoteLength(notes, s);
            int row = _topNote - (notes[s] + transpose);
            if (s + len <= first || row < 0 || row >= _Rows)
                continue;
            int x0 = _GridX + Math.Max(0, s - first) * _StepW;
            int x1 = _GridX + (Math.Min(s + len, last) - first) * _StepW;
            int y = _GridY + row * _RowH;
            if (ghost)
            {
                Gfx.BlendRect(x0 + 1, y + 3, x1 - x0 - 2, _RowH - 6, color, 90);
                continue;
            }
            Gfx.FillRect(x0 + 1, y + 1, x1 - x0 - 2, _RowH - 2, color);
            // a bright edge where the note starts
            if (s >= first)
                Gfx.FillRect(x0 + 1, y + 1, 3, _RowH - 2, Gfx.Rgb(255, 255, 255));
        }
    }

    static void _DrawRoll()
    {
        int firstStep = _viewBar * StepsPerBar;
        int steps = Math.Min(_ViewBars, _songBars - _viewBar) * StepsPerBar;
        int width = steps * _StepW;

        // the bar numbers; a click selects the bar
        for (var b = 0; b < steps / StepsPerBar; b += 1)
        {
            int x = _GridX + b * StepsPerBar * _StepW;
            int w = StepsPerBar * _StepW;
            bool selected = _viewBar + b == _bar;
            Gfx.FillRect(x, _HeaderY, w - 1, 16, selected ? Gfx.Rgb(110, 80, 30) : Gfx.Rgb(34, 32, 54));
            Gfx.Text(x + 6, _HeaderY + 1, "BAR " + (_viewBar + b + 1).ToString(), 2, selected ? Gfx.Rgb(255, 225, 150) : Gfx.Rgb(170, 160, 200));
            if (_click == 1 && _In(x, _HeaderY, w, 16))
                _SelectBar(_viewBar + b);
        }

        // the keys and the rows
        for (var r = 0; r < _Rows; r += 1)
        {
            int note = _topNote - r;
            int y = _GridY + r * _RowH;
            bool black = _IsBlackKey(note);
            bool hoverKey = _In(_KeysX, y, _GridX - _KeysX, _RowH);
            Gfx.FillRect(_KeysX, y, _GridX - _KeysX - 2, _RowH - 1, hoverKey ? Gfx.Rgb(255, 205, 90) : black ? Gfx.Rgb(30, 28, 40) : Gfx.Rgb(200, 196, 214));
            Gfx.Text(_KeysX + 4, y + 2, Song.NoteName(note), 1, black && !hoverKey ? Gfx.Rgb(170, 165, 190) : Gfx.Rgb(20, 18, 30));
            if (hoverKey && _click == 1)
            {
                _lastNote = note;
                Music.Preview(note + _tracks[_sel].Transpose, _tracks[_sel].Sound, 0.4);
            }
            uint32 back = black ? Gfx.Rgb(26, 25, 40) : Gfx.Rgb(34, 33, 52);
            if (note % 12 == 0)
                back = Gfx.Rgb(44, 42, 66);
            Gfx.FillRect(_GridX, y, width, _RowH - 1, back);
        }
        int selX = _GridX + (_bar - _viewBar) * StepsPerBar * _StepW;
        if (_bar >= _viewBar && _bar < _viewBar + _ViewBars)
            Gfx.BlendRect(selX, _GridY, StepsPerBar * _StepW, _GridH, Gfx.Rgb(255, 205, 90), 12);
        for (var s = 0; s <= steps; s += 1)
        {
            uint32 line = s % StepsPerBar == 0 ? Gfx.Rgb(150, 140, 190) : s % 4 == 0 ? Gfx.Rgb(78, 74, 108) : Gfx.Rgb(46, 44, 68);
            Gfx.FillRect(_GridX + s * _StepW, _GridY, 1, _GridH, line);
        }

        // the other tracks behind, the selected one in front
        var track = _tracks[_sel];
        int source = _Source();
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            // muted tracks would only clutter the grid
            if (t != source && _tracks[t].Follow < 0 && !_tracks[t].Muted)
                _DrawNotes(_tracks[t].Notes, 0, _TrackColors[t % _TrackColors.Length], true);
        }
        Gfx.SetClip(_GridX, _GridY, width, _GridH);
        _DrawNotes(_tracks[source].Notes, source == _sel ? 0 : track.Transpose, _TrackColors[_sel % _TrackColors.Length], false);
        Gfx.ResetClip();

        if (Music.IsPlaying())
        {
            int pos = Music.Position() - firstStep;
            if (pos >= 0 && pos < steps)
                Gfx.FillRect(_GridX + pos * _StepW, _GridY, 2, _GridH, Gfx.Rgb(255, 255, 255));
        }
        if (track.Follow >= 0)
            Gfx.Text(_GridX + 8, _GridY + _GridH - 20, "THIS TRACK PLAYS THE NOTES OF TRACK " + (track.Follow + 1).ToString() + ": EDIT THEM THERE", 2, Gfx.Rgb(255, 205, 90));

        _RollMouse(firstStep, steps, track.Follow < 0);
    }

    static void _RollMouse(int firstStep, int steps, bool editable)
    {
        bool inside = _In(_GridX, _GridY, steps * _StepW, _GridH);
        if (_In(_KeysX, _HeaderY, _GridX - _KeysX + _GridW, _GridY + _GridH - _HeaderY) && _wheel != 0)
        {
            // the wheel scrolls the notes, with Shift the bars
            if (_shiftDown)
                _SelectBar(_bar - _wheel);
            else
                _SetTopNote(_topNote + _wheel * 3);
        }
        int step = firstStep + Math.Clamp((_mouseX - _GridX) / _StepW, 0, steps - 1);
        int note = _topNote - Math.Clamp((_mouseY - _GridY) / _RowH, 0, _Rows - 1);
        if (inside && _drag == _Drag.None)
        {
            int x = _GridX + (step - firstStep) * _StepW;
            int y = _GridY + (_topNote - note) * _RowH;
            Gfx.FrameRect(x, y, _StepW + 1, _RowH, 1, Gfx.Rgb(255, 205, 90));
            Gfx.Text(_GridX + steps * _StepW - 40, _HeaderY + 5, Song.NoteName(note), 1, Gfx.Rgb(255, 225, 150));
        }
        if (!editable)
            return;
        var notes = _tracks[_sel].Notes;
        if (inside && _click == 1)
        {
            _Touch();
            _drag = _Drag.Place;
            _dragStep = step;
            _dragNote = note;
            _dragBackup = _Copy(notes);
            _lastNote = note;
            Music.Preview(note + _tracks[_sel].Transpose, _tracks[_sel].Sound, 0.3);
        }
        else if (inside && _click == 2)
        {
            _drag = _Drag.Erase;
            _dragChanged = false;
        }
        if (_drag == _Drag.Place && _mouseLeft)
        {
            // dragging to the right makes the note longer; everything else is as it was before the click
            for (var i = 0; i < notes.Length; i += 1)
            {
                notes[i] = _dragBackup[i];
            }
            _Place(notes, _dragStep, Math.Max(1, step - _dragStep + 1), _dragNote);
            _Tidy(notes);
        }
        else if (_drag == _Drag.Erase && _mouseRight && inside)
            _Erase(step, note);
    }

    // the whole song: one row per track, one cell per bar
    static void _DrawOverview()
    {
        int cell = Math.Min(40, _GridW / _songBars);
        int playBar = Music.IsPlaying() ? Music.Position() / StepsPerBar : -1;
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            int y = _OverviewY + t * _OverviewRowH;
            var track = _tracks[t];
            var notes = _tracks[track.Follow >= 0 ? track.Follow : t].Notes;
            uint32 color = _TrackColors[t % _TrackColors.Length];
            if (t == _sel)
                Gfx.FillRect(_KeysX, y, _GridX - _KeysX - 2, _OverviewRowH - 1, color);
            for (var b = 0; b < _songBars; b += 1)
            {
                bool any = false;
                for (var s = 0; s < StepsPerBar; s += 1)
                {
                    any = any || notes[b * StepsPerBar + s] > 0;
                }
                uint32 fill = any ? Gfx.Scale(color, track.Muted ? 80 : t == _sel ? 256 : 150) : Gfx.Rgb(30, 29, 46);
                Gfx.FillRect(_GridX + b * cell, y, cell - 1, _OverviewRowH - 1, fill);
            }
        }
        int height = _tracks.Count() * _OverviewRowH;
        // the bars shown in the grid, the selected bar and the bar that plays
        Gfx.FillRect(_GridX + _viewBar * cell, _OverviewY + height + 1, Math.Min(_ViewBars, _songBars) * cell - 1, 2, Gfx.Rgb(170, 160, 200));
        Gfx.FrameRect(_GridX + _bar * cell - 1, _OverviewY - 1, cell + 1, height + 1, 1, Gfx.Rgb(255, 205, 90));
        if (playBar >= 0)
            Gfx.FrameRect(_GridX + playBar * cell - 1, _OverviewY - 1, cell + 1, height + 1, 1, Gfx.Rgb(255, 255, 255));
        if (_click == 1 && _In(_GridX, _OverviewY, _songBars * cell, height))
        {
            _SelectTrack((_mouseY - _OverviewY) / _OverviewRowH);
            _SelectBar((_mouseX - _GridX) / cell);
            _viewBar = Math.Clamp(_bar, 0, Math.Max(0, _songBars - _ViewBars));
            _UpdateLoop();
        }
    }

    static void _DrawStatus()
    {
        uint32 dim = Gfx.Rgb(130, 124, 160);
        Gfx.Text(8, _HintY, "GRID: CLICK = NOTE, DRAG RIGHT = LONGER, RIGHT CLICK = DELETE, WHEEL = SCROLL (SHIFT: BARS)   PIANO KEYS: LISTEN   SHIFT WITH +/-: 10 STEPS   ESC: QUIT", 1, dim);
        Gfx.Text(8, _HintY + 12, "SPACE: PLAY   ARROWS: BAR / TRACK   CTRL+C / V: COPY / PASTE BAR (SHIFT+C: ALL TRACKS)   DEL: CLEAR BAR   CTRL+Z / Y: UNDO / REDO   CTRL+S: SAVE", 1, dim);
        if (_status.Length > 0 && _now - _statusTime < _StatusSeconds)
            Gfx.Text(8, _StatusY, _status, 2, Gfx.Rgb(170, 255, 170));
        else
            Gfx.Text(8, _StatusY, _path + (_dirty ? " *" : ""), 2, dim);
    }
}
