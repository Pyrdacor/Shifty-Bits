//! A small software synthesizer: the background music (the song of song.csh, a loop) and the sound effects. It
//! renders mono float samples; the platform layer sends them to the sound card (winmm) or the browser (Web Audio).

namespace ShiftyBits;

using System;

/// The sound effects of the game.
enum Sfx : uint8
{
    Roll,
    Lock,
    Clear,
    LevelUp,
    GameOver,
}

const int _VoiceCount = 32;

// the song built into the program; the editor and the desktop game can replace it by a file
const ReadOnlySlice<string> _SongLines = embed_lines("../song.txt");

// ---- instruments of the sound effects ----

Instrument _Tick = Instrument { Wave = Wave.Triangle, Volume = 0.07, Attack = 0.001, Decay = 0.03, Release = 0.02, IsSfx = true };
Instrument _Thud = Instrument { Wave = Wave.Sine, Volume = 0.32, Attack = 0.001, Decay = 0.09, Release = 0.05, SweepTo = 0.4, IsSfx = true };
Instrument _Crunch = Instrument { Wave = Wave.Noise, Volume = 0.05, Attack = 0.001, Decay = 0.025, Release = 0.02, IsSfx = true };
Instrument _Chime = Instrument { Wave = Wave.Sine, Volume = 0.13, Attack = 0.003, Decay = 0.35, Release = 0.1, IsSfx = true };
Instrument _ChimeShine = Instrument { Wave = Wave.Triangle, Volume = 0.035, Attack = 0.003, Decay = 0.2, Release = 0.1, IsSfx = true };
Instrument _Fanfare = Instrument { Wave = Wave.Pulse, Volume = 0.06, Attack = 0.003, Decay = 0.3, Release = 0.1, IsSfx = true };
Instrument _Doom = Instrument { Wave = Wave.Square, Volume = 0.06, Attack = 0.003, Decay = 0.4, Release = 0.1, IsSfx = true };
Instrument _DoomBass = Instrument { Wave = Wave.Triangle, Volume = 0.15, Attack = 0.003, Decay = 0.4, Release = 0.1, IsSfx = true };

/// One sounding note.
struct _Voice
{
    bool Active;
    Instrument Sound;
    double Freq;
    double Sweep;       // the frequency is multiplied by this every sample
    double Phase;
    double Env;
    int Stage;          // 0 attack, 1 decay/sustain, 2 release
    double AttackStep;
    double DecayMul;
    double ReleaseMul;
    int Gate;           // samples until the release starts
    double VibPhase;
}

/// A note waiting to be played (sound effects made of several notes).
struct _Pending
{
    int Delay;
    int Midi;
    Instrument Sound;
}

int _rate = 44100;
_Voice[] _voices = [];
List<_Pending> _pending = List<_Pending>.Create();
double[] _sineTable = [];
float[] _echo = [];
int _echoPos;
uint32 _noise = 22222;
double _lowpass;

bool _musicOn = true;
bool _soundsOn = true;
bool _musicRunning;
bool _musicPaused;
double _musicGain;
double _musicTarget;
int _step;
double _stepPos;            // samples until the next step
double _bpm = 100.0;
// the steps the song loops over: the whole song, or a part of it in the editor
int _loopStart;
int _loopEnd;
// the only track that plays (-1: all that are not muted); for the editor
int _soloTrack = -1;

/// The synthesizer and sequencer.
struct Music
{
    /// Prepares the synthesizer for the given sample rate.
    static void Init(int rate)
    {
        _rate = rate;
        _voices = new _Voice[_VoiceCount];
        _sineTable = new double[1024];
        for (var i = 0; i < 1024; i += 1)
        {
            _sineTable[i] = Math.Sin(i * Math.PI * 2.0 / 1024.0);
        }
        _echo = new float[rate * 3 / 8];
        LoadSong(_SongLines);
    }

    /// Replaces the song (see `Song.Load`) and plays it as a whole.
    static void LoadSong(ReadOnlySlice<string> lines)
    {
        Song.Load(lines);
        SongChanged();
    }

