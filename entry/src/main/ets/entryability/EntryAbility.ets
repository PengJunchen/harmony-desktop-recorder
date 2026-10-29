import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { RecorderService } from '../recording/RecorderService';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    RecorderService.shared.initialize(this.context);
    stage.loadContent('pages/Index');
  }

  onDestroy(): void {
    // Keep the recorder alive when merely minimized. Finalize on ability destruction.
    RecorderService.shared.stop().catch(() => {});
  }
}
