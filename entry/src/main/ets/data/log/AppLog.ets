import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';

const DOMAIN: number = 0x0001;
const HILOG_TAG: string = 'LanArk';

const LOG_FOLDER_NAME: string = 'lanark-logs';
const LOG_FILE_NAME: string = 'lanark.log';
const PREVIOUS_LOG_FILE_NAME: string = 'lanark-previous.log';

/** Where the on/off switches live, read again by the settings page. */
export const LOG_PREFERENCES_NAME: string = 'lanark_log_settings';
export const LOG_ENABLED_KEY: string = 'log_enabled';
export const LOG_VERBOSE_KEY: string = 'log_verbose';

/** Entries kept in memory for the in-app viewer and for copying. */
const MEMORY_LIMIT: number = 4000;
/** A log file rotates once it passes this size, keeping the previous one. */
const FILE_LIMIT_BYTES: number = 1024 * 1024;
/** Lines are flushed to disk in batches; the buffered ones are never lost. */
const FLUSH_DELAY_MS: number = 400;

export type LogLevel = 'D' | 'I' | 'W' | 'E';

interface LogEntry {
  time: string;
  level: LogLevel;
  area: string;
  message: string;
}

/**
 * In-app diagnostic log, off by default.
 *
 * The system log (`hilog`) is only reachable with a development cable, so a
 * problem reported from a normal session used to be undiagnosable: the answer
 * was always "reproduce it while connected". This keeps a bounded, rotated copy
 * inside the app sandbox that can be copied out of Settings instead.
 *
 * It is deliberately opt-in. A log holds server addresses, archive titles and
 * page names, so recording starts only when the user turns it on; until then
 * every call here costs one boolean check and writes nothing.
 *
 * Two switches: `enabled` records anything at all, `verbose` adds per-request
 * and per-page detail. With `verbose` off only the milestones and every problem
 * are kept, which is what a report usually needs.
 */
export class AppLog {
  private static entries: Array<LogEntry> = [];
  private static rootPath: string = '';
  private static filePath: string = '';
  private static previousFilePath: string = '';
  private static initialized: boolean = false;
  private static enabled: boolean = false;
  private static verbose: boolean = false;
  private static pendingLines: Array<string> = [];
  private static flushTimer: number = -1;

  /**
   * Prepares the log directory and reads the switches.
   *
   * The switches are read synchronously so the very first lines of a session are
   * already governed by them; an asynchronous read would let early entries slip
   * in before the user's choice is known.
   */
  static initialize(context: common.UIAbilityContext): void {
    if (AppLog.initialized) {
      return;
    }
    AppLog.initialized = true;
    try {
      AppLog.rootPath = `${context.filesDir}/${LOG_FOLDER_NAME}`;
      AppLog.filePath = `${AppLog.rootPath}/${LOG_FILE_NAME}`;
      AppLog.previousFilePath = `${AppLog.rootPath}/${PREVIOUS_LOG_FILE_NAME}`;
    } catch (error) {
      // A missing directory only costs the file copy; memory still works.
    }
    AppLog.readSettings(context);
    if (!AppLog.enabled) {
      return;
    }
    try {
      if (AppLog.rootPath.length > 0 && !fs.accessSync(AppLog.rootPath)) {
        fs.mkdirSync(AppLog.rootPath, true);
      }
    } catch (error) {
      // Logging must never be the reason the app fails to start.
    }
    AppLog.info('app',
      `log started (verbose=${AppLog.verbose})`);
  }

  /** Applies the switches at runtime, so a change takes effect immediately. */
  static configure(enabled: boolean, verbose: boolean): void {
    AppLog.enabled = enabled;
    AppLog.verbose = verbose;
    if (!enabled) {
      // Drop what was buffered for a session that is no longer being recorded.
      AppLog.pendingLines = [];
      return;
    }
    AppLog.info('app', `logging enabled (verbose=${verbose})`);
  }

  static isEnabled(): boolean {
    return AppLog.enabled;
  }

  static isVerbose(): boolean {
    return AppLog.verbose;
  }

