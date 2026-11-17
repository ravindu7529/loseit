import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';
import '../models/tracking.dart';
import '../models/user_profile.dart';

/// Local persistence with strict per-user data isolation.
///
/// Each user account (and guest session) has its own scoped data keys
/// so that meal logs, weigh-ins, favourites, chats, and personalized goals
/// never leak across accounts.
class StorageService {
  static const _kCurrentUserId = 'loseit.current_user_id';
  static const _kLegacyUserId = 'loseit.user_id';
  static const _kSignedIn = 'loseit.signed_in';
  static const _kIsGuest = 'loseit.is_guest';
  static const _kApiBase = 'loseit.api_base';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  String _scopeKey(String? userId, String suffix) {
    final clean = (userId ?? '').trim();
    final scope = clean.isNotEmpty ? clean : 'guest_user';
    return 'loseit.$scope.$suffix';
  }

  /// Cleans legacy global un-scoped keys so old data never pollutes new user accounts
  Future<void> cleanLegacyKeys() async {
    final p = await _p;
    for (final legacyKey in [
      'loseit.profile',
      'loseit.onboarded',
      'loseit.meal_logs',
      'loseit.weight_entries',
      'loseit.favourites',
      'loseit.chat',
      'loseit.user_id',
    ]) {
      await p.remove(legacyKey);
    }
  }

  // -------------------- Session & Active User --------------------

  Future<String?> loadCurrentUserId() async {
    final p = await _p;
    return p.getString(_kCurrentUserId);
  }

  Future<void> saveCurrentUserId(String? id) async {
    final p = await _p;
    if (id != null && id.trim().isNotEmpty) {
      await p.setString(_kCurrentUserId, id.trim());
    } else {
      await p.remove(_kCurrentUserId);
    }
  }

  Future<bool> isSignedIn() async => (await _p).getBool(_kSignedIn) ?? false;
  Future<void> setSignedIn(bool v) async => (await _p).setBool(_kSignedIn, v);

  Future<bool> isGuest() async => (await _p).getBool(_kIsGuest) ?? false;
  Future<void> setIsGuest(bool v) async => (await _p).setBool(_kIsGuest, v);

  /// Clears active session state without deleting the user's historical data.
  Future<void> clearSession() async {
    final p = await _p;
    await p.remove(_kCurrentUserId);
    await p.remove(_kLegacyUserId);
    await p.remove(_kSignedIn);
    await p.remove(_kIsGuest);
  }

  // -------------------- User-Scoped Profile & Onboarding --------------------

  Future<UserProfile?> loadProfile(String? userId) async {
    final key = _scopeKey(userId, 'profile');
    final raw = (await _p).getString(key);
    if (raw != null) {
      try {
        return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveProfile(String? userId, UserProfile profile) async {
    final key = _scopeKey(userId, 'profile');
    await (await _p).setString(key, jsonEncode(profile.toJson()));
  }

  Future<bool> isOnboarded(String? userId) async {
    final key = _scopeKey(userId, 'onboarded');
    return (await _p).getBool(key) ?? false;
  }

  Future<void> setOnboarded(String? userId, bool v) async {
    final key = _scopeKey(userId, 'onboarded');
    await (await _p).setBool(key, v);
  }

  // -------------------- User-Scoped Tracking & History --------------------

  Future<List<MealLog>> loadMeals(String? userId) async {
    final key = _scopeKey(userId, 'meal_logs');
    return _loadList(key, MealLog.fromJson);
  }

  Future<void> saveMeals(String? userId, List<MealLog> meals) async {
    final key = _scopeKey(userId, 'meal_logs');
    await _saveList(key, meals.map((m) => m.toJson()).toList());
  }

  Future<List<WeightEntry>> loadWeights(String? userId) async {
    final key = _scopeKey(userId, 'weight_entries');
    return _loadList(key, WeightEntry.fromJson);
  }

  Future<void> saveWeights(String? userId, List<WeightEntry> entries) async {
    final key = _scopeKey(userId, 'weight_entries');
    await _saveList(key, entries.map((w) => w.toJson()).toList());
  }

  Future<List<ChatMessage>> loadChat(String? userId) async {
    final key = _scopeKey(userId, 'chat');
    return _loadList(key, ChatMessage.fromJson);
  }

  Future<void> saveChat(String? userId, List<ChatMessage> messages) async {
    final key = _scopeKey(userId, 'chat');
    await _saveList(key, messages.map((m) => m.toJson()).toList());
  }

  Future<Set<String>> loadFavourites(String? userId) async {
    final key = _scopeKey(userId, 'favourites');
    return ((await _p).getStringList(key) ?? const []).toSet();
  }

  Future<void> saveFavourites(String? userId, Set<String> ids) async {
    final key = _scopeKey(userId, 'favourites');
    await (await _p).setStringList(key, ids.toList());
  }

  Future<List<Recipe>> loadGeneratedRecipes(String? userId) async {
    final key = _scopeKey(userId, 'generated_recipes');
    return _loadList(key, Recipe.fromJson);
  }

  Future<void> saveGeneratedRecipes(String? userId, List<Recipe> recipes) async {
    final key = _scopeKey(userId, 'generated_recipes');
    await _saveList(key, recipes.map((r) => r.toJson()).toList());
  }

  // -------------------- Settings & Data Management --------------------

  Future<String?> loadApiBase() async => (await _p).getString(_kApiBase);

  Future<void> saveApiBase(String value) async =>
      (await _p).setString(_kApiBase, value);

  /// Clears all local data belonging to a specific user.
  Future<void> clearUserData(String? userId) async {
    final p = await _p;
    for (final suffix in [
      'profile',
      'onboarded',
      'meal_logs',
      'weight_entries',
      'favourites',
      'chat',
      'generated_recipes',
    ]) {
      await p.remove(_scopeKey(userId, suffix));
    }
  }

  /// Wipes all LoseIt persistent keys.
  Future<void> clearAll() async {
    final p = await _p;
    final keys = p.getKeys().where((k) => k.startsWith('loseit.')).toList();
    for (final key in keys) {
      await p.remove(key);
    }
  }

  // -------------------- Helpers --------------------

  Future<List<T>> _loadList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final raw = (await _p).getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList(growable: true);
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveList(String key, List<Map<String, dynamic>> items) async =>
      (await _p).setString(key, jsonEncode(items));
}
