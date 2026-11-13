// Host for shiftybits.wasm (built by `cshiftc build web` with CShift's wasm backend).
//
// The CShift program initialises itself, registers its frame function (web_set_frame) and hands control back by
// calling web_run, which throws. After that, this script calls the frame function once per animation frame through
// the exported function table. The framebuffer is copied into a canvas, key presses are queued for the game and the
// synthesized samples are played by an AudioWorklet.

const W = 960, H = 720;
const canvas = document.getElementById('screen');
const ctx2d = canvas.getContext('2d');
const image = ctx2d.createImageData(W, H);
const image32 = new Uint32Array(image.data.buffer);
const hint = document.getElementById('hint');

let memory = null;
const decoder = new TextDecoder();
const keys = [];

// ---- audio ----

const AUDIO_RATE = 44100;
const AUDIO_AHEAD = 0.12;       // seconds of samples queued in advance
let audio = null;               // { ctx, node, written, start }

const workletCode = `
class ShiftyBitsOut extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunks = []; this.pos = 0;
    this.port.onmessage = e => this.chunks.push(e.data);
  }
  process(inputs, outputs) {
    const out = outputs[0];
    const n = out[0].length;
    for (let i = 0; i < n; i++) {
      let v = 0;
      if (this.chunks.length) {
        const c = this.chunks[0];
        v = c[this.pos++];
        if (this.pos >= c.length) { this.chunks.shift(); this.pos = 0; }
      }
      for (let ch = 0; ch < out.length; ch++) out[ch][i] = v;
    }
    return true;
  }
}
registerProcessor('shiftybits-out', ShiftyBitsOut);
`;

async function startAudio() {
  if (audio) {
    if (audio.ctx.state === 'suspended') audio.ctx.resume();
    return;
  }
  const ctx = new AudioContext({ sampleRate: AUDIO_RATE });
  audio = { ctx, node: null, written: 0, start: 0 };
  const url = URL.createObjectURL(new Blob([workletCode], { type: 'application/javascript' }));
  await ctx.audioWorklet.addModule(url);
  audio.node = new AudioWorkletNode(ctx, 'shiftybits-out', { outputChannelCount: [2] });
  audio.node.connect(ctx.destination);
  audio.start = ctx.currentTime;
  audio.written = 0;
  hint.classList.add('hidden');
}

function audioWanted() {
  if (!audio || !audio.node || audio.ctx.state !== 'running') return 0;
  const played = (audio.ctx.currentTime - audio.start) * AUDIO_RATE;
  if (audio.written < played) audio.written = played;     // after an underrun, start again from now
  const queued = audio.written - played;
  return Math.max(0, Math.floor(AUDIO_AHEAD * AUDIO_RATE - queued));
}

// ---- keyboard ----

const codes = {
  ArrowLeft: 263, ArrowRight: 262, ArrowUp: 265, ArrowDown: 264, Enter: 257, NumpadEnter: 335,
  Escape: 256, Space: 32, Backspace: 259, Delete: 261, F1: 290, F12: 301,
};

function toggleFullscreen() {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.getElementById('stage').requestFullscreen().catch(() => {});
}

window.addEventListener('keydown', e => {
  startAudio();
  // fullscreen must be requested inside the key event itself
  if (e.code === 'F11' || (e.code === 'Enter' && e.altKey)) {
    e.preventDefault();
    toggleFullscreen();
    return;
  }
  // pasting arrives as a paste event (below), which the browser only sends if the key is left alone
  if ((e.ctrlKey || e.metaKey) && e.code === 'KeyV') return;
  let code = codes[e.code];
  if (code === undefined && e.key.length === 1) {
    const c = e.key.toUpperCase().charCodeAt(0);
    if ((c >= 65 && c <= 90) || (c >= 48 && c <= 57)) code = c;
  }
  if (code === undefined) return;
  if (code !== 301) e.preventDefault();
  const mods = (e.shiftKey ? 1 : 0) | (e.ctrlKey || e.metaKey ? 2 : 0) | (e.altKey ? 4 : 0);
  keys.push(code | (mods << 16));
});
// the game asks for the pasted text (web_paste) when it gets Ctrl+V
let pasted = '';
window.addEventListener('paste', e => {
  pasted = (e.clipboardData && e.clipboardData.getData('text')) || '';
  e.preventDefault();
  keys.push(86 | (2 << 16));
});
window.addEventListener('pointerdown', () => startAudio());

