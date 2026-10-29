const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const devEco = process.env.RECORDER_DEVECO || '/Applications/DevEco-Studio.app/Contents';
const ts = require(process.env.RECORDER_TYPESCRIPT_DIR || path.join(devEco, 'tools/hvigor/hvigor/node_modules/typescript'));
const sourceDirectory = path.join(__dirname, '../entry/src/main/ets/recording');

function load(name, mocks = {}) {
  const code = ts.transpileModule(fs.readFileSync(path.join(sourceDirectory, name), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports, canIUse: () => true,
    require: id => {
      if (id === './RecordingPolicy') return load('RecordingPolicy.ts');
      if (id in mocks) return mocks[id];
      throw new Error(`Unexpected dependency ${id}`);
    }
  }, { filename: name });
  return module.exports;
}

const policy = load('RecordingPolicy.ts');
test('16:10 desktop retains aspect ratio when capped, even dimensions for H264', () => {
  const size = policy.captureSize(2880, 1800, 1920, true);
  assert.equal(size.width, 1920);
  assert.equal(size.height, 1200);
  assert.ok(size.bitrate > 12000000);
});
test('portrait, odd dimensions and smaller screens never upscale', () => {
  const portrait = policy.captureSize(1081, 1921, 1920, false);
  assert.equal(portrait.width % 2, 0);
  assert.equal(portrait.height, 1920);
  const small = policy.captureSize(1280, 720, 2560, true);
  assert.equal(small.width, 1280);
  assert.equal(small.height, 720);
});
test('native 4K preserves pixels and bitrate is bounded', () => {
  const size = policy.captureSize(3840, 2160, 0, true);
  assert.equal(size.width, 3840);
  assert.equal(size.height, 2160);
  assert.equal(size.bitrate, 30000000);
  assert.equal(policy.captureSize(3840, 2160, 0, false).bitrate, 20000000);
  assert.throws(() => policy.captureSize(0, 1080, 0, true));
  assert.throws(() => policy.captureSize(NaN, 1080, 0, true));
});
test('microphone/privacy notifications do not stop the recording', () => {
  for (const code of [5, 6, 7, 8, 9]) assert.equal(policy.isTerminalCaptureState(code), false);
  for (const code of [1, 2, 3, 4, 10]) assert.equal(policy.isTerminalCaptureState(code), true);
  assert.equal(policy.durationText(3661000), '01:01:01');
});

function fixture(options = {}) {
  const handlers = {};
  const events = [];
  const disk = new Map();
  const descriptors = new Map();
  let nextFd = 3;
  let sourcePath = '';
  let configured = undefined;
  const recorder = {
    on: (event, fn) => { handlers[event] = fn; },
    off: event => { delete handlers[event]; },
    init: async config => {
      configured = config; events.push('init');
      if (options.initFails || config.videoBitrate > 30000000) {
        throw { code: 401, message: 'The Parameter is invalid. Please check the type and range.' };
      }
    },
    setMicEnabled: async value => { events.push(`mic:${value}`); },
    setPickerMode: async () => { events.push('screen-only'); },
    startRecording: async () => {
      events.push('start');
      if (options.startEvent !== false) {
        disk.set(sourcePath, 4096);
        handlers.stateChange(0);
      }
    },
    stopRecording: async () => {
      events.push('stop');
      if (options.stopFails) throw { code: 5400103 };
    },
    release: async () => { events.push('release'); }
  };
  const fileApi = {
    OpenMode: { READ_WRITE: 2, CREATE: 64, READ_ONLY: 0, WRITE_ONLY: 1, TRUNC: 512 },
    accessSync: p => p === '/files/recordings' || disk.has(p),
    mkdirSync: () => {},
    open: async (p, mode) => {
      if (options.openFails) throw { code: 5400103 };
      const fd = nextFd++;
      descriptors.set(fd, p);
      if (mode & 64) { disk.set(p, 0); sourcePath = p; }
      return { fd };
    },
    fsync: async () => { events.push('fsync'); },
    close: async file => { events.push('close'); descriptors.delete(file.fd); },
    stat: async p => ({ size: disk.get(typeof p === 'number' ? descriptors.get(p) : p) || 0, mtime: 1 }),
    unlink: async p => { events.push('unlink'); disk.delete(p); },
    rename: async (p, target) => { events.push('rename'); disk.set(target, disk.get(p)); disk.delete(p); },
    listFile: async () => [...disk.keys()].map(p => p.split('/').pop()),
    copyFile: async () => { events.push('copy'); if (options.copyFails) throw { code: 5400103 }; }
  };
  const service = load('RecorderService.ets', {
    '@ohos.multimedia.media': {
      createAVScreenCaptureRecorder: async () => recorder,
      AVScreenCaptureStateCode: { SCREENCAPTURE_STATE_STARTED: 0 },
      PickerMode: { SCREEN_ONLY: 1 },
      AVScreenCaptureRecordPreset: { SCREEN_RECORD_PRESET_H264_AAC_MP4: 0 },
      createAVMetadataExtractor: async () => ({
        fetchMetadata: async () => options.invalidVideo ? {} : { duration: '1000', videoWidth: '1920', videoHeight: '1080' },
        release: async () => { events.push('metadata-release'); }
      })
    },
    '@ohos.file.fs': fileApi,
    '@ohos.file.picker': { DocumentViewPicker: class { async save() { return options.pickerCancel ? [] : ['file://export.mp4']; } } },
    '@ohos.display': {
      getDefaultDisplaySync: () => options.virtualDisplay ? { width: 1260, height: 2719, id: 0 } : { width: 1920, height: 1080, id: 0 },
      getPrimaryDisplaySync: () => ({ width: 1920, height: 1080, id: 0 })
    },
    '@ohos.deviceInfo': { sdkApiVersion: options.api || 22 },
    '@ohos.abilityAccessCtrl': { createAtManager: () => ({ requestPermissionsFromUser: async () => ({ authResults: [options.permissionDenied ? -1 : 0] }) }) }
  }).RecorderService.shared;
  service.initialize({ filesDir: '/files' });
  let snapshot;
  service.observe(value => { snapshot = { ...value }; });
  return { service, events, disk, descriptors, handlers, get snapshot() { return snapshot; }, get config() { return configured; } };
}
const settings = { longEdge: 1920, highQuality: true, microphone: false };

