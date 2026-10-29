import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { PRIVACY_VERSION } from './AppMetadata';

export class PrivacySettings {
  private readonly store: preferences.Preferences;

  constructor(context: common.UIAbilityContext) {
    this.store = preferences.getPreferencesSync(context, { name: 'qinglu_privacy' });
  }

  accepted(): boolean {
    return this.store.getSync('acceptedPolicyVersion', '') === PRIVACY_VERSION;
  }

  async save(accepted: boolean): Promise<void> {
    this.store.putSync('acceptedPolicyVersion', accepted ? PRIVACY_VERSION : '');
    await this.store.flush();
  }
}
