import deviceInfo from '@ohos.deviceInfo';
import fileUri from '@ohos.file.fileuri';
import { BusinessError } from '@ohos.base';
import { RecorderService, RecorderSnapshot, RecordingFile } from '../recording/RecorderService';
import { durationText, parseBitrateMbps, estimatedMegabytesPerMinute } from '../recording/RecordingPolicy';

const BITRATE_VALUES: number[] = [0, 2, 4, 8, 12, 20, 30];
const BITRATE_LABELS: string[] = ['自动匹配', '2 Mbps · 省空间', '4 Mbps · 均衡', '8 Mbps · 清晰',
  '12 Mbps · 精细', '20 Mbps · 高画质', '30 Mbps · 最高码率', '自定义'];

@Entry
@Component
struct Index {
  @State private phase: string = 'idle';
  @State private message: string = '准备好记录整个桌面';
  @State private elapsed: string = '00:00:00';
  @State private dimensions: string = '跟随主屏幕比例';
  @State private longEdge: number = 0;
  @State private highQuality: boolean = true;
  @State private bitrateChoice: number = 0;
  @State private bitrateText: string = '4';
  @State private microphone: boolean = false;
  @State private recordings: RecordingFile[] = [];
  @State private preview: string = '';
  @State private exporting: boolean = false;
  @State private notice: string = '';
  private startedAt: number = 0;
  private ticker: number = -1;
  private readonly service: RecorderService = RecorderService.shared;

  aboutToAppear(): void {
    this.service.observe((snapshot: RecorderSnapshot) => {
      this.phase = snapshot.phase;
      this.message = snapshot.message;
      this.startedAt = snapshot.startedAt;
      if (snapshot.width > 0) {
        this.dimensions = `${snapshot.width} × ${snapshot.height} · ${(snapshot.bitrate / 1000000).toFixed(1)} Mbps`;
      }
      if (this.phase === 'idle') { this.refresh(); }
    });
    this.ticker = setInterval(() => {
      if (this.phase === 'recording' && this.startedAt > 0) {
        this.elapsed = durationText(Date.now() - this.startedAt);
      }
    }, 500);
    this.refresh();
  }

  aboutToDisappear(): void {
    this.service.observe(undefined);
    if (this.ticker >= 0) { clearInterval(this.ticker); this.ticker = -1; }
  }

  onBackPress(): boolean {
    if (this.preview) { this.preview = ''; return true; }
    if (this.phase !== 'idle') {
      this.notice = '录制进行中。请先停止录制，或最小化窗口继续录制。';
      return true;
    }
    return false;
  }

  private async refresh(): Promise<void> {
    try { this.recordings = await this.service.files(); }
    catch (error) { this.notice = (error as BusinessError).message; }
  }

  private async record(): Promise<void> {
    this.notice = '';
    const videoBitrate = this.bitrateChoice === 0 ? undefined : parseBitrateMbps(this.bitrateText);
    if (this.bitrateChoice !== 0 && videoBitrate === undefined) {
      this.notice = '请输入 1–30 Mbps 的视频码率，最多两位小数。';
      return;
    }
    this.preview = '';
    this.elapsed = '00:00:00';
    try {
      await this.service.start({ longEdge: this.longEdge, highQuality: this.highQuality,
        microphone: this.microphone, videoBitrate: videoBitrate });
    } catch (error) { this.notice = (error as BusinessError).message; }
  }

  private bitrateEstimate(): string {
    const bitrate = parseBitrateMbps(this.bitrateText);
    return bitrate === undefined ? '输入有效码率后显示体积参考' :
      `参考体积约 ${estimatedMegabytesPerMinute(bitrate).toFixed(1)} MB / 分钟`;
  }

  private async stop(): Promise<void> {
    try { await this.service.stop(); }
    catch (error) { this.notice = (error as BusinessError).message; }
  }

  private async exportRecording(recording: RecordingFile): Promise<void> {
    if (this.exporting) { return; }
    this.exporting = true;
    this.notice = '选择导出位置…';
    try {
      const location = await this.service.exportFile(recording);
      this.notice = location ? '导出完成，原视频仍保存在应用内。' : '已取消导出';
    } catch (error) {
      this.notice = `导出失败，应用内原视频仍保留：${(error as BusinessError).message}`;
    } finally { this.exporting = false; }
  }

  @Builder
  qualityChoice(label: string, detail: string, edge: number) {
    Column({ space: 8 }) {
      Text(label).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(this.longEdge === edge ? '#15392F' : '#464F49')
      Text(detail).fontSize(12).fontColor('#6D7971')
    }
    .padding(18).layoutWeight(1).borderRadius(14)
    .backgroundColor(this.longEdge === edge ? '#E6F1E8' : '#F5F7F4')
    .border({ width: this.longEdge === edge ? 2 : 1, color: this.longEdge === edge ? '#39775B' : '#E5EAE3' })
    .onClick(() => { if (this.phase === 'idle') { this.longEdge = edge; } })
    .opacity(this.phase === 'idle' ? 1 : 0.55)
  }