test('authorization promise does not falsely mark capture as started; cancel cleans resources', async () => {
  const f = fixture({ startEvent: false });
  await f.service.start(settings);
  assert.equal(f.snapshot.phase, 'starting');
  f.handlers.stateChange(1);
  await f.service.stop();
  assert.equal(f.snapshot.phase, 'idle');
  assert.equal(f.disk.size, 0);
  assert.equal(f.descriptors.size, 0);
  assert.match(f.snapshot.message, /取消/);
});
test('normal stop finalizes before closing and exposes only validated MP4', async () => {
  const f = fixture();
  await f.service.start(settings);
  assert.equal(f.snapshot.phase, 'recording');
  assert.equal((await f.service.files()).length, 0);
  await f.service.stop();
  assert.equal(f.snapshot.phase, 'idle');
  assert.ok(f.events.indexOf('stop') < f.events.indexOf('close'));
  assert.ok(f.events.indexOf('metadata-release') < f.events.indexOf('rename'));
  const saved = await f.service.files();
  assert.equal(saved.length, 1);
  assert.equal(saved[0].incomplete, false);
  assert.equal(f.descriptors.size, 0);
});
test('duplicate start/stop clicks serialize into exactly one session', async () => {
  const f = fixture();
  await Promise.all([f.service.start(settings), f.service.start(settings)]);
  await Promise.all([f.service.stop(), f.service.stop()]);
  assert.equal(f.events.filter(e => e === 'start').length, 1);
  assert.equal(f.events.filter(e => e === 'stop').length, 1);
  assert.equal(f.events.filter(e => e === 'release').length, 1);
});
test('system toolbar stop saves output without calling stop twice', async () => {
  const f = fixture();
  await f.service.start(settings);
  f.handlers.stateChange(2);
  await f.service.stop();
  assert.equal(f.snapshot.phase, 'idle');
  assert.ok(f.snapshot.lastSaved.endsWith('.mp4'));
  assert.equal(f.events.includes('stop'), false);
  assert.equal(f.events.filter(e => e === 'release').length, 1);
});
test('failed finalization preserves partial file and permits another session', async () => {
  const f = fixture({ stopFails: true });
  await f.service.start(settings);
  await f.service.stop();
  assert.equal(f.snapshot.phase, 'idle');
  assert.equal(f.snapshot.lastSaved, '');
  assert.equal((await f.service.files())[0].incomplete, true);
  assert.equal(f.descriptors.size, 0);
  await f.service.start(settings);
  assert.equal(f.snapshot.phase, 'recording');
});
test('invalid video metadata never produces a successful saved result', async () => {
  const f = fixture({ invalidVideo: true });
  await f.service.start(settings);
  await f.service.stop();
  assert.equal(f.snapshot.lastSaved, '');
  assert.equal(f.events.includes('rename'), false);
  assert.equal((await f.service.files())[0].incomplete, true);
});
test('microphone rejection and file-open failure return to idle', async () => {
  const denied = fixture({ permissionDenied: true });
  await denied.service.start({ ...settings, microphone: true });
  assert.equal(denied.snapshot.phase, 'idle');
  assert.equal(denied.events.includes('start'), false);
  const noSpace = fixture({ openFails: true });
  await noSpace.service.start(settings);
  assert.equal(noSpace.snapshot.phase, 'idle');
  assert.equal(noSpace.descriptors.size, 0);
});
test('API 12 avoids API 15/22 calls and still initializes main screen capture', async () => {
  const f = fixture({ api: 12 });
  await f.service.start(settings);
  assert.equal(f.events.includes('screen-only'), false);
  assert.equal(f.config.displayId, undefined);
  assert.equal(f.snapshot.phase, 'recording');
});
test('export cancellation and copy failure preserve source and close every fd', async () => {
  const canceled = fixture({ pickerCancel: true });
  await canceled.service.start(settings);
  await canceled.service.stop();
  assert.equal(await canceled.service.exportFile((await canceled.service.files())[0]), '');
  const failed = fixture({ copyFails: true });
  await failed.service.start(settings);
  await failed.service.stop();
  await assert.rejects(failed.service.exportFile((await failed.service.files())[0]));
  assert.equal(failed.descriptors.size, 0);
  assert.equal((await failed.service.files()).length, 1);
});

