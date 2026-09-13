import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ServerConfig, ServerProfile } from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

const PREFERENCES_NAME: string = 'lanark_settings';
const SERVER_URL_KEY: string = 'lanraragi_server_url';
const SERVER_PROFILES_KEY: string = 'lanark_server_profiles';
const ACTIVE_PROFILE_KEY: string = 'lanark_active_server_profile';
const LEGACY_API_KEY_ALIAS: string = 'lanark_lanraragi_api_key';
const PROFILE_API_KEY_PREFIX: string = 'lanark_lanraragi_api_key_';

class StoredServerProfile {
  readonly id: string;
  readonly name: string;
  readonly serverUrl: string;

  constructor(id: string, name: string, serverUrl: string) {
    this.id = id;
    this.name = name;
    this.serverUrl = serverUrl;
  }
}

export class ServerConfigRepository {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /** Returns the currently selected profile as the legacy ServerConfig API expects. */
  async load(): Promise<ServerConfig> {
    try {
      const profile: ServerProfile | undefined = await this.loadActiveProfile();
      return profile === undefined ? new ServerConfig() : profile.toConfig();
    } catch (error) {
      throw new Error(`${localized('读取服务器配置失败：', 'Failed to read server settings: ')}${this.errorMessage(error)}`);
    }
  }

  async loadProfiles(): Promise<Array<ServerProfile>> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const rawValue: preferences.ValueType = await store.get(SERVER_PROFILES_KEY, '');
      const raw: string = typeof rawValue === 'string' ? rawValue : '';
      const stored: Array<StoredServerProfile> = this.parseStoredProfiles(raw);
      if (stored.length > 0) {
        const profiles: Array<ServerProfile> = [];
        for (const item of stored) {
          const apiKey: string = await this.readApiKey(this.profileAlias(item.id));
          profiles.push(new ServerProfile(item.id, item.serverUrl, apiKey, item.name));
        }
        return profiles;
      }