  @Builder
  recordingRow(recording: RecordingFile) {
    Row({ space: 16 }) {
      Stack() {
        Row().width(64).height(46).borderRadius(8).backgroundColor(recording.incomplete ? '#FFF0E2' : '#E6F1E8')
        Text(recording.incomplete ? '!' : '▶').fontSize(19).fontColor('#39775B')
      }
      Column({ space: 5 }) {
        Text(recording.name).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor('#263B31').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${(recording.size / 1048576).toFixed(1)} MB · ${recording.incomplete ? '未完成封装，导出后检查' : 'MP4 视频'}`)
          .fontSize(12).fontColor(recording.incomplete ? '#A26B26' : '#778277')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (!recording.incomplete) {
        Button('播放').fontSize(13).fontColor('#39775B').backgroundColor('#EDF3ED')
          .onClick(() => { this.preview = fileUri.getUriFromPath(recording.path); })
      }
      Button('导出').fontSize(13).fontColor('#FFFFFF').backgroundColor('#39775B')
        .enabled(!this.exporting && this.phase === 'idle')
        .onClick(() => { this.exportRecording(recording); })
    }.padding({ top: 14, bottom: 14 }).width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 26 }) {
        Row() {
          Row({ space: 12 }) {
            Image($r('app.media.app_icon')).width(42).height(42)
            Column({ space: 2 }) {
              Text('清录').fontSize(23).fontWeight(FontWeight.Bold).fontColor('#15392F')
              Text('DESKTOP RECORDER').fontSize(10).letterSpacing(2).fontColor('#78837B')
            }.alignItems(HorizontalAlign.Start)
          }
          Blank()
          Text('OpenHarmony').fontSize(12).fontColor('#64806E')
            .padding({ left: 14, right: 14, top: 7, bottom: 7 }).backgroundColor('#E7EEE6').borderRadius(20)
        }.width('100%')

        Column({ space: 10 }) {
          Text('每一个细节，都清晰留下。').fontSize(30).fontWeight(FontWeight.Bold).fontColor('#15392F')
          Text('整个桌面，高清记录。为演示、教学和工作留下一份好画面。')
            .fontSize(14).fontColor('#778277')
        }.alignItems(HorizontalAlign.Start).width('100%')

        Column({ space: 22 }) {
          Row() {
            Row({ space: 8 }) {
              Row().width(8).height(8).borderRadius(4).backgroundColor('#F27D6C')
                .opacity(this.phase === 'recording' ? 1 : 0.4)
              Text(this.phase === 'recording' ? '正在录制' : this.phase === 'starting' ? '等待系统授权' :
                this.phase === 'stopping' ? '正在保存' : '整屏录制').fontSize(13).fontColor('#D8E9DB')
            }
            Blank()
            Text('H.264 / MP4').fontSize(11).fontColor('#9CB8A5')
          }.width('100%')
          Text(this.elapsed).fontSize(60).fontWeight(FontWeight.Lighter).fontColor('#F0F8EE')
            .fontFamily('monospace').letterSpacing(3)
          Text(this.dimensions).fontSize(13).fontColor('#ADC7B5')
          if (this.phase === 'idle') {
            Button('●   开始录制').height(48).width(212).backgroundColor('#D6EFCC').fontColor('#15392F')
              .enabled(this.bitrateChoice === 0 || parseBitrateMbps(this.bitrateText) !== undefined)
              .fontWeight(FontWeight.Medium).onClick(() => { this.record(); })
          } else {
            Button(this.phase === 'stopping' ? '正在保存…' : this.phase === 'starting' ? '等待授权…' : '■   停止并保存')
              .height(48).width(212).backgroundColor('#F28E7C').fontColor('#243A2D')
              .enabled(this.phase === 'recording').onClick(() => { this.stop(); })
          }
          Text(this.message).fontSize(12).fontColor('#B6CABA').textAlign(TextAlign.Center)
        }.padding(28).width('100%').borderRadius(22).backgroundColor('#15392F')

        Column({ space: 20 }) {
          Row() {
            Text('录制设置').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#263B31')
            Blank()
            Text('保留屏幕比例 · 不放大原画面').fontSize(11).fontColor('#839080')
          }.width('100%')
          Row({ space: 12 }) {
            this.qualityChoice('1080p', '长边最高 1920', 1920)
            this.qualityChoice('2K', '长边最高 2560', 2560)
            this.qualityChoice('原分辨率', '保留原屏像素', 0)
          }.width('100%')
          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text('视频码率').fontSize(14).fontColor('#344D3E')
              Text('分辨率保持不变，也能选择更小的视频体积').fontSize(12).fontColor('#839080')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Select([{ value: BITRATE_LABELS[0] }, { value: BITRATE_LABELS[1] },
              { value: BITRATE_LABELS[2] }, { value: BITRATE_LABELS[3] },
              { value: BITRATE_LABELS[4] }, { value: BITRATE_LABELS[5] },
              { value: BITRATE_LABELS[6] }, { value: BITRATE_LABELS[7] }])
              .selected(this.bitrateChoice).value(BITRATE_LABELS[this.bitrateChoice])
              .font({ size: 13 }).fontColor('#344D3E').enabled(this.phase === 'idle')
              .onSelect((index: number) => {
                this.bitrateChoice = index;
                if (index > 0 && index < BITRATE_VALUES.length) {
                  this.bitrateText = BITRATE_VALUES[index].toString();
                }
              })
          }.width('100%')
          if (this.bitrateChoice === 0) {
            Row({ space: 16 }) {
              Column({ space: 4 }) {
                Text('自动匹配高画质').fontSize(14).fontColor('#344D3E')
                Text('根据分辨率匹配码率，开启后保留更多细节').fontSize(12).fontColor('#839080')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.highQuality }).selectedColor('#39775B')
                .enabled(this.phase === 'idle').onChange((value: boolean) => { this.highQuality = value; })
            }.width('100%')
          } else {
            Column({ space: 10 }) {
              Row({ space: 12 }) {
                Slider({ value: (parseBitrateMbps(this.bitrateText) || 4000000) / 1000000,
                  min: 1, max: 30, step: 0.5 }).layoutWeight(1).selectedColor('#39775B')
                  .enabled(this.phase === 'idle').showTips(true)
                  .onChange((value: number) => { this.bitrateChoice = 7; this.bitrateText = value.toString(); })
                TextInput({ text: this.bitrateText, placeholder: '1–30' }).width(86).height(38)
                  .type(InputType.Normal).maxLength(5).textAlign(TextAlign.Center)
                  .enabled(this.phase === 'idle')
                  .onChange((value: string) => { this.bitrateChoice = 7; this.bitrateText = value; })
                Text('Mbps').fontSize(12).fontColor('#778277')
              }.width('100%')
              if (parseBitrateMbps(this.bitrateText) === undefined) {
                Text('请输入 1–30 Mbps，最多两位小数。').fontSize(12).fontColor('#A8443D')
              } else {
                Text(this.bitrateEstimate()).fontSize(12).fontColor('#39775B')
              }
              Text('码率越低，文件通常越小，运动画面和文字细节也可能下降。实际体积随画面内容变化。')
                .fontSize(12).fontColor('#839080')
            }.width('100%').alignItems(HorizontalAlign.Start)
          }
          Divider().color('#EBEEE6')
          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text('麦克风讲解').fontSize(14).fontColor('#344D3E')
              Text('系统声音由系统录屏服务采集；开启后加入麦克风').fontSize(12).fontColor('#839080')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.microphone }).selectedColor('#39775B')
              .enabled(this.phase === 'idle').onChange((value: boolean) => { this.microphone = value; })
          }.width('100%')
        }.padding(24).width('100%').backgroundColor('#FFFFFF').borderRadius(20)

        if (this.preview) {
          Column({ space: 12 }) {
            Row() {
              Text('视频预览').fontSize(18).fontColor('#263B31')
              Blank()
              Button('关闭预览').fontSize(12).onClick(() => { this.preview = ''; })
            }.width('100%')
            Video({ src: this.preview }).width('100%').height(340).controls(true).autoPlay(false)
              .onError(() => { this.notice = '视频暂时无法播放，请导出到播放器检查。'; })
          }.width('100%')
        }

        Column({ space: 8 }) {
          Row() {
            Text('我的录制').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#263B31')
            Text(`  ${this.recordings.length}`).fontSize(13).fontColor('#8C998D')
            Blank()
            Button('刷新').fontSize(12).backgroundColor('#E9EEE5').fontColor('#52735C')
              .onClick(() => { this.refresh(); })
          }.width('100%').margin({ bottom: 8 })
          if (this.recordings.length === 0) {
            Column({ space: 8 }) {
              Text('第一段精彩，等你按下开始。').fontSize(15).fontColor('#70806F')
              Text('录制自动保存在本机，可随时导出到你选择的文件夹。').fontSize(12).fontColor('#97A091')
            }.padding(28).width('100%')
          } else {
            ForEach(this.recordings, (recording: RecordingFile) => {
              this.recordingRow(recording)
            }, (recording: RecordingFile) => recording.path)
          }
        }.padding(24).width('100%').backgroundColor('#FFFFFF').borderRadius(20)

        if (this.notice) {
          Text(this.notice).fontSize(13).fontColor('#76583A').width('100%')
            .padding(16).backgroundColor('#FFF2DC').borderRadius(12)
        }
        Text(`本地录制 · 无上传 · ${deviceInfo.osFullName} · API ${deviceInfo.sdkApiVersion}\n录制时请选择整个屏幕。隐私窗口和受保护内容可能被系统遮蔽；帧率由系统管理。`)
          .fontSize(11).fontColor('#8B9786').textAlign(TextAlign.Center).lineHeight(19).width('100%')
      }.width('100%').constraintSize({ maxWidth: 960 }).padding(32)
    }.width('100%').height('100%').backgroundColor('#F4F6F0').align(Alignment.Top)
  }
}
