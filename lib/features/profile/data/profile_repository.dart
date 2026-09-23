import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/local_db.dart';
import '../../../core/database/version_sync.dart';
import '../../../core/supabase/supabase_config.dart';

class UserProfile {
  final String id;
  final String name;
  final int age;
  final String email;
  final String phone;
  final int avatarIndex;
  final double monthlyBudget;
  final String? createdAt;

  UserProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.email,
    required this.phone,
    this.avatarIndex = 0,
    this.monthlyBudget = 50000,
    this.createdAt,
  });

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'email': email,
      'phone': phone,
      'avatar_index': avatarIndex,
      'monthly_budget': monthlyBudget,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      age: map['age'] as int,
      email: map['email'] as String,
      phone: map['phone'] as String,
      avatarIndex: map['avatar_index'] as int? ?? 0,
      monthlyBudget: (map['monthly_budget'] as num?)?.toDouble() ?? 50000,
      createdAt: map['created_at'] as String?,
    );
  }
}

class ProfileRepository {
  final SupabaseClient _client;
  final _localDb = LocalDB.instance;

  ProfileRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  /// Get profile from local cache first
  Future<UserProfile?> getCachedProfile() async {
    try {
      final local = await _localDb.getProfile();
      if (local != null) return UserProfile.fromMap(local);
    } catch (e) { debugPrint('Local profile read failed: $e'); }
    return getProfile();
  }

  Future<UserProfile?> getProfile() async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', _userId)
        .maybeSingle();

    if (data == null) return null;
    final profile = UserProfile.fromMap(data);

    // Cache locally
    try {
      await _localDb.upsertProfile({
        'id': data['id'], 'name': data['name'], 'age': data['age'],
        'email': data['email'], 'phone': data['phone'],
        'avatar_index': data['avatar_index'] ?? 0,
        'monthly_budget': (data['monthly_budget'] as num?)?.toDouble() ?? 50000,
        'created_at': data['created_at'],
      });
    } catch (e) { debugPrint('Cache profile failed: $e'); }

    return profile;
  }

  Future<void> createProfile(UserProfile profile) async {
    await _client.from('profiles').upsert(profile.toInsertMap());
    VersionSync.instance.bumpVersion(SyncTable.profiles);
    // Update cache
    try {
      await _localDb.upsertProfile({
        'id': profile.id, 'name': profile.name, 'age': profile.age,
        'email': profile.email, 'phone': profile.phone,
        'avatar_index': profile.avatarIndex,
        'monthly_budget': profile.monthlyBudget,
        'created_at': null,
      });
    } catch (e) { debugPrint('Cache profile update failed: $e'); }
  }

  Future<void> updateProfile(UserProfile profile) async {
    await _client
        .from('profiles')
        .update(profile.toInsertMap())
        .eq('id', _userId);
    VersionSync.instance.bumpVersion(SyncTable.profiles);
    // Update cache
    try {
      await _localDb.upsertProfile({
        'id': profile.id, 'name': profile.name, 'age': profile.age,
        'email': profile.email, 'phone': profile.phone,
        'avatar_index': profile.avatarIndex,
        'monthly_budget': profile.monthlyBudget,
        'created_at': null,
      });
    } catch (e) { debugPrint('Cache profile update failed: $e'); }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ProfileRepository(client);
});
