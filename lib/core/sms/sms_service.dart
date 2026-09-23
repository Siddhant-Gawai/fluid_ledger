import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sms_parser.dart';

/// Inbox SMS → parsed debit transactions with **cursor + overlap** sync and **fingerprint** dedupe.
class SmsService {
  final SmsQuery _query = SmsQuery();

  /// Legacy: wall-clock “last scan” — migrated once into [_highWaterKey].
  static const _legacyLastSyncKey = 'last_sms_sync_timestamp';

  /// Max [SmsMessage.date] seen in the last successful inbox read (device timeline).
  static const _highWaterKey = 'sms_sync_high_water_ms';

  /// Stored [SmsParser.parserVersion] after last successful scan.
  static const _parserVersionKey = 'sms_sync_parser_version';

  /// Re-scan this far behind high-water to catch delayed / duplicate SMS and parser updates.
  static const Duration _overlap = Duration(hours: 72);

  Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async {
    return await Permission.sms.isGranted;
  }

  /// High-water mark from the last inbox read (latest SMS `date` on device), if any.
  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_highWaterKey) ?? prefs.getInt(_legacyLastSyncKey);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Inclusive lower bound for which messages to consider on this run.
  Future<DateTime> _resolveCutoff(SharedPreferences prefs, int days) async {
    final wideBack = DateTime.now().subtract(Duration(days: days));
    final storedVer = prefs.getInt(_parserVersionKey) ?? 0;

    // Parser upgrade → one full backfill inside [days] so new rules apply to history.
    if (storedVer < SmsParser.parserVersion) {
      return wideBack;
    }

    final hw = prefs.getInt(_highWaterKey);
    if (hw != null) {
      final tail = DateTime.fromMillisecondsSinceEpoch(hw).subtract(_overlap);
      return tail.isBefore(wideBack) ? wideBack : tail;
    }

    final legacyMs = prefs.getInt(_legacyLastSyncKey);
    if (legacyMs != null) {
      final tail = DateTime.fromMillisecondsSinceEpoch(legacyMs).subtract(_overlap);
      await prefs.remove(_legacyLastSyncKey);
      return tail.isBefore(wideBack) ? wideBack : tail;
    }

    return wideBack;
  }

  /// Read inbox SMS, parse debits, **dedupe** bank+UPI doubles, chronological order.
  Future<List<ParsedSmsTransaction>> getRecentTransactions({int days = 90}) async {
    if (!await hasPermission()) return [];

    final prefs = await SharedPreferences.getInstance();
    final cutoff = await _resolveCutoff(prefs, days);

    final messages = await _query.querySms(
      kinds: [SmsQueryKind.inbox],
      sort: true,
    );

    var maxSeenMs = 0;
    for (final sms in messages) {
      final d = sms.date;
      if (d != null && d.millisecondsSinceEpoch > maxSeenMs) {
        maxSeenMs = d.millisecondsSinceEpoch;
      }
    }

    final inWindow = <SmsMessage>[];
    for (final sms in messages) {
      final body = sms.body ?? '';
      final d = sms.date;
      if (d == null || body.isEmpty) continue;
      if (d.isBefore(cutoff)) continue;
      inWindow.add(sms);
    }

    inWindow.sort((a, b) => a.date!.compareTo(b.date!));

    // Optional: stable order within bank thread, then global time (thread id when present).
    inWindow.sort((a, b) {
      final ta = a.threadId ?? -1;
      final tb = b.threadId ?? -1;
      if (ta != tb) return ta.compareTo(tb);
      return a.date!.compareTo(b.date!);
    });

    final bestByFingerprint = <String, ParsedSmsTransaction>{};
    for (final sms in inWindow) {
      final tx = SmsParser.parse(sms.body ?? '', sms.address ?? '', sms.date!);
      if (tx == null || tx.type != 'debit') continue;
      final fp = SmsParser.fingerprint(tx);
      final prev = bestByFingerprint[fp];
      bestByFingerprint[fp] = prev == null ? tx : SmsParser.pickRicher(prev, tx);
    }

    final out = bestByFingerprint.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (maxSeenMs > 0) {
      await prefs.setInt(_highWaterKey, maxSeenMs);
    }
    await prefs.setInt(_parserVersionKey, SmsParser.parserVersion);

    return out;
  }

  /// Clears sync cursors so the next run scans the full [days] window again.
  Future<List<ParsedSmsTransaction>> fullRescan({int days = 90}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_highWaterKey);
    await prefs.remove(_legacyLastSyncKey);
    await prefs.remove(_parserVersionKey);
    return getRecentTransactions(days: days);
  }
}
