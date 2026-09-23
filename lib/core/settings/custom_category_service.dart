import 'package:shared_preferences/shared_preferences.dart';

class CustomCategoryService {
  CustomCategoryService._();
  static final CustomCategoryService instance = CustomCategoryService._();

  static const _key = 'custom_categories';

  Future<List<String>> getCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? const <String>[];
    final normalized =
        list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();
    return normalized;
  }

  Future<void> addCategory(String category) async {
    final normalized = category.trim();
    if (normalized.isEmpty) return;
    final existing = await getCategories();
    if (existing.any((e) => e.toLowerCase() == normalized.toLowerCase())) {
      return;
    }
    final next = [...existing, normalized]..sort();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next);
  }
}