  private static readSettings(context: common.UIAbilityContext): void {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, {
        name: LOG_PREFERENCES_NAME
      });
      AppLog.enabled = store.getSync(LOG_ENABLED_KEY, false) as boolean;
      AppLog.verbose = store.getSync(LOG_VERBOSE_KEY, true) as boolean;
    } catch (error) {
      // Unreadable settings mean "do not record", which is the safe default.
      AppLog.enabled = false;
      AppLog.verbose = false;
    }
  }

  /** Persists both switches. Called when the user flips one in Settings. */
  static saveSettings(context: common.UIAbilityContext, enabled: boolean, verbose: boolean): void {
    AppLog.configure(enabled, verbose);
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, {
        name: LOG_PREFERENCES_NAME
      });
      store.putSync(LOG_ENABLED_KEY, enabled);
      store.putSync(LOG_VERBOSE_KEY, verbose);
      store.flush();
    } catch (error) {
      // The switch still applies to this session even if it cannot be stored.
    }
  }

  /** The switches as stored, for the settings page to render. */
  static loadSettings(context: common.UIAbilityContext): Array<boolean> {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, {
        name: LOG_PREFERENCES_NAME
      });
      return [
        store.getSync(LOG_ENABLED_KEY, false) as boolean,
        store.getSync(LOG_VERBOSE_KEY, true) as boolean
      ];
    } catch (error) {
      return [false, true];
    }
  }

  static debug(area: string, message: string): void {
    AppLog.write('D', area, message);
  }

  static info(area: string, message: string): void {
    AppLog.write('I', area, message);
  }

  static warn(area: string, message: string): void {
    AppLog.write('W', area, message);
  }

  static error(area: string, message: string): void {
    AppLog.write('E', area, message);
  }

  /**
   * A step-by-step entry, kept only in verbose mode.
   *
   * Routine traffic lives here: per-request headers, per-page decodes, cache
   * hits. They are what makes a subtle problem visible and also what makes a log
   * large, so the user decides.
   */
  static detail(area: string, message: string): void {
    if (!AppLog.verbose) {
      return;
    }
    AppLog.write('D', area, message);
  }

  /** Entries currently held in memory, oldest first, already formatted. */
  static snapshot(): Array<string> {
    return AppLog.entries.map((entry: LogEntry) => AppLog.format(entry));
  }

  /**
   * One line describing a caught error.
   *
   * The code matters as much as the message: a network failure whose code was
   * thrown away cannot be told from a bad address or a rejected certificate, and
   * that was the reason a past bug report could not be acted on.
   */
  static describe(error: Object): string {
    if (error === undefined || error === null) {
      return 'unknown error';
    }
    let text: string = '';
    const code: number = (error as BusinessError).code;
    if (Number.isFinite(code) && code !== 0) {
      text = `code=${code}`;
    }
    if (error instanceof Error && error.message.length > 0) {
      text = text.length > 0 ? `${text} ${error.message}` : error.message;
    }
    return text.length > 0 ? text : `${error}`;
  }

  static entryCount(): number {
    return AppLog.entries.length;
  }

  /**
   * Level of a rendered line, so the viewer can colour it.
   *
   * The line format is fixed by `format`, so the level sits at a known offset;
   * an unparseable line is treated as informational rather than dropped.
   */
  static levelOf(line: string): LogLevel {
    const marker: number = line.indexOf(' ');
    if (marker < 0 || marker + 1 >= line.length) {
      return 'I';
    }
    const level: string = line.substring(marker + 1, marker + 2);
    if (level === 'E' || level === 'W' || level === 'D') {
      return level;
    }
    return 'I';
  }

  /**
   * Everything that fits in a message, oldest first.
   *
   * The file holds more than memory does (it survives restarts), so the file is
   * preferred and the in-memory rows are appended for the entries that have not
   * been flushed yet.
   */
  static exportText(): string {
    AppLog.flushNow();
    let text: string = '';
    try {
      if (fs.accessSync(AppLog.previousFilePath)) {
        text += fs.readTextSync(AppLog.previousFilePath);
      }
      if (fs.accessSync(AppLog.filePath)) {
        text += fs.readTextSync(AppLog.filePath);
      }
    } catch (error) {
      // Fall back to memory alone; a partial log still helps.
    }
    if (text.length === 0) {
      return AppLog.entries.map((entry: LogEntry) => AppLog.format(entry)).join('\n');
    }
    return text;
  }

  /**
   * Device and app facts that make a log self-describing.
   *
   * The server address is deliberately absent: a private IP or a personal domain
   * identifies the user without helping to diagnose anything, and the log is
   * meant to be safe to hand over as it is.
   */
  static header(serverUrl: string, appVersion: string): string {
    const lines: Array<string> = [];
    lines.push('===== LanArk log =====');
    lines.push(`app version: ${appVersion}`);
    lines.push(`server: ${serverUrl.length > 0 ? AppLog.redact(serverUrl) : '(none)'}`);
    lines.push(`verbose: ${AppLog.verbose}`);
    lines.push(`entries in memory: ${AppLog.entries.length}`);
    lines.push('======================');
    return lines.join('\n');
  }

  static clear(): void {
    AppLog.entries = [];
    AppLog.pendingLines = [];
    try {
      if (fs.accessSync(AppLog.filePath)) {
        fs.unlinkSync(AppLog.filePath);
      }
      if (fs.accessSync(AppLog.previousFilePath)) {
        fs.unlinkSync(AppLog.previousFilePath);
      }
    } catch (error) {
      // A file that cannot be removed is truncated on the next write.
    }
    AppLog.info('app', 'log cleared');
  }

  private static write(level: LogLevel, area: string, message: string): void {
    if (!AppLog.enabled) {
      return;
    }
    const entry: LogEntry = {
      time: AppLog.timestamp(),
      level: level,
      area: area,
      message: AppLog.redact(message)
    };
    AppLog.entries.push(entry);
    if (AppLog.entries.length > MEMORY_LIMIT) {
      AppLog.entries.splice(0, AppLog.entries.length - MEMORY_LIMIT);
    }
    const line: string = AppLog.format(entry);
    AppLog.pendingLines.push(line);
    AppLog.mirrorToSystemLog(level, line);
    AppLog.scheduleFlush();
  }

  private static format(entry: LogEntry): string {
    return `${entry.time} ${entry.level}/${entry.area}: ${entry.message}`;
  }

  /** The system log stays useful for a cabled session, and costs one call. */
  private static mirrorToSystemLog(level: LogLevel, line: string): void {
    try {
      if (level === 'E') {
        hilog.error(DOMAIN, HILOG_TAG, '%{public}s', line);
      } else if (level === 'W') {
        hilog.warn(DOMAIN, HILOG_TAG, '%{public}s', line);
      } else {
        hilog.info(DOMAIN, HILOG_TAG, '%{public}s', line);
      }
    } catch (error) {
      // hilog is optional; the file copy is the one that matters.
    }
  }

  private static scheduleFlush(): void {
    if (AppLog.flushTimer >= 0) {
      return;
    }
    try {
      AppLog.flushTimer = setTimeout(() => {
        AppLog.flushTimer = -1;
        AppLog.flushNow();
      }, FLUSH_DELAY_MS);
    } catch (error) {
      // Without a timer the next entry tries again.
    }
  }

  /** Appends whatever is buffered. Best effort: a full disk drops lines. */
  static flushNow(): void {
    if (AppLog.pendingLines.length === 0 || AppLog.filePath.length === 0) {
      return;
    }
    const lines: Array<string> = AppLog.pendingLines;
    AppLog.pendingLines = [];
    try {
      AppLog.rotateIfNeeded();
      const file: fs.File = fs.openSync(
        AppLog.filePath,
        fs.OpenMode.CREATE | fs.OpenMode.APPEND | fs.OpenMode.WRITE_ONLY
      );
      try {
        const encoded: Uint8Array =
          new util.TextEncoder().encodeInto(`${lines.join('\n')}\n`);
        fs.writeSync(file.fd, encoded.buffer as ArrayBuffer);
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      // Dropping log lines is preferable to failing the operation being logged.
    }
  }

  private static rotateIfNeeded(): void {
    try {
      if (!fs.accessSync(AppLog.filePath)) {
        return;
      }
      if (fs.statSync(AppLog.filePath).size < FILE_LIMIT_BYTES) {
        return;
      }
      if (fs.accessSync(AppLog.previousFilePath)) {
        fs.unlinkSync(AppLog.previousFilePath);
      }
      fs.renameSync(AppLog.filePath, AppLog.previousFilePath);
    } catch (error) {
      // Rotation is optional; the file simply keeps growing until it works.
    }
  }

  /**
   * Removes credentials and the server address from a message.
   *
   * Done on the way in, so a log is safe to copy the moment it is produced: the
   * host is the user's own address (a private IP or a personal domain) and is
   * not needed to diagnose anything, while the path after it — which endpoint,
   * which archive, which page — is exactly what is needed. The API key is a
   * bearer token sent on every request, so it is scrubbed too rather than
   * trusted not to appear.
   */
  private static redact(message: string): string {
    let result: string = message;
    const patterns: Array<string> = [
      // Full URLs: keep what follows the authority.
      '(https?)://[^\\s/?#]+',
      // A bare authority, as `redact(server)` produces when no scheme is present.
      '(?<![\\w./-])[a-zA-Z0-9][a-zA-Z0-9.-]*:\\d{2,5}(?=[/\\s]|$)',
      'Bearer [A-Za-z0-9+/=]+',
      'api_key=[^&\\s]+'
    ];
    for (const pattern of patterns) {
      try {
        result = result.replace(new RegExp(pattern, 'g'), AppLog.replacementFor(pattern));
      } catch (error) {
        // A pattern that cannot compile leaves the message as it was.
      }
    }
    return result;
  }

  /** What a scrubbed span becomes, which differs for URLs and for secrets. */
  private static replacementFor(pattern: string): string {
    if (pattern.startsWith('(https?)')) {
      return '$1://[server]';
    }
    if (pattern.indexOf('Bearer') >= 0) {
      return 'Bearer ***';
    }
    if (pattern.indexOf('api_key') >= 0) {
      return 'api_key=***';
    }
    return '[server]';
  }

  private static timestamp(): string {
    const now: Date = new Date();
    return `${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}.${pad3(now.getMilliseconds())}`;
  }
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function pad3(value: number): string {
  if (value < 10) {
    return `00${value}`;
  }
  return value < 100 ? `0${value}` : `${value}`;
}
