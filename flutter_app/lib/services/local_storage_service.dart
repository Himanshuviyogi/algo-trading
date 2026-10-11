import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for app-level local flags.
class LocalStorageService {
  LocalStorageService._(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStorageService._(prefs);
  }

  // ── Onboarding ────────────────────────────────────────────────────────────

  static String _onboardingKey(String uid) => 'onboarding_skipped_$uid';
  static String _profileKey(String uid)    => 'profile_complete_$uid';

  bool hasSkippedOnboarding(String uid) =>
      _prefs.getBool(_onboardingKey(uid)) ?? false;

  Future<void> setOnboardingSkipped(String uid) =>
      _prefs.setBool(_onboardingKey(uid), true);

  Future<void> clearOnboardingSkipped(String uid) =>
      _prefs.remove(_onboardingKey(uid));

  // ── Profile complete cache ────────────────────────────────────────────────
  // Persists across app restarts so the router doesn't re-prompt for
  // name/email on every login once the user has already filled them in.

  bool isProfileComplete(String uid) =>
      _prefs.getBool(_profileKey(uid)) ?? false;

  Future<void> setProfileComplete(String uid) =>
      _prefs.setBool(_profileKey(uid), true);

  Future<void> clearProfileComplete(String uid) =>
      _prefs.remove(_profileKey(uid));
}
