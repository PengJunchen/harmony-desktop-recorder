import media from '@ohos.multimedia.media';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import display from '@ohos.display';
import deviceInfo from '@ohos.deviceInfo';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';
import { captureSize, captureStateMessage, isTerminalCaptureState } from './RecordingPolicy';

export interface RecordingOptions {
  longEdge: number;
  highQuality: boolean;
  microphone: boolean;
  videoBitrate?: number;
}

export interface RecordingFile {
  name: string;
  path: string;
  size: number;
  modified: number;
  incomplete: boolean;
}

export class RecorderSnapshot {
  phase: string = 'idle';
  message: string = '准备好记录整个桌面';
  startedAt: number = 0;
  width: number = 0;
  height: number = 0;
  bitrate: number = 0;
  lastSaved: string = '';
}

interface CaptureDiagnostic {
  time: number;
  stage: string;
  phase: string;
  code: number;
  detail: string;
}

export class RecorderService {
  static readonly shared: RecorderService = new RecorderService();
  private context: common.UIAbilityContext | undefined = undefined;
  private recorder: media.AVScreenCaptureRecorder | undefined = undefined;
  private file: fs.File | undefined = undefined;
  private path: string = '';
  private started: boolean = false;
  private snapshot: RecorderSnapshot = new RecorderSnapshot();
  private listener: ((snapshot: RecorderSnapshot) => void) | undefined = undefined;
  // Native state/error events and UI actions share the same serialized lifecycle.
  private pending: Promise<void> = Promise.resolve();
  private stage: string = 'idle';
  private validating: boolean = false;

  initialize(context: common.UIAbilityContext): void { this.context = context; }

  observe(listener: ((snapshot: RecorderSnapshot) => void) | undefined): void {
    this.listener = listener;
    this.publish();
  }

  private publish(): void {
    if (this.listener) { this.listener(this.snapshot); }
  }

  private enqueue(action: () => Promise<void>): Promise<void> {
    const result = this.pending.then(action);
    this.pending = result.catch(() => {});
    return result;
  }

