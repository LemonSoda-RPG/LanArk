import { ArchiveItem } from '../../domain/model/LanraragiModels';

/**
 * Key for one archive row.
 *
 * The page position belongs in the key. `LazyForEach` keeps the component it
 * already built while the key is unchanged, so a row whose progress moved went
 * on showing the position it was created with: the card still read "unread"
 * after a document had been read, and the badge still claimed it was new.
 */
export function archiveRowKey(archive: ArchiveItem, prefix: string = ''): string {
  const key: string = `${archive.id}-${archive.progress}`;
  return prefix.length > 0 ? `${prefix}-${key}` : key;
}