    /// Adapts the player after the length or the tempo of the song changed.
    static void SongChanged()
    {
        _loopStart = 0;
        _loopEnd = Song.Steps();
        _step = _step % _loopEnd;
        _bpm = _songBpm;
    }

    /// Plays only the steps from `start` to `end` (exclusive) in a loop.
    static void SetLoop(int start, int end)
    {
        _loopStart = Math.Clamp(start, 0, Song.Steps() - 1);
        _loopEnd = Math.Clamp(end, _loopStart + 1, Song.Steps());
    }

    /// Lets only one track play (-1: all that are not muted).
    static void SetSolo(int track)
    {
        _soloTrack = track;
    }

    /// Starts the music at `step` at once, without fading in.
    static void PlayFrom(int step)
    {
        _step = Math.Clamp(step, _loopStart, _loopEnd - 1);
        _stepPos = 0.0;
        _musicRunning = true;
        _musicPaused = false;
        _musicTarget = 1.0;
        _musicGain = 1.0;
    }

    /// Stops the music at once; notes that sound ring out.
    static void Halt()
    {
        _musicRunning = false;
        for (var v = 0; v < _VoiceCount; v += 1)
        {
            var voice = _voices[v];
            if (voice.Active && !voice.Sound.IsSfx)
            {
                voice.Gate = 0;
                _voices[v] = voice;
            }
        }
    }

    /// Whether the music is running.
    static bool IsPlaying()
    {
        return _musicRunning;
    }

    /// The step that is played next.
    static int Position()
    {
        return _step;
    }

    /// Plays one note of an instrument for `seconds`, also while the music is stopped (the editor's preview).
    static void Preview(int midi, Instrument sound, double seconds)
    {
        // as a sound effect, the note does not depend on the volume of the music
        sound.IsSfx = true;
        _Start(midi, sound, (int)(seconds * _rate));
    }

    /// Starts the music from the first bar, fading in.
    static void Start()
    {
        _step = _loopStart;
        _stepPos = 0.0;
        _musicRunning = true;
        _musicPaused = false;
        _musicTarget = 1.0;
        _musicGain = 0.0;
    }

    /// Fades the music out.
    static void Stop()
    {
        _musicTarget = 0.0;
    }

    /// Pauses or resumes the music.
    static void SetPaused(bool paused)
    {
        _musicPaused = paused;
    }

    /// Switches the music on or off (the sound effects stay).
    static void Toggle()
    {
        _musicOn = !_musicOn;
    }

    /// Switches the music on or off.
    static void SetOn(bool on)
    {
        _musicOn = on;
    }

    /// Switches the sound effects on or off (the music stays).
    static void SetSoundsOn(bool on)
    {
        _soundsOn = on;
    }

    /// Whether the sound effects are switched on.
    static bool SoundsOn()
    {
        return _soundsOn;
    }

    /// Whether the music is switched on.
    static bool IsOn()
    {
        return _musicOn;
    }

    /// Faster music on higher levels.
    static void SetLevel(int level)
    {
        _bpm = _songBpm + Math.Min(level - 1, 10) * 3.0;
    }

