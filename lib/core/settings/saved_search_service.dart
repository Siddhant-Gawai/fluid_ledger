import 'package:shared_preferences/shared_preferences.dart';

class SavedSearchService {
  SavedSearchService._();
  static final SavedSearchService instance = SavedSearchService._();

  static const _key = 'saved_transaction_searches_v1';
  static const _maxSaved = 8;

  Future<List<String>> getSavedSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? const <String>[];
    return list.where((e) => e.trim().isNotEmpty).toList(growable: false);
  }

  Future<void> saveSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    final merged = <String>[
      normalized,
      ...current.where((q) => q.toLowerCase() != normalized.toLowerCase()),
    ];
    if (merged.length > _maxSaved) {
      merged.removeRange(_maxSaved, merged.length);
    }
    await prefs.setStringList(_key, merged);
  }

  Future<void> removeSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    current.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
    await prefs.setStringList(_key, current);
  }
}
