//! Sound output on Windows via winmm (waveOut): a few small buffers that are refilled by the synthesizer as soon as
//! the sound card has played them. Shared by the game and the music editor.

namespace ShiftyBits;

using System;

/// The sample rate of the sound output.
const int AudioRate = 44100;

const int _AudioBuffers = 6;
const int _AudioSamples = 1024;   // per buffer: about 23 ms
const uint32 _WhdrDone = 1;

/// WAVEFORMATEX of the Windows API.
struct _WaveFormat
{
    uint16 FormatTag;
    uint16 Channels;
    uint32 SamplesPerSec;
    uint32 AvgBytesPerSec;
    uint16 BlockAlign;
    uint16 BitsPerSample;
    uint16 Size;
}

/// WAVEHDR of the Windows API (64 bit).
struct _WaveHeader
{
    void* Data;
    uint32 BufferLength;
    uint32 BytesRecorded;
    uint64 User;
    uint32 Flags;
    uint32 Loops;
    void* Next;
    uint64 Reserved;
}

extern "C" uint32 waveOutOpen(void** handle, uint32 device, _WaveFormat* format, uint64 callback, uint64 instance, uint32 flags);
extern "C" uint32 waveOutPrepareHeader(void* handle, _WaveHeader* header, uint32 size);
extern "C" uint32 waveOutUnprepareHeader(void* handle, _WaveHeader* header, uint32 size);
extern "C" uint32 waveOutWrite(void* handle, _WaveHeader* header, uint32 size);
extern "C" uint32 waveOutReset(void* handle);
extern "C" uint32 waveOutClose(void* handle);

void* _waveOut;
_WaveHeader* _headers;
int16* _pcm;
float* _mix;
bool _audioOk;

/// The sound card.
struct Audio
{
    /// Opens the sound output; without a sound card the program stays silent.
    static unsafe void Init()
    {
        var format = _WaveFormat
        {
            FormatTag = 1, Channels = 1, SamplesPerSec = (uint32)AudioRate, AvgBytesPerSec = (uint32)(AudioRate * 2),
            BlockAlign = 2, BitsPerSample = 16, Size = 0,
        };
        void* handle = null;
        if (waveOutOpen(&handle, 0xffffffffu, &format, 0ul, 0ul, 0u) != 0)
            return;
        _waveOut = handle;
        _headers = (_WaveHeader*)Memory.Allocate(_AudioBuffers * sizeof(_WaveHeader));
        _pcm = (int16*)Memory.Allocate(_AudioBuffers * _AudioSamples * sizeof(int16));
        _mix = (float*)Memory.Allocate(_AudioSamples * sizeof(float));
        for (var i = 0; i < _AudioBuffers; i += 1)
        {
            _WaveHeader* h = _headers + i;
            *h = _WaveHeader { Data = (void*)(_pcm + i * _AudioSamples), BufferLength = (uint32)(_AudioSamples * 2) };
            waveOutPrepareHeader(_waveOut, h, (uint32)sizeof(_WaveHeader));
            // free to be filled
            h->Flags = h->Flags | _WhdrDone;
        }
        _audioOk = true;
    }

    /// Refills every buffer the sound card has finished playing; call it once per frame.
    static unsafe void Pump()
    {
        if (!_audioOk)
            return;
        for (var i = 0; i < _AudioBuffers; i += 1)
        {
            _WaveHeader* h = _headers + i;
            if ((Memory.VolatileRead(&h->Flags) & _WhdrDone) == 0)
                continue;
            Music.Render(_mix, _AudioSamples);
            int16* out = _pcm + i * _AudioSamples;
            for (var s = 0; s < _AudioSamples; s += 1)
            {
                out[s] = (int16)(int)(_mix[s] * 32000.0f);
            }
            h->Flags = h->Flags & ~_WhdrDone;
            waveOutWrite(_waveOut, h, (uint32)sizeof(_WaveHeader));
        }
    }

    /// Closes the sound output.
    static unsafe void Shutdown()
    {
        if (!_audioOk)
            return;
        waveOutReset(_waveOut);
        for (var i = 0; i < _AudioBuffers; i += 1)
        {
            waveOutUnprepareHeader(_waveOut, _headers + i, (uint32)sizeof(_WaveHeader));
        }
        waveOutClose(_waveOut);
    }
}