    /// Plays a sound effect; `strength` makes clears sound bigger (runs and chain step).
    static void Play(Sfx sfx, int strength)
    {
        if (!_soundsOn)
            return;
        switch (sfx)
        {
            case Sfx.Roll:
                _Note(91, _Tick);
                break;
            case Sfx.Lock:
                _Note(45, _Thud);
                _Note(60, _Crunch);
                break;
            case Sfx.Clear:
            {
                // a rising chime that starts higher the bigger the clear
                int root = 69 + Math.Min(strength - 1, 4) * 2;
                ReadOnlySlice<int> intervals = [0, 3, 7, 12, 15];
                for (var i = 0; i < intervals.Length; i += 1)
                {
                    _Later(i * 55, root + intervals[i], _Chime);
                    _Later(i * 55, root + intervals[i] + 12, _ChimeShine);
                }
                break;
            }
            case Sfx.LevelUp:
            {
                ReadOnlySlice<int> notes = [69, 72, 76, 81, 84, 88];
                for (var i = 0; i < notes.Length; i += 1)
                {
                    _Later(i * 70, notes[i], _Fanfare);
                }
                break;
            }
            case Sfx.GameOver:
            {
                ReadOnlySlice<int> notes = [64, 60, 57, 52, 45];
                for (var i = 0; i < notes.Length; i += 1)
                {
                    var doom = _Doom;
                    var bass = _DoomBass;
                    // the last note rings out
                    if (i == notes.Length - 1)
                    {
                        doom.Decay = 1.2;
                        bass.Decay = 1.2;
                    }
                    _Later(i * 220, notes[i], doom);
                    _Later(i * 220, notes[i] - 12, bass);
                }
                break;
            }
        }
    }

    /// Renders `count` mono samples into `out`.
    static unsafe void Render(float* out, int count)
    {
        double gainStep = 1.0 / (0.8 * _rate);
        for (var i = 0; i < count; i += 1)
        {
            if (_musicRunning && !_musicPaused)
            {
                _stepPos -= 1.0;
                if (_stepPos <= 0.0)
                {
                    _stepPos += _rate * 60.0 / _bpm / 4.0;
                    _PlayStep(_step);
                    _step += 1;
                    if (_step >= _loopEnd)
                        _step = _loopStart;
                }
            }
            _UpdatePending();
            if (_musicGain < _musicTarget)
                _musicGain = Math.Min(_musicTarget, _musicGain + gainStep);
            else if (_musicGain > _musicTarget)
                _musicGain = Math.Max(_musicTarget, _musicGain - gainStep);
            if (_musicGain <= 0.0 && _musicTarget <= 0.0)
                _musicRunning = false;

            double music = 0.0;
            double sfx = 0.0;
            double send = 0.0;
            for (var v = 0; v < _VoiceCount; v += 1)
            {
                if (!_voices[v].Active)
                    continue;
                double s = _Sample(v);
                if (_voices[v].Sound.IsSfx)
                    sfx += s;
                else
                {
                    music += s;
                    if (_voices[v].Sound.Echo)
                        send += s;
                }
            }
            // a simple echo for the instruments that ask for it
            double echoed = _echo[_echoPos];
            _echo[_echoPos] = (float)(send + echoed * 0.38);
            _echoPos = (_echoPos + 1) % _echo.Length;
            music += echoed * 0.35;

            double musicGain = _musicOn && !_musicPaused ? _musicGain : 0.0;
            _lowpass += (music * musicGain + sfx - _lowpass) * 0.45;
            // soft clipping
            double x = _lowpass * 0.9;
            out[i] = (float)(x / (1.0 + Math.Abs(x)));
        }
    }

    // ---- the song ----

    // starts the notes of all tracks at `step`
    static void _PlayStep(int step)
    {
        double stepSamples = 60.0 / _bpm / 4.0 * _rate;
        for (var t = 0; t < _tracks.Count(); t += 1)
        {
            var track = _tracks[t];
            // a track that follows another one plays that one's notes with its own instrument
            int source = track.Follow >= 0 ? track.Follow : t;
            if (_soloTrack >= 0 ? _soloTrack != t && _soloTrack != source : track.Muted)
                continue;
            var notes = _tracks[source].Notes;
            if (step >= notes.Length || notes[step] <= 0)
                continue;
            int gate = (int)(Song.NoteLength(notes, step) * stepSamples * track.Gate);
            _Start(notes[step] + track.Transpose, track.Sound, gate);
        }
    }

    // ---- voices ----

    static void _Later(int delayMs, int midi, Instrument sound)
    {
        _pending.Add(_Pending { Delay = delayMs * _rate / 1000, Midi = midi, Sound = sound });
    }