  start(options: RecordingOptions, validateOnly: boolean = false, configVariant: number = 0): Promise<void> {
    return this.enqueue(async () => {
      if (this.snapshot.phase !== 'idle') { return; }
      this.snapshot.phase = 'starting';
      this.snapshot.message = '请在系统弹窗中授权，并选择整个屏幕';
      this.snapshot.lastSaved = '';
      this.snapshot.startedAt = 0;
      this.validating = validateOnly;
      this.publish();
      try {
        this.step('checkCapability');
        if (!this.context) { throw new Error('应用尚未初始化'); }
        if (deviceInfo.sdkApiVersion < 12) { throw new Error('需要 OpenHarmony API 12 或更高版本'); }
        if (!canIUse('SystemCapability.Multimedia.Media.AVScreenCapture')) {
          throw new Error('此设备没有提供系统录屏能力');
        }
        if (options.microphone) {
          this.step('requestMicrophone');
          const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
            this.context, ['ohos.permission.MICROPHONE']);
          if (result.authResults.length !== 1 || result.authResults[0] !== 0) {
            throw new Error('未获得麦克风权限，请关闭麦克风或重新授权');
          }
        }
        this.step('readDisplay');
        this.trace('device', 0, `type=${deviceInfo.deviceType}; api=${deviceInfo.sdkApiVersion}; os=${deviceInfo.osFullName}`);
        const defaultScreen = display.getDefaultDisplaySync();
        const screen = deviceInfo.sdkApiVersion >= 14 ? display.getPrimaryDisplaySync() : defaultScreen;
        this.trace('displaySource', 0, `default=${defaultScreen.width}x${defaultScreen.height}; primary=${screen.width}x${screen.height}; variant=${configVariant}`);
        const size = captureSize(screen.width, screen.height, options.longEdge, options.highQuality, options.videoBitrate);
        this.trace('display', 0, `${screen.width}x${screen.height}; output=${size.width}x${size.height}; bitrate=${size.bitrate}; displayId=${screen.id}`);
        this.snapshot.width = size.width;
        this.snapshot.height = size.height;
        this.snapshot.bitrate = size.bitrate;
        this.step('prepareFile');
        const directory = this.directory();
        if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
        const timestamp = Date.now();
        let sequence = 0;
        this.path = `${directory}/Qinglu_${timestamp}.part.mp4`;
        while (fs.accessSync(this.path)) {
          sequence++;
          this.path = `${directory}/Qinglu_${timestamp}_${sequence}.part.mp4`;
        }
        this.file = await fs.open(this.path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        this.step('createRecorder');
        const recorder = await media.createAVScreenCaptureRecorder();
        this.recorder = recorder;
        recorder.on('stateChange', (code: media.AVScreenCaptureStateCode) => {
          if (this.recorder !== recorder) { return; }
          this.trace('stateChange', code);
          if (code === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STARTED) {
            this.started = true;
            this.snapshot.phase = 'recording';
            this.snapshot.startedAt = Date.now();
            this.snapshot.message = '正在录制整个桌面 · 可最小化本窗口';
            this.publish();
          } else if (isTerminalCaptureState(code)) {
            const reason = captureStateMessage(code);
            this.enqueue(async () => {
              if (this.recorder === recorder) { await this.finish(true, reason); }
            }).catch(() => {});
          } else {
            const message = captureStateMessage(code);
            if (message) { this.snapshot.message = message; this.publish(); }
          }
        });
        recorder.on('error', (error: BusinessError) => {
          this.trace('recorderError', error.code, error.message);
          this.enqueue(async () => {
            if (this.recorder === recorder) { await this.finish(true, this.describeError(error)); }
          }).catch(() => {});
        });
        // API 22+ limits the system chooser to full screens. Older systems capture the main screen.
        if (deviceInfo.sdkApiVersion >= 22) {
          this.step('setPickerMode');
          await recorder.setPickerMode(media.PickerMode.SCREEN_ONLY);
        }
        let config: media.AVScreenCaptureRecordConfig = {
          fd: this.file.fd, frameWidth: size.width, frameHeight: size.height,
          videoBitrate: size.bitrate, audioSampleRate: 48000,
          audioChannelCount: 2, audioBitrate: 192000,
          preset: media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H264_AAC_MP4
        };
        if (deviceInfo.sdkApiVersion >= 15) { config.displayId = screen.id; }
        // Diagnostic variants only initialize the recorder. They never start capture.
        if (validateOnly && configVariant > 0) {
          config = { fd: this.file.fd };
          if (configVariant >= 2) { config.frameWidth = size.width; config.frameHeight = size.height; }
          if (configVariant >= 3) { config.videoBitrate = size.bitrate; }
          if (configVariant >= 4) {
            config.audioSampleRate = 48000; config.audioChannelCount = 2;
            config.audioBitrate = configVariant === 4 ? 96000 : 192000;
          }
          if (configVariant >= 6) { config.displayId = screen.id; }
          if (configVariant >= 7) {
            const bitrates: number[] = [10000000, 12000000, 20000000, 30000000, 60000000, 30822120];
            config = { fd: this.file.fd, frameWidth: size.width, frameHeight: size.height,
              videoBitrate: bitrates[Math.min(configVariant - 7, bitrates.length - 1)] };
          }
        }
        this.step('initRecorder');
        await recorder.init(config);
        this.step('setMicrophone');
        await recorder.setMicEnabled(options.microphone);
        if (validateOnly) {
          this.trace('configurationValidated');
          await this.finish(false, '初始化检查通过，未开始录制');
          return;
        }
        // The promise alone does not prove user authorization. Wait for the STARTED event.
        this.step('startRecording');
        await recorder.startRecording();
      } catch (error) {
        const failure = error as BusinessError;
        this.trace('failure', failure.code, `${this.stage}: ${failure.message}`);
        const reason = `${this.stage}（${failure.code || '未知错误码'}）：${this.describeError(failure)}`;
        await this.finish(false, reason);
      }
    });
  }

  stop(): Promise<void> {
    return this.enqueue(async () => {
      if (this.snapshot.phase === 'idle') { return; }
      await this.finish(false, '录制已结束');
    });
  }

