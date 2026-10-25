import { ServerProfile } from '../../domain/model/LanraragiModels';

/**
 * True when the form changed only the saved endpoint's name.
 *
 * A name is local, so such an edit is written without a connection test. Running
 * the test first is what made renaming a server impossible once its stored key
 * no longer matched: the test reported 401, the save never ran, and the name was
 * lost. The address is compared in its normalised form because that is what the
 * repository stores.
 */
export function isNameOnlyEdit(profile: ServerProfile, normalizedUrl: string,
  apiKey: string): boolean {
  return normalizedUrl === profile.serverUrl && apiKey === profile.apiKey;
}
