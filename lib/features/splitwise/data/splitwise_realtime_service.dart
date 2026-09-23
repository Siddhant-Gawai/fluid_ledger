import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/version_sync.dart';
import '../../../core/supabase/supabase_config.dart';
import 'splitwise_projection_service.dart';

class SplitwiseInvalidation {
  final Set<String> groupIds;
  final bool groupsChanged;

  const SplitwiseInvalidation({
    required this.groupIds,
    this.groupsChanged = false,
  });
}

class SplitwiseRealtimeMapper {
  static SplitwiseInvalidation fromTableChange({
    required String table,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    String? fromNew(String key) => newRecord[key]?.toString();
    String? fromOld(String key) => oldRecord[key]?.toString();
    final groupIds = <String>{
      switch (table) {
        'split_groups' => fromNew('id') ?? fromOld('id') ?? '',
        'group_members' => fromNew('group_id') ?? fromOld('group_id') ?? '',
        'split_expenses' => fromNew('group_id') ?? fromOld('group_id') ?? '',
        'settlements' => fromNew('group_id') ?? fromOld('group_id') ?? '',
        _ => '',
      },
    }..removeWhere((id) => id.isEmpty);

    return SplitwiseInvalidation(
      groupIds: groupIds,
      groupsChanged: table == 'split_groups' || table == 'group_members',
    );
  }
}

class SplitwiseRealtimeService {
  SplitwiseRealtimeService(this._client, this._projection);

  final SupabaseClient _client;
  final SplitwiseProjectionService _projection;
  final _controller = StreamController<SplitwiseInvalidation>.broadcast();
  final Set<String> _dirtyGroupIds = <String>{};
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  Timer? _flushTimer;
  bool _started = false;
  bool _groupsChanged = false;

  Stream<SplitwiseInvalidation> get events => _controller.stream;

  void start() {
    if (_started) return;
    _started = true;
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      final event = state.event;
      if (event == AuthChangeEvent.signedOut) {
        _stopChannel();
        return;
      }
      if (_client.auth.currentSession != null) {
        _ensureChannel();
      }
    });
    if (_client.auth.currentSession != null) {
      _ensureChannel();
    }
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _authSub?.cancel();
    _authSub = null;
    await _stopChannel();
    await _controller.close();
    _started = false;
  }

  void _ensureChannel() {
    if (_channel != null) return;
    final channel = _client.channel('splitwise-realtime');
    for (final table in const [
      'split_groups',
      'group_members',
      'split_expenses',
      'settlements',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) => _handleChange(
          table,
          Map<String, dynamic>.from(payload.newRecord),
          Map<String, dynamic>.from(payload.oldRecord),
        ),
      );
    }
    channel.subscribe();
    _channel = channel;
  }

  Future<void> _stopChannel() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }

  Future<void> _handleChange(
    String table,
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) async {
    final invalidation = SplitwiseRealtimeMapper.fromTableChange(
      table: table,
      newRecord: newRecord,
      oldRecord: oldRecord,
    );

    if (table == 'split_groups') {
      VersionSync.instance.bumpVersion(SyncTable.splitGroups);
    } else if (table == 'group_members') {
      VersionSync.instance.bumpVersion(SyncTable.groupMembers);
    } else if (table == 'split_expenses') {
      VersionSync.instance.bumpVersion(SyncTable.splitExpenses);
    } else if (table == 'settlements') {
      VersionSync.instance.bumpVersion(SyncTable.settlements);
    }

    if (invalidation.groupIds.isEmpty && !invalidation.groupsChanged) return;

    _groupsChanged = _groupsChanged || invalidation.groupsChanged;
    _dirtyGroupIds.addAll(invalidation.groupIds);
    for (final groupId in invalidation.groupIds) {
      await _projection.markGroupDirty(groupId, reason: 'realtime:$table');
    }

    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 350), _flush);
  }

  Future<void> _flush() async {
    final groupIds = Set<String>.from(_dirtyGroupIds);
    final groupsChanged = _groupsChanged;
    _dirtyGroupIds.clear();
    _groupsChanged = false;

    try {
      if (groupIds.isNotEmpty) {
        await _projection.refreshGroupsFromRemote(groupIds);
      }
    } catch (e) {
      debugPrint('Splitwise realtime projection refresh failed: $e');
    }

    if (!_controller.isClosed) {
      _controller.add(
        SplitwiseInvalidation(groupIds: groupIds, groupsChanged: groupsChanged),
      );
    }
  }
}

final splitwiseRealtimeServiceProvider = Provider<SplitwiseRealtimeService>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  final projection = ref.watch(splitwiseProjectionServiceProvider);
  final service = SplitwiseRealtimeService(client, projection);
  ref.onDispose(service.dispose);
  return service;
});

final splitwiseRealtimeBootstrapProvider = Provider<void>((ref) {
  final service = ref.watch(splitwiseRealtimeServiceProvider);
  service.start();
});

final splitwiseRealtimeEventsProvider = StreamProvider<SplitwiseInvalidation>((
  ref,
) {
  final service = ref.watch(splitwiseRealtimeServiceProvider);
  return service.events;
});