    static void _UpdatePending()
    {
        for (var i = _pending.Count() - 1; i >= 0; i -= 1)
        {
            var p = _pending[i];
            if (p.Delay <= 0)
            {
                _Note(p.Midi, p.Sound);
                _pending.RemoveAt(i);
            }
            else
            {
                p.Delay -= 1;
                _pending[i] = p;
            }
        }
    }

    // starts a note of a sound effect: it is never released, it rings out with its decay
    static void _Note(int midi, Instrument sound)
    {
        _Start(midi, sound, int.MaxValue);
    }

    // starts a note on a free voice (or the quietest one); `gate` is the time the key is held, in samples
    static void _Start(int midi, Instrument sound, int gate)
    {
        int best = 0;
        double quietest = 10.0;
        for (var v = 0; v < _VoiceCount; v += 1)
        {
            if (!_voices[v].Active)
            {
                best = v;
                break;
            }
            double level = _voices[v].Env * _voices[v].Sound.Volume;
            if (level < quietest)
            {
                quietest = level;
                best = v;
            }
        }
        double samples = Math.Max(1.0, sound.Decay * _rate);
        _voices[best] = _Voice
        {
            Active = true, Sound = sound, Freq = 440.0 * Math.Pow(2.0, (midi - 69) / 12.0),
            Sweep = sound.SweepTo > 0.0 ? Math.Pow(sound.SweepTo, 1.0 / samples) : 1.0,
            AttackStep = 1.0 / Math.Max(1.0, sound.Attack * _rate),
            DecayMul = Math.Exp(-1.0 / samples),
            ReleaseMul = Math.Exp(-1.0 / Math.Max(1.0, sound.Release * _rate)),
            Gate = Math.Max(1, gate),
        };
    }

    static double _Sample(int v)
    {
        var voice = _voices[v];
        double freq = voice.Freq;
        if (voice.Sound.Vibrato > 0.0)
        {
            voice.VibPhase += 5.5 / _rate;
            if (voice.VibPhase >= 1.0)
                voice.VibPhase -= 1.0;
            freq *= 1.0 + voice.Sound.Vibrato * _sineTable[(int)(voice.VibPhase * 1024.0) & 1023];
        }
        voice.Phase += freq / _rate;
        if (voice.Phase >= 1.0)
            voice.Phase -= Math.Floor(voice.Phase);
        voice.Freq *= voice.Sweep;

        double p = voice.Phase;
        double s = 0.0;
        switch (voice.Sound.Wave)
        {
            case Wave.Sine:
                s = _sineTable[(int)(p * 1024.0) & 1023];
                break;
            case Wave.Triangle:
                s = 4.0 * Math.Abs(p - 0.5) - 1.0;
                break;
            case Wave.Pulse:
                s = p < 0.25 ? 0.8 : -0.8;
                break;
            case Wave.Square:
                s = p < 0.5 ? 0.6 : -0.6;
                break;
            case Wave.Noise:
                _noise = unchecked(_noise * 1664525u + 1013904223u);
                s = (double)(int)(_noise >> 16) / 32768.0 - 1.0;
                break;
        }

        // envelope
        double sustain = voice.Sound.Sustain;
        if (voice.Stage == 0)
        {
            voice.Env += voice.AttackStep;
            if (voice.Env >= 1.0)
            {
                voice.Env = 1.0;
                voice.Stage = 1;
            }
        }
        else if (voice.Stage == 1)
            voice.Env = sustain + (voice.Env - sustain) * voice.DecayMul;
        else
            voice.Env *= voice.ReleaseMul;
        // the release waits for the end of the attack: a note that is shorter than its attack would stay far below
        // its volume otherwise
        if (voice.Gate > 0)
            voice.Gate -= 1;
        if (voice.Gate <= 0 && voice.Stage == 1)
            voice.Stage = 2;
        if ((voice.Stage == 2 || sustain <= 0.0) && voice.Env < 0.0005 && voice.Stage > 0)
            voice.Active = false;

        _voices[v] = voice;
        return s * voice.Env * voice.Sound.Volume;
    }
}