test('desktop capture uses the primary screen rather than an app compatibility display', async () => {
  const f = fixture({ virtualDisplay: true });
  await f.service.start(settings);
  assert.equal(f.config.frameWidth, 1920);
  assert.equal(f.config.frameHeight, 1080);
  await f.service.stop();
});
test('configuration probe never starts capture and releases file and recorder', async () => {
  const f = fixture();
  await f.service.start(settings, true);
  assert.equal(f.events.includes('start'), false);
  assert.equal(f.events.includes('release'), true);
  assert.equal(f.descriptors.size, 0);
  assert.equal(f.disk.size, 0);
  assert.match(f.snapshot.message, /检查通过/);
});
test('native initialization error retains its stage and code and returns to idle', async () => {
  const f = fixture({ initFails: true });
  await f.service.start(settings);
  assert.equal(f.snapshot.phase, 'idle');
  assert.match(f.snapshot.message, /initRecorder（401）/);
  assert.equal(f.events.includes('start'), false);
  assert.equal(f.events.includes('release'), true);
  assert.equal(f.descriptors.size, 0);
});

test('custom bitrate reduces the encoding target without changing resolution or aspect ratio', () => {
  const automatic = policy.captureSize(3120, 2080, 2560, true);
  const compressed = policy.captureSize(3120, 2080, 2560, true, 2000000);
  assert.equal(compressed.width, automatic.width);
  assert.equal(compressed.height, automatic.height);
  assert.equal(compressed.bitrate, 2000000);
  assert.ok(compressed.bitrate < automatic.bitrate);
});
test('Mbps input accepts decimal user values and rejects ambiguous or unsupported values', () => {
  for (const [text, expected] of [['1', 1000000], ['2.5', 2500000], [' 4 ', 4000000],
    ['12.34', 12340000], ['30', 30000000]]) {
    assert.equal(policy.parseBitrateMbps(text), expected);
  }
  for (const text of ['', '0', '0.99', '30.01', '31', '-2', '2.', '2 Mbps', '1e1', 'NaN', '2.123']) {
    assert.equal(policy.parseBitrateMbps(text), undefined);
  }
  for (const bitrate of [0, 999999, 30000001, NaN, Infinity, 1500000.5]) {
    assert.throws(() => policy.captureSize(1920, 1080, 1920, true, bitrate));
  }
});
test('file-size reference includes the audio track and decreases with the selected bitrate', () => {
  assert.equal(policy.estimatedMegabytesPerMinute(4000000), 31.44);
  assert.ok(policy.estimatedMegabytesPerMinute(2000000) < policy.estimatedMegabytesPerMinute(4000000));
});
test('selected bitrate reaches the native recorder unchanged', async () => {
  const f = fixture();
  await f.service.start({ ...settings, videoBitrate: 2500000 });
  assert.equal(f.config.videoBitrate, 2500000);
  assert.equal(f.config.frameWidth, 1920);
  assert.equal(f.config.frameHeight, 1080);
  await f.service.stop();
});
test('invalid direct bitrate cannot reach native initialization', async () => {
  const f = fixture();
  await f.service.start({ ...settings, videoBitrate: 500000 });
  assert.equal(f.snapshot.phase, 'idle');
  assert.equal(f.events.includes('init'), false);
  assert.equal(f.descriptors.size, 0);
});
