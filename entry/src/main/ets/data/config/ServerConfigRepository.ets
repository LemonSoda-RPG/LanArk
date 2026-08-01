import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ServerConfig } from '../../domain/model/LanraragiModels';

const PREFERENCES_NAME: string = 'lanark_settings';
const SERVER_URL_KEY: string = 'lanraragi_server_url';
const API_KEY_ALIAS: string = 'lanark_lanraragi_api_key';

export class ServerConfigRepository {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async load(): Promise<ServerConfig> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const serverUrlValue: preferences.ValueType = await store.get(SERVER_URL_KEY, '');
      const serverUrl: string = serverUrlValue as string;
      const apiKey: string = await this.readApiKey();
      return new ServerConfig(serverUrl, apiKey);
    } catch (error) {
      throw new Error(`读取服务器配置失败：${this.errorMessage(error)}`);
    }
  }

  async save(config: ServerConfig): Promise<void> {
    try {
      await this.replaceApiKey(config.apiKey);
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(SERVER_URL_KEY, config.serverUrl);
      await store.flush();
    } catch (error) {
      throw new Error(`保存服务器配置失败：${this.errorMessage(error)}`);
    }
  }

  async clear(): Promise<void> {
    try {
      await this.removeApiKey();
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.delete(SERVER_URL_KEY);
      await store.flush();
    } catch (error) {
      throw new Error(`清除服务器配置失败：${this.errorMessage(error)}`);
    }
  }

  private aliasBytes(): Uint8Array {
    return new util.TextEncoder().encodeInto(API_KEY_ALIAS);
  }

  private async readApiKey(): Promise<string> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, this.aliasBytes());
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);

      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return '';
      }
      return new util.TextDecoder().decodeToString(secret);
    } catch (error) {
      if (this.isAssetError(error, asset.ErrorCode.NOT_FOUND)) {
        return '';
      }
      throw new Error(`读取 API Key 失败：${this.errorMessage(error)}`);
    }
  }

  private async replaceApiKey(apiKey: string): Promise<void> {
    if (apiKey.length === 0) {
      await this.removeApiKey();
      return;
    }

    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, this.aliasBytes());
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(apiKey));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attributes);
    } catch (error) {
      if (this.isAssetError(error, asset.ErrorCode.DUPLICATED)) {
        const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        query.set(asset.Tag.ALIAS, this.aliasBytes());
        const attributesToUpdate: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        attributesToUpdate.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(apiKey));
        try {
          await asset.update(query, attributesToUpdate);
          return;
        } catch (updateError) {
          throw new Error(`更新 API Key 失败：${this.errorMessage(updateError)}`);
        }
      }
      throw new Error(`写入 API Key 失败：${this.errorMessage(error)}`);
    }
  }

  private async removeApiKey(): Promise<void> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.aliasBytes());
    try {
      await asset.remove(query);
    } catch (error) {
      if (this.isAssetError(error, asset.ErrorCode.NOT_FOUND)) {
        return;
      }
      throw new Error(`删除 API Key 失败：${this.errorMessage(error)}`);
    }
  }

  private isAssetError(error: Object, code: asset.ErrorCode): boolean {
    return (error as BusinessError).code === code;
  }

  private errorMessage(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '系统安全存储不可用';
  }
}