      // Migrate the original single-server preferences lazily. The profile is
      // persisted when the user next verifies/saves it, so old installations
      // keep working without exposing the API key.
      const legacyUrlValue: preferences.ValueType = await store.get(SERVER_URL_KEY, '');
      const legacyUrl: string = typeof legacyUrlValue === 'string' ? legacyUrlValue : '';
      if (legacyUrl.length === 0) {
        return [];
      }
      const legacyKey: string = await this.readApiKey(LEGACY_API_KEY_ALIAS);
      return [new ServerProfile(this.profileIdForUrl(legacyUrl), legacyUrl, legacyKey)];
    } catch (error) {
      throw new Error(`${localized('读取服务器配置失败：', 'Failed to read server settings: ')}${this.errorMessage(error)}`);
    }
  }

  async loadActiveProfile(): Promise<ServerProfile | undefined> {
    const profiles: Array<ServerProfile> = await this.loadProfiles();
    if (profiles.length === 0) {
      return undefined;
    }

    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const activeValue: preferences.ValueType = await store.get(ACTIVE_PROFILE_KEY, '');
      const activeId: string = typeof activeValue === 'string' ? activeValue : '';
      if (activeId.length > 0) {
        const matched: ServerProfile | undefined =
          profiles.find((profile: ServerProfile) => profile.id === activeId);
        if (matched !== undefined) {
          return matched;
        }
      }
    } catch (error) {
      throw new Error(`${localized('读取当前服务器失败：', 'Failed to read the active server: ')}${this.errorMessage(error)}`);
    }
    return profiles[0];
  }

  /** Upserts by URL and makes the saved endpoint the active profile. */
  async save(config: ServerConfig): Promise<void> {
    try {
      const profiles: Array<ServerProfile> = await this.loadProfiles();
      const id: string = this.profileIdForUrl(config.serverUrl);
      const existingIndex: number = profiles.findIndex((profile: ServerProfile) => profile.serverUrl === config.serverUrl);
      const profile: ServerProfile = new ServerProfile(id, config.serverUrl, config.apiKey);
      if (existingIndex >= 0) {
        profiles[existingIndex] = profile;
      } else {
        profiles.push(profile);
      }
      await this.persistProfiles(profiles, id);
    } catch (error) {
      throw new Error(`${localized('保存服务器配置失败：', 'Failed to save server settings: ')}${this.errorMessage(error)}`);
    }
  }

  /** Changes the active profile without changing its credentials. */
  async selectProfile(profileId: string): Promise<void> {
    try {
      const profiles: Array<ServerProfile> = await this.loadProfiles();
      const selected: ServerProfile | undefined =
        profiles.find((profile: ServerProfile) => profile.id === profileId);
      if (selected === undefined) {
        throw new Error(localized('找不到服务器配置', 'The server profile was not found'));
      }
      await this.persistProfiles(profiles, selected.id);
    } catch (error) {
      throw new Error(`${localized('切换服务器失败：', 'Failed to switch server: ')}${this.errorMessage(error)}`);
    }
  }

  async deleteProfile(profileId: string): Promise<void> {
    try {
      const profiles: Array<ServerProfile> = await this.loadProfiles();
      const targetIndex: number = profiles.findIndex((profile: ServerProfile) => profile.id === profileId);
      if (targetIndex < 0) {
        return;
      }
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const activeValue: preferences.ValueType = await store.get(ACTIVE_PROFILE_KEY, '');
      const activeId: string = typeof activeValue === 'string' ? activeValue : '';
      const target: ServerProfile = profiles[targetIndex];
      profiles.splice(targetIndex, 1);
      if (profiles.length === 0) {
        await store.delete(SERVER_PROFILES_KEY);
        await store.delete(ACTIVE_PROFILE_KEY);
        await store.delete(SERVER_URL_KEY);
        await store.flush();
        // Keys are removed only after the reduced list is persisted, so a
        // failure here cannot leave a stored profile without its credential.
        await this.removeApiKey(this.profileAlias(target.id));
        await this.removeApiKey(LEGACY_API_KEY_ALIAS);
        return;
      }
      const nextActive: string = activeId === target.id || activeId.length === 0
        ? profiles[0].id
        : activeId;
      await this.persistProfiles(profiles, nextActive);
      await this.removeApiKey(this.profileAlias(target.id));
    } catch (error) {
      throw new Error(`${localized('删除服务器失败：', 'Failed to delete server: ')}${this.errorMessage(error)}`);
    }
  }

  async clear(): Promise<void> {
    try {
      const profiles: Array<ServerProfile> = await this.loadProfiles();
      for (const profile of profiles) {
        await this.removeApiKey(this.profileAlias(profile.id));
      }
      await this.removeApiKey(LEGACY_API_KEY_ALIAS);
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.delete(SERVER_PROFILES_KEY);
      await store.delete(ACTIVE_PROFILE_KEY);
      await store.delete(SERVER_URL_KEY);
      await store.flush();
    } catch (error) {
      throw new Error(`${localized('清除服务器配置失败：', 'Failed to clear server settings: ')}${this.errorMessage(error)}`);
    }
  }

  private async persistProfiles(profiles: Array<ServerProfile>, activeId: string): Promise<void> {
    try {
      const stored: Array<StoredServerProfile> = profiles.map((profile: ServerProfile) => {
        return new StoredServerProfile(profile.id, profile.name, profile.serverUrl);
      });
      for (const profile of profiles) {
        await this.replaceApiKey(this.profileAlias(profile.id), profile.apiKey);
      }
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(SERVER_PROFILES_KEY, JSON.stringify(stored));
      await store.put(ACTIVE_PROFILE_KEY, activeId);
      const active: ServerProfile | undefined =
        profiles.find((profile: ServerProfile) => profile.id === activeId);
      await store.put(SERVER_URL_KEY, active === undefined ? '' : active.serverUrl);
      await store.flush();
    } catch (error) {
      throw new Error(this.errorMessage(error));
    }
  }

  private parseStoredProfiles(raw: string): Array<StoredServerProfile> {
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsedValue: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsedValue)) {
        return [];
      }
      const parsed: Array<Object> = parsedValue as Array<Object>;
      const result: Array<StoredServerProfile> = [];
      for (const item of parsed) {
        const candidate: StoredServerProfile = item as StoredServerProfile;
        if (candidate.id !== undefined && candidate.serverUrl !== undefined) {
          const name: string = candidate.name === undefined || candidate.name.length === 0
            ? candidate.serverUrl
            : candidate.name;
          result.push(new StoredServerProfile(candidate.id, name, candidate.serverUrl));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  private profileIdForUrl(serverUrl: string): string {
    let hash: number = 5381;
    for (let index = 0; index < serverUrl.length; index++) {
      hash = ((hash * 33) ^ serverUrl.charCodeAt(index)) >>> 0;
    }
    return `profile-${hash.toString(16)}`;
  }

  private profileAlias(profileId: string): string {
    return `${PROFILE_API_KEY_PREFIX}${profileId}`;
  }

  private aliasBytes(alias: string): Uint8Array {
    return new util.TextEncoder().encodeInto(alias);
  }

  private async readApiKey(alias: string): Promise<string> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, this.aliasBytes(alias));
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
      throw new Error(`${localized('读取 API Key 失败：', 'Failed to read API key: ')}${this.errorMessage(error)}`);
    }
  }

  private async replaceApiKey(alias: string, apiKey: string): Promise<void> {
    if (apiKey.length === 0) {
      await this.removeApiKey(alias);
      return;
    }
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, this.aliasBytes(alias));
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(apiKey));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attributes);
    } catch (error) {
      if (this.isAssetError(error, asset.ErrorCode.DUPLICATED)) {
        const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        query.set(asset.Tag.ALIAS, this.aliasBytes(alias));
        const attributesToUpdate: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        attributesToUpdate.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(apiKey));
        try {
          await asset.update(query, attributesToUpdate);
          return;
        } catch (updateError) {
          throw new Error(`${localized('更新 API Key 失败：', 'Failed to update API key: ')}${this.errorMessage(updateError)}`);
        }
      }
      throw new Error(`${localized('写入 API Key 失败：', 'Failed to write API key: ')}${this.errorMessage(error)}`);
    }
  }

  private async removeApiKey(alias: string): Promise<void> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.aliasBytes(alias));
    try {
      await asset.remove(query);
    } catch (error) {
      if (this.isAssetError(error, asset.ErrorCode.NOT_FOUND)) {
        return;
      }
      throw new Error(`${localized('删除 API Key 失败：', 'Failed to delete API key: ')}${this.errorMessage(error)}`);
    }
  }

  private isAssetError(error: Object, code: asset.ErrorCode): boolean {
    return (error as BusinessError).code === code;
  }

  private errorMessage(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return localized('系统安全存储不可用', 'System secure storage is unavailable');
  }
}