// ---- WASI (only what the program uses: console output, the clock, no files) ----

const view = () => new DataView(memory.buffer);
const ENOSYS = 52, EBADF = 8, ENOENT = 44;

const wasi = new Proxy({
  fd_write(fd, iovs, count, written) {
    const v = view();
    let total = 0, text = '';
    for (let i = 0; i < count; i++) {
      const ptr = v.getUint32(iovs + i * 8, true), len = v.getUint32(iovs + i * 8 + 4, true);
      text += decoder.decode(new Uint8Array(memory.buffer, ptr, len));
      total += len;
    }
    if (text.trim()) (fd === 2 ? console.error : console.log)(text.trimEnd());
    v.setUint32(written, total, true);
    return 0;
  },
  clock_time_get(id, precision, out) {
    const ns = BigInt(Math.round((id === 0 ? Date.now() : performance.now()) * 1e6));
    view().setBigUint64(out, ns, true);
    return 0;
  },
  random_get(ptr, len) { crypto.getRandomValues(new Uint8Array(memory.buffer, ptr, len)); return 0; },
  args_sizes_get(a, b) { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
  args_get() { return 0; },
  environ_sizes_get(a, b) { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
  environ_get() { return 0; },
  fd_prestat_get() { return EBADF; },
  path_open() { return ENOENT; },
  path_filestat_get() { return ENOENT; },
  fd_close() { return 0; },
  proc_exit(code) { throw new Error('exit ' + code); },
}, {
  get(target, name) {
    return target[name] || (() => { console.warn('WASI function not provided:', name); return ENOSYS; });
  },
});

// ---- functions the CShift program imports ----

const bestKey = slot => slot === 0 ? 'shiftybits-best' : 'shiftybits-best-' + slot;

let frameIndex = -1;
const RUN = { run: true };

const env = {
  web_set_frame(index) { frameIndex = index; },
  web_run() { throw RUN; },
  web_present(ptr, count) {
    const src = new Uint32Array(memory.buffer, ptr, count);
    for (let i = 0; i < count; i++) {
      const p = src[i];
      image32[i] = 0xff000000 | ((p & 0xff) << 16) | (p & 0xff00) | ((p >> 16) & 0xff);
    }
    ctx2d.putImageData(image, 0, 0);
  },
  web_poll_key() { return keys.length ? keys.shift() : -1; },
  web_audio_rate() { return AUDIO_RATE; },
  web_audio_wanted() { return audioWanted(); },
  web_audio_write(ptr, count) {
    if (!audio || !audio.node) return;
    audio.node.port.postMessage(new Float32Array(memory.buffer, ptr, count).slice());
    audio.written += count;
  },
  // best values and settings; slot 0 keeps the key of the versions that had only one best score
  web_load_best(slot) {
    // values saved under the game's former name (Shiftris) are still found
    const value = localStorage.getItem(bestKey(slot)) || localStorage.getItem(bestKey(slot).replace('shiftybits', 'shiftris'));
    return parseInt(value || '0', 10) || 0;
  },
  web_save_best(slot, value) { localStorage.setItem(bestKey(slot), String(value)); },
  web_copy(ptr) {
    const bytes = new Uint8Array(memory.buffer);
    let end = ptr;
    while (bytes[end]) end++;
    const text = decoder.decode(bytes.subarray(ptr, end));
    if (navigator.clipboard) navigator.clipboard.writeText(text).catch(() => {});
  },
  web_paste(ptr, size) {
    const bytes = new TextEncoder().encode(pasted).subarray(0, size);
    new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
    return bytes.length;
  },
  web_download(namePtr, ptr, length) {
    const bytes = new Uint8Array(memory.buffer);
    let end = namePtr;
    while (bytes[end]) end++;
    const name = decoder.decode(bytes.subarray(namePtr, end));
    const blob = new Blob([bytes.slice(ptr, ptr + length)], { type: 'image/png' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 10000);
  },
  web_fullscreen() { toggleFullscreen(); },
};

// ---- start ----

const { instance } = await WebAssembly.instantiateStreaming(fetch('shiftybits.wasm'), { wasi_snapshot_preview1: wasi, env });
memory = instance.exports.memory;
try {
  instance.exports._start();
} catch (e) {
  if (e !== RUN) throw e;
}
const frame = instance.exports.__indirect_function_table.get(frameIndex);

let last = performance.now();
function tick(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  frame(dt);
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
