import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://ujgjyqxhmpzbtyjoafga.supabase.co';
const supabaseAnonKey = 'sb_publishable_cGFtwRkGgpfHlP0CCxzyCg_ri2vn8bo';

/// Use this after [Supabase.initialize] (singleton). Prefer [supabaseClientProvider] in widgets/notifiers with [Ref].
SupabaseClient get appSupabaseClient => Supabase.instance.client;

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return appSupabaseClient;
});
