import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/router/app_router.dart';
import '../../dashboard/presentation/screens/dashboard_screen.dart';

enum AuthState { phoneEntry, otpEntry, processing, authenticated, error, existingUser }

class AuthNotifier extends Notifier<AuthState> {
  SupabaseClient get _client => ref.read(supabaseClientProvider);

  String _phone = '';
  String _errorMessage = '';

  String get phone => _phone;
  String get errorMessage => _errorMessage;

  @override
  AuthState build() {
    final session = _client.auth.currentSession;
    if (session != null) {
      return AuthState.authenticated;
    }
    return AuthState.phoneEntry;
  }

  /// Login flow — just send OTP, no existence check
  Future<void> sendOtp(String phone) async {
    state = AuthState.processing;
    _phone = phone;
    try {
      await _client.auth.signInWithOtp(phone: phone)
          .timeout(const Duration(seconds: 15));
      state = AuthState.otpEntry;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      state = AuthState.error;
    } catch (e) {
      _errorMessage = 'Failed to send OTP. Check your connection and try again.';
      state = AuthState.error;
    }
  }

  /// Sign up flow — check if phone already registered via RPC (bypasses RLS)
  Future<void> sendSignUpOtp(String phone) async {
    state = AuthState.processing;
    _phone = phone;
    try {
      // RPC function runs with security definer, bypasses RLS
      final exists = await _client.rpc('check_phone_exists', params: {
        'phone_number': phone,
      });

      if (exists == true) {
        _errorMessage = 'This number is already registered. Please login instead.';
        state = AuthState.existingUser;
        return;
      }

      await _client.auth.signInWithOtp(phone: phone);
      state = AuthState.otpEntry;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      state = AuthState.error;
    } catch (e) {
      _errorMessage = 'Failed to send OTP. Please try again.';
      state = AuthState.error;
    }
  }

  Future<void> verifyOtp(String otp) async {
    state = AuthState.processing;
    try {
      await _client.auth.verifyOTP(
        phone: _phone,
        token: otp,
        type: OtpType.sms,
      );
      state = AuthState.authenticated;
      // Warm SQLite from Supabase before dashboard reads cache (serialized with other sync calls).
      SyncService.instance.deltaSync();
    } on AuthException catch (e) {
      _errorMessage = e.message;
      state = AuthState.error;
    } catch (e) {
      _errorMessage = 'Verification failed. Please try again.';
      state = AuthState.error;
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await SyncService.instance.clearCache();
    _phone = '';
    resetProfileCheck();
    DashboardScreenState.resetAlertFlag();
    state = AuthState.phoneEntry;
  }

  void reset() {
    _errorMessage = '';
    state = AuthState.phoneEntry;
  }

  void clearError() {
    _errorMessage = '';
    state = _phone.isEmpty ? AuthState.phoneEntry : AuthState.otpEntry;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
