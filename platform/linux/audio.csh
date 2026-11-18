//! Sound output on Linux via ALSA (libasound, which also reaches PulseAudio and PipeWire through their ALSA plugins):
//! the device is opened without blocking, and every frame the synthesizer fills as much as it has room for.

namespace ShiftyBits;

using System;

/// The sample rate of the sound output.
const int AudioRate = 44100;

const int _AudioChunk = 512;
const int _SndPcmStreamPlayback = 0;
const int _SndPcmNonblock = 1;
const int _SndPcmFormatS16Le = 2;
const int _SndPcmAccessRwInterleaved = 3;
// how much sound is queued ahead, in microseconds
const uint32 _AudioLatency = 70000u;

extern "C" int snd_pcm_open(void** pcm, char* name, int stream, int mode);
extern "C" int snd_pcm_set_params(void* pcm, int format, int access, uint32 channels, uint32 rate, int softResample, uint32 latency);
extern "C" int64 snd_pcm_avail_update(void* pcm);
extern "C" int64 snd_pcm_writei(void* pcm, void* buffer, uint64 frames);
extern "C" int snd_pcm_recover(void* pcm, int error, int silent);
extern "C" int snd_pcm_drop(void* pcm);
extern "C" int snd_pcm_close(void* pcm);

void* _pcmDevice;
int16* _pcm;
float* _mix;
bool _audioOk;

/// The sound card.
struct Audio
{
    /// Opens the sound output; without a sound device the program stays silent.
    static unsafe void Init()
    {
        void* device = null;
        string name = "default";
        if (snd_pcm_open(&device, name.CStr(), _SndPcmStreamPlayback, _SndPcmNonblock) < 0)
            return;
        if (snd_pcm_set_params(device, _SndPcmFormatS16Le, _SndPcmAccessRwInterleaved, 1u, (uint32)AudioRate, 1, _AudioLatency) < 0)
        {
            snd_pcm_close(device);
            return;
        }
        _pcmDevice = device;
        _pcm = (int16*)Memory.Allocate(_AudioChunk * sizeof(int16));
        _mix = (float*)Memory.Allocate(_AudioChunk * sizeof(float));
        _audioOk = true;
    }

    /// Fills the room the sound device has; call it once per frame.
    static unsafe void Pump()
    {
        if (!_audioOk)
            return;
        int64 room = snd_pcm_avail_update(_pcmDevice);
        if (room < 0)
        {
            // an underrun (or a suspended device): start again
            snd_pcm_recover(_pcmDevice, (int)room, 1);
            room = snd_pcm_avail_update(_pcmDevice);
            if (room < 0)
                return;
        }
        while (room >= _AudioChunk)
        {
            Music.Render(_mix, _AudioChunk);
            for (var s = 0; s < _AudioChunk; s += 1)
            {
                _pcm[s] = (int16)(int)(_mix[s] * 32000.0f);
            }
            int64 written = snd_pcm_writei(_pcmDevice, (void*)_pcm, (uint64)_AudioChunk);
            if (written < 0)
            {
                snd_pcm_recover(_pcmDevice, (int)written, 1);
                return;
            }
            room -= written;
        }
    }

    /// Closes the sound output.
    static unsafe void Shutdown()
    {
        if (!_audioOk)
            return;
        snd_pcm_drop(_pcmDevice);
        snd_pcm_close(_pcmDevice);
    }
}
