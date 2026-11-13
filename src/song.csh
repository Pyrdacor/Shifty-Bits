//! The song the synthesizer plays: tracks of notes on a grid of 16th notes, each with its own instrument. The song is
//! a text file (`song.txt`): the game embeds it, the music editor (tools/musiceditor) reads and writes it.

namespace ShiftyBits;

using System;

/// Steps (16th notes) per bar.
const int StepsPerBar = 16;
/// The longest song in bars.
const int MaxBars = 64;
/// The largest number of tracks.
const int MaxTracks = 12;
/// A step that holds the note before it.
const int NoteHold = 0;
/// A silent step.
const int NoteOff = -1;
/// The lowest note a track can play (C1).
const int LowestNote = 24;
/// The highest note a track can play (C8).
const int HighestNote = 108;

/// The waveform of an instrument.
enum Wave : uint8
{
    Sine,
    Triangle,
    Pulse,
    Square,
    Noise,
}

/// The names of the waveforms in the song file, in the order of `Wave`.
const ReadOnlySlice<string> WaveNames = ["sine", "triangle", "pulse", "square", "noise"];
const ReadOnlySlice<string> _NoteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

/// How a note sounds: waveform, volume and envelope (times in seconds).
struct Instrument
{
    Wave Wave;
    double Volume;
    double Attack;
    double Decay;
    /// Level held while the note is down (0: the note just decays).
    double Sustain;
    double Release;
    /// Depth of the vibrato, 0 for none.
    double Vibrato;
    /// The pitch falls to this factor during the decay (drums); 0 for none.
    double SweepTo;
    /// Sent to the echo.
    bool Echo;
    /// A sound effect: not affected by the music volume.
    bool IsSfx;
}

/// One voice of the song: an instrument and its notes.
struct Track
{
    string Name;
    Instrument Sound;
    /// The part of a note's length the key is held down (0 to 1); the rest is the release.
    double Gate;
    /// The track whose notes this one plays instead of its own (-1: none), for a second layer of the same melody.
    int Follow;
    /// Semitones added to every note.
    int Transpose;
    bool Muted;
    /// One entry per step: a MIDI note, `NoteHold` or `NoteOff`.
    int[] Notes;
}

int _songBpm = 100;
int _songBars = 16;
List<Track> _tracks = List<Track>.Create();

/// Reading, writing and changing the song.
struct Song
{
    /// The number of steps of the song.
    static int Steps()
    {
        return _songBars * StepsPerBar;
    }

    /// A new track with a plain instrument and no notes.
    static Track NewTrack(string name)
    {
        var notes = new int[Steps()];
        for (var i = 0; i < notes.Length; i += 1)
        {
            notes[i] = NoteOff;
        }
        return Track
        {
            Name = name, Gate = 0.9, Follow = -1, Notes = notes,
            Sound = Instrument { Wave = Wave.Triangle, Volume = 0.15, Attack = 0.005, Decay = 0.3, Sustain = 0.4, Release = 0.1 },
        };
    }

