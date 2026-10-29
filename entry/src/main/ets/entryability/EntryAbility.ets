import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import Want from '@ohos.app.ability.Want';
import { RecorderService } from '../recording/RecorderService';

export default class EntryAbility extends UIAbility {
  private validateConfig: boolean = false;
  private configVariant: number = 0;

  onCreate(want: Want): void {
    this.validateConfig = want.parameters?.qingluValidateConfig === true;
    this.configVariant = (want.parameters?.qingluConfigVariant as number) || 0;
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    RecorderService.shared.initialize(this.context);
    stage.loadContent('pages/Index');
    if (this.validateConfig) { this.checkConfiguration(); }
  }

  onNewWant(want: Want): void {
    if (want.parameters?.qingluValidateConfig === true) {
      this.configVariant = (want.parameters?.qingluConfigVariant as number) || 0;
      this.checkConfiguration();
    }
  }

  private checkConfiguration(): void {
    // Configuration validation opens no screen picker and never starts capture.
    RecorderService.shared.start({ longEdge: 0, highQuality: true, microphone: false }, true, this.configVariant).catch(() => {});
  }

  onDestroy(): void {
    // Keep the recorder alive when merely minimized. Finalize on ability destruction.
    RecorderService.shared.stop().catch(() => {});
  }
}