  private async finish(systemStopped: boolean, reason: string): Promise<void> {
    this.snapshot.phase = 'stopping';
    this.snapshot.message = '正在封装 MP4，请稍候…';
    this.publish();
    const recorder = this.recorder;
    this.recorder = undefined;
    let finalized = systemStopped;
    let failure = '';
    if (recorder) {
      try { recorder.off('stateChange'); recorder.off('error'); }
      catch (error) { failure = this.describeError(error as BusinessError); }
      if (!systemStopped && this.started) {
        try { await recorder.stopRecording(); finalized = true; }
        catch (error) { failure = this.describeError(error as BusinessError); }
      }
      try { await recorder.release(); }
      catch (error) { failure = this.describeError(error as BusinessError); }
    }
    if (this.file) {
      try { await fs.fsync(this.file.fd); }
      catch (error) { failure = this.describeError(error as BusinessError); }
      try { await fs.close(this.file); }
      catch (error) { failure = this.describeError(error as BusinessError); }
      this.file = undefined;
    }
    let message = reason;
    if (this.path) {
      try {
        const stat = await fs.stat(this.path);
        if (!this.started && (stat.size === 0 || this.validating)) {
          await fs.unlink(this.path);
        } else if (this.started && finalized && !failure && await this.validVideo(this.path)) {
          const destination = this.path.replace('.part.mp4', '.mp4');
          await fs.rename(this.path, destination);
          this.snapshot.lastSaved = destination;
          message = `${reason}。视频已保存，可在下方导出。`;
        } else {
          message = `${reason}。文件尚未通过完整性检查，已保留原始文件，请在下方导出检查。`;
        }
      } catch (error) { failure = this.describeError(error as BusinessError); }
    }
    this.path = '';
    this.started = false;
    this.validating = false;
    this.snapshot.phase = 'idle';
    this.snapshot.message = failure ? `${message}（${failure}）` : message;
    this.trace('finished', 0, this.snapshot.message);
    this.publish();
  }

  private step(stage: string): void {
    this.stage = stage;
    this.trace(stage);
  }

  private trace(stage: string, code: number = 0, detail: string = ''): void {
    if (!this.context) { return; }
    try {
      const path = `${this.context.filesDir}/recorder-diagnostics.jsonl`;
      const mode = fs.accessSync(path) && fs.statSync(path).size > 262144 ? fs.OpenMode.TRUNC : fs.OpenMode.APPEND;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | mode);
      try {
        const event: CaptureDiagnostic = { time: Date.now(), stage: stage, phase: this.snapshot.phase,
          code: code || 0, detail: detail };
        fs.writeSync(file.fd, JSON.stringify(event) + '\n');
      } finally { fs.closeSync(file); }
    } catch (_) { /* Diagnostic output must not prevent recording or cleanup. */ }
  }

  private async validVideo(path: string): Promise<boolean> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    let extractor: media.AVMetadataExtractor | undefined = undefined;
    try {
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: file.fd, offset: 0, length: (await fs.stat(file.fd)).size };
      const metadata = await extractor.fetchMetadata();
      return Number(metadata.duration) > 0 && Number(metadata.videoWidth) > 0 && Number(metadata.videoHeight) > 0;
    } finally {
      try { if (extractor) { await extractor.release(); } }
      finally { await fs.close(file); }
    }
  }

  private directory(): string {
    if (!this.context) { throw new Error('应用尚未初始化'); }
    return `${this.context.filesDir}/recordings`;
  }

  async files(): Promise<RecordingFile[]> {
    const directory = this.directory();
    if (!fs.accessSync(directory)) { return []; }
    const names = await fs.listFile(directory);
    const recordings: RecordingFile[] = [];
    for (const name of names) {
      const path = `${directory}/${name}`;
      if (!name.endsWith('.mp4') || path === this.path) { continue; }
      const stat = await fs.stat(path);
      recordings.push({ name: name, path: path, size: stat.size, modified: stat.mtime,
        incomplete: name.endsWith('.part.mp4') });
    }
    return recordings.sort((a: RecordingFile, b: RecordingFile) => b.modified - a.modified);
  }

  async exportFile(recording: RecordingFile): Promise<string> {
    if (!this.context) { throw new Error('应用尚未初始化'); }
    const savePicker = new picker.DocumentViewPicker(this.context);
    const locations = await savePicker.save({ newFileNames: [recording.name], fileSuffixChoices: ['MP4 视频|.mp4'] });
    if (locations.length === 0) { return ''; }
    const source = await fs.open(recording.path, fs.OpenMode.READ_ONLY);
    try {
      const destination = await fs.open(locations[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { await fs.copyFile(source.fd, destination.fd); await fs.fsync(destination.fd); }
      finally { await fs.close(destination); }
    } finally { await fs.close(source); }
    return locations[0];
  }

  private describeError(error: BusinessError): string {
    if (error.code === 201) { return '系统拒绝权限，请检查录屏或麦克风授权'; }
    if (error.code === 5400103) { return '文件写入失败，请检查可用空间'; }
    if (error.code === 5400105) { return '系统媒体服务已退出，请重试'; }
    return error.message || `操作失败（${error.code}）`;
  }
}