    /// Changes the length of the song; new bars are silent.
    static void SetBars(int bars)
    {
        _songBars = Math.Clamp(bars, 1, MaxBars);
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            var track = _tracks[t];
            var notes = new int[Steps()];
            for (var i = 0; i < notes.Length; i += 1)
            {
                notes[i] = i < track.Notes.Length ? track.Notes[i] : NoteOff;
            }
            track.Notes = notes;
            _tracks[t] = track;
        }
    }

    /// The length in steps of the note that starts at `step` of `notes` (0 if none starts there).
    static int NoteLength(int[] notes, int step)
    {
        if (notes[step] <= 0)
            return 0;
        int len = 1;
        while (step + len < notes.Length && notes[step + len] == NoteHold)
        {
            len += 1;
        }
        return len;
    }

    /// The step at which the note sounding at `step` starts (-1 if the step is silent).
    static int NoteStart(int[] notes, int step)
    {
        while (step > 0 && notes[step] == NoteHold)
        {
            step -= 1;
        }
        return notes[step] > 0 ? step : -1;
    }

    /// 73 -> "C#5".
    static string NoteName(int midi)
    {
        return _NoteNames[midi % 12] + (midi / 12 - 1).ToString();
    }

    /// "C#5" -> 73; `NoteOff` for anything else.
    static int NoteNumber(StringSlice name)
    {
        if (name.Length < 2)
            return NoteOff;
        const string letters = "C D EF G A B";
        int semitone = letters.IndexOf(name[0]);
        if (semitone < 0 || name[0] == ' ')
            return NoteOff;
        int pos = 1;
        if (name[pos] == '#')
        {
            semitone += 1;
            pos += 1;
        }
        if (pos >= name.Length || name[pos] < '0' || name[pos] > '9')
            return NoteOff;
        return Math.Clamp(((int)(name[pos] - '0') + 1) * 12 + semitone, LowestNote, HighestNote);
    }

    /// Replaces the song by the one in `lines` (the format of `ToText`). Unknown lines are skipped.
    static void Load(ReadOnlySlice<string> lines)
    {
        _songBpm = 100;
        _songBars = 16;
        _tracks = List<Track>.Create();
        // the bar the next line of notes belongs to, per track
        int bar = 0;
        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (line.Length == 0 || line[0] == '#')
                continue;
            int last = _tracks.Count() - 1;
            if (line[0] == '|')
            {
                if (last >= 0 && bar < _songBars)
                {
                    var track = _tracks[last];
                    _ReadBar(track.Notes, bar, line[1..]);
                    bar += 1;
                }
                continue;
            }
            int space = line.IndexOf(' ');
            if (space < 0)
                continue;
            var key = line[..space];
            var value = line[space + 1..].Trim();
            if (key == "track")
            {
                if (_tracks.Count() < MaxTracks)
                    _tracks.Add(NewTrack(value.ToString()));
                bar = 0;
                continue;
            }
            double number = 0.0;
            if (value.ParseDouble() is double parsed)
                number = parsed;
            if (key == "bpm")
                _songBpm = Math.Clamp((int)number, 40, 240);
            else if (key == "bars" && last < 0)
                _songBars = Math.Clamp((int)number, 1, MaxBars);
            if (last < 0)
                continue;
            var t = _tracks[last];
            if (key == "wave")
            {
                for (var w = 0; w < WaveNames.Length; w += 1)
                {
                    if (value == WaveNames[w])
                        t.Sound.Wave = (Wave)w;
                }
            }
            else if (key == "volume")
                t.Sound.Volume = number;
            else if (key == "attack")
                t.Sound.Attack = number;
            else if (key == "decay")
                t.Sound.Decay = number;
            else if (key == "sustain")
                t.Sound.Sustain = number;
            else if (key == "release")
                t.Sound.Release = number;
            else if (key == "vibrato")
                t.Sound.Vibrato = number;
            else if (key == "sweep")
                t.Sound.SweepTo = number;
            else if (key == "echo")
                t.Sound.Echo = number != 0.0;
            else if (key == "gate")
                t.Gate = number;
            else if (key == "transpose")
                t.Transpose = (int)number;
            else if (key == "muted")
                t.Muted = number != 0.0;
            else if (key == "follow")
                t.Follow = (int)number - 1;
            _tracks[last] = t;
        }
        // a track can only follow another one that has notes of its own
        for (var i = 0; i < _tracks.Count(); i += 1)
        {
            var t = _tracks[i];
            if (t.Follow == i || t.Follow >= _tracks.Count() || (t.Follow >= 0 && _tracks[t.Follow].Follow >= 0))
            {
                t.Follow = -1;
                _tracks[i] = t;
            }
        }
    }

    // one bar of notes: a note name starts a note, '-' holds it, '.' is silence
    static void _ReadBar(int[] notes, int bar, StringSlice text)
    {
        int s = 0;
        foreach (var token in text.Split(' '))
        {
            if (token.Length == 0)
                continue;
            if (s >= StepsPerBar)
                break;
            notes[bar * StepsPerBar + s] = token == "-" ? NoteHold : Song.NoteNumber(token);
            s += 1;
        }
    }

    /// The song as the text of a song file.
    static string ToText()
    {
        var sb = StringBuilder.Create();
        sb.Append("# Shifty Bits song: edit it with tools/musiceditor. The game embeds this file when it is built.\n");
        sb.Append("# A line of notes is one bar of 16 steps: a note name starts a note, '-' holds it, '.' is silence.\n");
        sb.Append("bpm " + _songBpm.ToString() + "\n");
        sb.Append("bars " + _songBars.ToString() + "\n");
        foreach (var t in _tracks)
        {
            sb.Append("\ntrack " + t.Name + "\n");
            sb.Append("wave " + WaveNames[(int)t.Sound.Wave] + "\n");
            sb.Append("volume " + Number(t.Sound.Volume) + "\n");
            sb.Append("attack " + Number(t.Sound.Attack) + "\n");
            sb.Append("decay " + Number(t.Sound.Decay) + "\n");
            sb.Append("sustain " + Number(t.Sound.Sustain) + "\n");
            sb.Append("release " + Number(t.Sound.Release) + "\n");
            sb.Append("vibrato " + Number(t.Sound.Vibrato) + "\n");
            sb.Append("sweep " + Number(t.Sound.SweepTo) + "\n");
            sb.Append("echo " + (t.Sound.Echo ? "1" : "0") + "\n");
            sb.Append("gate " + Number(t.Gate) + "\n");
            sb.Append("transpose " + t.Transpose.ToString() + "\n");
            sb.Append("muted " + (t.Muted ? "1" : "0") + "\n");
            // the number of the followed track, counted from 1; 0 for none
            sb.Append("follow " + (t.Follow + 1).ToString() + "\n");
            if (t.Follow >= 0)
                continue;
            for (var bar = 0; bar < _songBars; bar += 1)
            {
                sb.Append("|");
                for (var s = 0; s < StepsPerBar; s += 1)
                {
                    int note = t.Notes[bar * StepsPerBar + s];
                    sb.Append(" " + (note == NoteHold ? "-" : note < 0 ? "." : NoteName(note)));
                }
                sb.Append("\n");
            }
        }
        return sb.ToString();
    }

    /// A value with at most four decimals and no zeros at its end ("0.16").
    static string Number(double value)
    {
        string text = value.ToString("F4");
        int end = text.Length;
        while (end > 1 && text[end - 1] == '0')
        {
            end -= 1;
        }
        if (text[end - 1] == '.')
            end -= 1;
        return text[..end].ToString();
    }
}
