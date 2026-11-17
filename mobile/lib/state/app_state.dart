import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/recipe.dart';
import '../models/tracking.dart';
import '../models/user_profile.dart';
import '../services/assistant_service.dart';
import '../services/auth_service.dart';
import '../services/personalization_service.dart';
import '../services/recipe_service.dart';
import '../services/storage_service.dart';

/// Single source of truth for the whole app with strict multi-user & guest isolation.
///
/// Every screen reads from here via `context.watch<AppState>()`, so the
/// dashboard, recipe list, progress screens, and user profile can never
/// disagree about the active account, logged meals, or personalized recommendations.
class AppState extends ChangeNotifier {
  AppState({
    RecipeService? recipeService,
    AuthService? authService,
    StorageService? storage,
    AssistantService? assistant,
    PersonalizationService? personalization,
  })  : _recipes = recipeService ?? RecipeService(),
        _auth = authService ?? AuthService(baseUrl: recipeService?.baseUrl),
        _storage = storage ?? StorageService(),
        _assistant = assistant ?? AssistantService(),
        _personalization = personalization ?? PersonalizationService();

  final RecipeService _recipes;
  final AuthService _auth;
  final StorageService _storage;
  final AssistantService _assistant;
  final PersonalizationService _personalization;

  RecipeService get recipeService => _recipes;
  AuthService get authService => _auth;
  AssistantService get assistantService => _assistant;

  // -------------------- state --------------------

  bool _ready = false;
  bool get isReady => _ready;

  String? _userId;
  String? get userId => _userId;

  bool _signedIn = false;
  bool get isSignedIn => _signedIn;

  bool _isGuest = false;
  bool get isGuest => _isGuest;

  bool _onboarded = false;
  bool get isOnboarded => _onboarded;

  UserProfile _profile = UserProfile.initial();
  UserProfile get profile => _profile;

  List<Recipe> _allRecipes = const [];
  List<Recipe> get allRecipes => _allRecipes;

  /// Raw output from the trained model / local fallback - not yet personalized.
  List<ScoredRecipe> _baseRecommendations = const [];

  /// The list every screen should render: the model's ranking, re-ordered
  /// by what the active user has actually favourited and logged.
  List<ScoredRecipe> get recommendations => _personalized.items;

  PersonalizedRecommendations get _personalized => _personalization.personalize(
        _baseRecommendations,
        meals: _meals,
        favouriteIds: _favourites,
        allRecipes: _allRecipes,
      );

  /// Human-readable explanation of the personalisation applied above.
  String? get personalizationInsight => _personalized.insight;

  ScoreSource _scoreSource = ScoreSource.localFallback;
  ScoreSource get scoreSource => _scoreSource;

  bool _loadingRecommendations = false;
  bool get isLoadingRecommendations => _loadingRecommendations;

  String? _recommendationError;
  String? get recommendationError => _recommendationError;

  final List<MealLog> _meals = [];
  List<MealLog> get meals => List.unmodifiable(_meals);

  final List<Recipe> _generatedRecipes = [];
  List<Recipe> get generatedRecipes => List.unmodifiable(_generatedRecipes);

  bool _generatingRecipe = false;
  bool get isGeneratingRecipe => _generatingRecipe;

  String? _generationError;
  String? get generationError => _generationError;

  Recipe? _lastGeneratedRecipe;
  Recipe? get lastGeneratedRecipe => _lastGeneratedRecipe;

  final List<WeightEntry> _weights = [];
  List<WeightEntry> get weightEntries => List.unmodifiable(_weights);

  final Set<String> _favourites = {};
  Set<String> get favourites => Set.unmodifiable(_favourites);

  final List<ChatMessage> _chat = [];
  List<ChatMessage> get chat => List.unmodifiable(_chat);

  bool _assistantThinking = false;
  bool get isAssistantThinking => _assistantThinking;

  String get apiBaseUrl => _recipes.baseUrl;
  bool get assistantUsesLlm => _assistant.hasApiKey;

  // -------------------- lifecycle --------------------

  /// Loads the bundled dataset and the active user's persisted state.
  Future<void> bootstrap() async {
    try {
      await _storage.cleanLegacyKeys();
      _allRecipes = await _recipes.loadRecipes();

      final savedBase = await _storage.loadApiBase();
      if (savedBase != null && savedBase.isNotEmpty) {
        _recipes.baseUrl = savedBase;
        _auth.baseUrl = savedBase;
      }

      _signedIn = await _storage.isSignedIn();
      _isGuest = await _storage.isGuest();
      _userId = await _storage.loadCurrentUserId();

      if (_signedIn && _userId != null && _userId!.isNotEmpty) {
        // Load user-scoped data
        final savedProfile = await _storage.loadProfile(_userId);
        if (savedProfile != null) {
          _profile = savedProfile;
        }

        _onboarded = await _storage.isOnboarded(_userId);

        _meals
          ..clear()
          ..addAll(await _storage.loadMeals(_userId));
        _weights
          ..clear()
          ..addAll(await _storage.loadWeights(_userId));
        _favourites
          ..clear()
          ..addAll(await _storage.loadFavourites(_userId));
        _chat
          ..clear()
          ..addAll(await _storage.loadChat(_userId));
        _generatedRecipes
          ..clear()
          ..addAll(await _storage.loadGeneratedRecipes(_userId));

        // Seed initial weight entry if onboarding is completed
        if (_weights.isEmpty && _onboarded) {
          _weights.add(WeightEntry(
            id: _newId(),
            weightKg: _profile.weightKg,
            recordedAt: DateTime.now(),
          ));
          await _storage.saveWeights(_userId, _weights);
        }

        // Trigger background sync with backend for registered users
        if (!_isGuest && !_userId!.startsWith('guest')) {
          unawaited(_syncUserDataWithBackend(_userId!));
        }
      } else {
        // Ensure clean state if not signed in
        _signedIn = false;
        _isGuest = false;
        _userId = null;
        _onboarded = false;
        _profile = UserProfile.initial();
        _meals.clear();
        _weights.clear();
        _favourites.clear();
        _chat.clear();
        _generatedRecipes.clear();
      }
    } catch (e, st) {
      debugPrint('[LoseIt] Error during bootstrap: $e\n$st');
    } finally {
      _ready = true;
      notifyListeners();
    }

    if (_onboarded) {
      unawaited(refreshRecommendations());
    }
  }

  /// Syncs remote MongoDB / backend database assets for this user into local state.
  Future<void> _syncUserDataWithBackend(String uid) async {
    try {
      final syncData = await _auth.fetchUserSyncData(uid);
      if (syncData != null && _userId == uid) {
        bool changed = false;

        // Profile sync
        if (syncData['profile'] is Map<String, dynamic>) {
          try {
            final remoteProfile = UserProfile.fromJson(
                syncData['profile'] as Map<String, dynamic>);
            if (remoteProfile.name.isNotEmpty &&
                remoteProfile.name != 'Guest') {
              _profile = remoteProfile;
              await _storage.saveProfile(uid, _profile);
              changed = true;
            }
          } catch (_) {}
        }

        // Onboarded status sync
        if (syncData['is_onboarded'] is bool) {
          final remoteOnboarded = syncData['is_onboarded'] as bool;
          if (remoteOnboarded != _onboarded) {
            _onboarded = remoteOnboarded;
            await _storage.setOnboarded(uid, _onboarded);
            changed = true;
          }
        }

        // Meals sync - merge remote logs
        if (syncData['meal_logs'] is List) {
          final remoteMeals = (syncData['meal_logs'] as List)
              .map((e) => MealLog.fromJson(e as Map<String, dynamic>))
              .toList();

          final existingIds = _meals.map((m) => m.id).toSet();
          for (final m in remoteMeals) {
            if (m.id.isNotEmpty && !existingIds.contains(m.id)) {
              _meals.add(m);
              changed = true;
            }
          }
          if (changed) {
            await _storage.saveMeals(uid, _meals);
          }
        }

        // Weight entries sync
        if (syncData['weight_logs'] is List) {
          final remoteWeights = (syncData['weight_logs'] as List)
              .map((e) => WeightEntry.fromJson(e as Map<String, dynamic>))
              .toList();

          final existingIds = _weights.map((w) => w.id).toSet();
          for (final w in remoteWeights) {
            if (w.id.isNotEmpty && !existingIds.contains(w.id)) {
              _weights.add(w);
              changed = true;
            }
          }
          if (changed) {
            await _storage.saveWeights(uid, _weights);
          }
        }

        // Favorites sync
        if (syncData['favorites'] is List) {
          final remoteFavs = (syncData['favorites'] as List)
              .map((e) => '$e')
              .toSet();
          if (remoteFavs.isNotEmpty) {
            _favourites.addAll(remoteFavs);
            await _storage.saveFavourites(uid, _favourites);
            changed = true;
          }
        }

        if (changed) {
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[LoseIt] Background user sync failed: $e');
    }
  }

  // -------------------- authentication --------------------

  /// Registers a brand new user account with clean isolated data.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final result = await _auth.register(
      name: name,
      email: email,
      password: password,
    );

    if (result.success) {
      // 1. Flush previous user memory completely
      _meals.clear();
      _weights.clear();
      _favourites.clear();
      _chat.clear();
      _generatedRecipes.clear();
      _baseRecommendations = const [];

      // 2. Set new user state
      _userId = result.userId;
      _isGuest = false;
      _signedIn = true;
      _onboarded = false;

      final cleanName = (result.name != null && result.name!.isNotEmpty)
          ? result.name!
          : name.trim();
      final cleanEmail = (result.email != null && result.email!.isNotEmpty)
          ? result.email!
          : email.trim().toLowerCase();

      _profile = UserProfile.initial().copyWith(
        name: cleanName,
        email: cleanEmail,
      );

      // 3. Persist scoped user state
      await _storage.saveCurrentUserId(_userId);
      await _storage.setIsGuest(false);
      await _storage.setSignedIn(true);
      await _storage.setOnboarded(_userId, false);
      await _storage.saveProfile(_userId, _profile);
      await _storage.saveMeals(_userId, []);
      await _storage.saveWeights(_userId, []);
      await _storage.saveFavourites(_userId, {});
      await _storage.saveChat(_userId, []);
      await _storage.saveGeneratedRecipes(_userId, []);

      notifyListeners();
    }
    return result;
  }

  /// Logs into an existing user account and restores all of that user's data.
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final result = await _auth.login(
      email: email,
      password: password,
    );

    if (result.success) {
      // 1. Flush previous user memory completely
      _meals.clear();
      _weights.clear();
      _favourites.clear();
      _chat.clear();
      _generatedRecipes.clear();
      _baseRecommendations = const [];

      // 2. Set active user identifiers
      _userId = result.userId;
      _isGuest = false;
      _signedIn = true;

      // 3. Load that user's scoped local data
      final localProfile = await _storage.loadProfile(_userId);
      final localOnboarded = await _storage.isOnboarded(_userId);
      final localMeals = await _storage.loadMeals(_userId);
      final localWeights = await _storage.loadWeights(_userId);
      final localFavourites = await _storage.loadFavourites(_userId);
      final localChat = await _storage.loadChat(_userId);
      final localGenerated = await _storage.loadGeneratedRecipes(_userId);

      _onboarded = result.isOnboarded || localOnboarded;

      final accountName = (result.name != null &&
              result.name!.isNotEmpty &&
              result.name != 'Guest')
          ? result.name!
          : (result.email?.split('@').first ?? 'Friend');
      final accountEmail = (result.email != null && result.email!.isNotEmpty)
          ? result.email!
          : email.trim().toLowerCase();

      if (result.profile != null) {
        _profile = result.profile!.copyWith(
          name: (result.profile!.name.isNotEmpty &&
                  result.profile!.name != 'Guest')
              ? result.profile!.name
              : accountName,
          email: result.profile!.email.isNotEmpty
              ? result.profile!.email
              : accountEmail,
        );
      } else if (localProfile != null) {
        _profile = localProfile.copyWith(
          name: localProfile.name.isNotEmpty && localProfile.name != 'Guest'
              ? localProfile.name
              : accountName,
          email: localProfile.email.isNotEmpty
              ? localProfile.email
              : accountEmail,
        );
      } else {
        _profile = UserProfile.initial().copyWith(
          name: accountName,
          email: accountEmail,
        );
      }

      // Populate memory lists from local scoped storage
      _meals.addAll(localMeals);
      _weights.addAll(localWeights);
      _favourites.addAll(localFavourites);
      _chat.addAll(localChat);
      _generatedRecipes.addAll(localGenerated);

      // Save active session pointers
      await _storage.saveCurrentUserId(_userId);
      await _storage.setIsGuest(false);
      await _storage.setSignedIn(true);
      await _storage.setOnboarded(_userId, _onboarded);
      await _storage.saveProfile(_userId, _profile);

      // Sync latest data from backend in background
      if (!_userId!.startsWith('guest')) {
        unawaited(_syncUserDataWithBackend(_userId!));
      }

      notifyListeners();

      if (_onboarded) {
        unawaited(refreshRecommendations());
      }
    }
    return result;
  }

  /// Starts or resumes an isolated Guest session.
  Future<void> continueAsGuest() async {
    // 1. Flush previous user memory
    _meals.clear();
    _weights.clear();
    _favourites.clear();
    _chat.clear();
    _generatedRecipes.clear();
    _baseRecommendations = const [];

    _userId = 'guest_user';
    _isGuest = true;
    _signedIn = true;

    // 2. Load guest-scoped data
    final guestProfile = await _storage.loadProfile('guest_user');
    _onboarded = await _storage.isOnboarded('guest_user');
    _profile = guestProfile ??
        UserProfile.initial().copyWith(name: 'Guest', email: '');

    _meals.addAll(await _storage.loadMeals('guest_user'));
    _weights.addAll(await _storage.loadWeights('guest_user'));
    _favourites.addAll(await _storage.loadFavourites('guest_user'));
    _chat.addAll(await _storage.loadChat('guest_user'));
    _generatedRecipes.addAll(await _storage.loadGeneratedRecipes('guest_user'));

    await _storage.saveCurrentUserId('guest_user');
    await _storage.setIsGuest(true);
    await _storage.setSignedIn(true);
    await _storage.saveProfile('guest_user', _profile);

    notifyListeners();

    if (_onboarded) {
      unawaited(refreshRecommendations());
    }
  }

  /// Signs out of the current account, flushes active RAM state, and returns to login.
  Future<void> signOut() async {
    // Save any pending in-memory state before wiping RAM
    if (_userId != null && _userId!.isNotEmpty) {
      await _storage.saveMeals(_userId, _meals);
      await _storage.saveWeights(_userId, _weights);
      await _storage.saveFavourites(_userId, _favourites);
      await _storage.saveProfile(_userId, _profile);
      await _storage.saveGeneratedRecipes(_userId, _generatedRecipes);
    }

    // Clear active session pointers (does NOT delete user's historical data)
    await _storage.clearSession();

    _userId = null;
    _isGuest = false;
    _signedIn = false;
    _onboarded = false;
    _profile = UserProfile.initial();
    _meals.clear();
    _weights.clear();
    _favourites.clear();
    _chat.clear();
    _generatedRecipes.clear();
    _baseRecommendations = const [];

    notifyListeners();
  }

  // -------------------- profile --------------------

  Future<void> saveProfile(UserProfile profile,
      {bool completeOnboarding = false}) async {
    final effectiveName = (profile.name.isNotEmpty && profile.name != 'Guest')
        ? profile.name
        : (_profile.name.isNotEmpty ? _profile.name : 'Guest');
    final effectiveEmail =
        profile.email.isNotEmpty ? profile.email : _profile.email;

    _profile = profile.copyWith(
      name: effectiveName,
      email: effectiveEmail,
    );
    await _storage.saveProfile(_userId, _profile);

    if (completeOnboarding && !_onboarded) {
      _onboarded = true;
      await _storage.setOnboarded(_userId, true);
      if (_weights.isEmpty) {
        final initialWeight = WeightEntry(
          id: _newId(),
          weightKg: _profile.weightKg,
          recordedAt: DateTime.now(),
        );
        _weights.add(initialWeight);
        await _storage.saveWeights(_userId, _weights);

        if (_userId != null && !_isGuest && !_userId!.startsWith('guest')) {
          unawaited(_auth.saveWeight(_userId!, initialWeight));
        }
      }
    }

    // Sync to MongoDB in background for registered user accounts
    if (_userId != null && !_isGuest && !_userId!.startsWith('guest')) {
      unawaited(_auth.saveUserProfile(_userId!, _profile));
    }

    notifyListeners();
    await refreshRecommendations();
  }

  // -------------------- recommendations --------------------

  Future<void> refreshRecommendations({String? mealType}) async {
    _loadingRecommendations = true;
    _recommendationError = null;
    notifyListeners();

    try {
      final result = await _recipes.recommend(
        _profile,
        topN: 40,
        mealType: mealType,
      );
      _baseRecommendations = result.items;
      _scoreSource = result.source;
    } catch (e) {
      _recommendationError = 'Could not build recommendations: $e';
      _baseRecommendations = const [];
    } finally {
      _loadingRecommendations = false;
      notifyListeners();
    }
  }

  Future<void> setApiBaseUrl(String value) async {
    final clean = value.trim();
    _recipes.baseUrl = clean;
    _auth.baseUrl = clean;
    await _storage.saveApiBase(clean);
    notifyListeners();
    await refreshRecommendations();
  }

  void setAssistantApiKey(String? key) {
    _assistant.apiKey = key;
    notifyListeners();
  }

  /// The single dish shown in the dashboard's "Recommended" card, picked
  /// for the meal slot that matches the current time of day.
  ScoredRecipe? get featuredRecipe {
    final list = recommendations;
    if (list.isEmpty) return null;
    final slot = currentMealSlot;
    for (final s in list) {
      if (s.recipe.mealType == slot) return s;
    }
    return list.first;
  }

  String get currentMealSlot {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Breakfast';
    if (hour < 16) return 'Lunch';
    if (hour < 21) return 'Dinner';
    return 'Snack';
  }

  Recipe? recipeById(String id) {
    for (final r in _generatedRecipes) {
      if (r.id == id) return r;
    }
    for (final r in _allRecipes) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Generates a brand-new Sri Lankan recipe from scratch taking inspiration from the 300 database.
  Future<GeneratedRecipeResult?> generateRecipe(String prompt, {String? mealType}) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return null;

    _generatingRecipe = true;
    _generationError = null;
    notifyListeners();

    try {
      final result = await _recipes.generateRecipe(
        prompt: cleanPrompt,
        profile: _profile,
        mealType: mealType,
      );

      _lastGeneratedRecipe = result.recipe;
      if (!_generatedRecipes.any((r) => r.id == result.recipe.id)) {
        _generatedRecipes.insert(0, result.recipe);
        await _storage.saveGeneratedRecipes(_userId, _generatedRecipes);
      }
      return result;
    } catch (e) {
      _generationError = 'Failed to generate recipe: $e';
      return null;
    } finally {
      _generatingRecipe = false;
      notifyListeners();
    }
  }

  // -------------------- meal logging --------------------

  List<MealLog> get todaysMeals {
    final now = DateTime.now();
    return _meals.where((m) => _sameDay(m.loggedAt, now)).toList();
  }

  int get caloriesConsumedToday =>
      todaysMeals.fold(0, (sum, m) => sum + m.calories);

  double get proteinToday => todaysMeals.fold(0.0, (s, m) => s + m.protein);
  double get carbsToday => todaysMeals.fold(0.0, (s, m) => s + m.carbs);
  double get fatToday => todaysMeals.fold(0.0, (s, m) => s + m.fat);

  int get caloriesRemainingToday =>
      _profile.dailyCalorieTarget.round() - caloriesConsumedToday;

  double get calorieProgress {
    final target = _profile.dailyCalorieTarget;
    if (target <= 0) return 0;
    return (caloriesConsumedToday / target).clamp(0.0, 1.0);
  }

  Future<void> logMeal(Recipe recipe, {String? mealType}) async {
    final meal = MealLog(
      id: _newId(),
      recipeId: recipe.id,
      recipeName: recipe.name,
      calories: recipe.calories,
      protein: recipe.protein,
      carbs: recipe.carbs,
      fat: recipe.fat,
      mealType: mealType ?? recipe.mealType,
      loggedAt: DateTime.now(),
    );

    _meals.add(meal);
    await _storage.saveMeals(_userId, _meals);

    // Sync with backend if registered account
    if (_userId != null && !_isGuest && !_userId!.startsWith('guest')) {
      unawaited(_auth.saveMealLog(_userId!, meal));
    }

    notifyListeners();
  }

  Future<void> removeMeal(String id) async {
    _meals.removeWhere((m) => m.id == id);
    await _storage.saveMeals(_userId, _meals);

    if (_userId != null && !_isGuest && !_userId!.startsWith('guest')) {
      unawaited(_auth.deleteMealLog(_userId!, id));
    }

    notifyListeners();
  }

  // -------------------- weight tracking --------------------

  List<WeightEntry> get weightHistory {
    final sorted = List<WeightEntry>.from(_weights)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sorted;
  }

  List<WeightEntry> get weightSeries {
    final sorted = List<WeightEntry>.from(_weights)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return sorted;
  }

  double get latestWeight =>
      weightHistory.isEmpty ? _profile.weightKg : weightHistory.first.weightKg;

  double get totalWeightChange {
    final series = weightSeries;
    if (series.length < 2) return 0;
    return series.last.weightKg - series.first.weightKg;
  }

  double get weeklyWeightChange {
    final series = weightSeries;
    if (series.length < 2) return 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final recent = series.where((w) => w.recordedAt.isAfter(cutoff)).toList();
    if (recent.length < 2) return 0;
    return recent.last.weightKg - recent.first.weightKg;
  }

  Future<void> logWeight(double kg) async {
    final entry = WeightEntry(
      id: _newId(),
      weightKg: kg,
      recordedAt: DateTime.now(),
    );
    _weights.add(entry);
    await _storage.saveWeights(_userId, _weights);

    if (_userId != null && !_isGuest && !_userId!.startsWith('guest')) {
      unawaited(_auth.saveWeight(_userId!, entry));
    }

    // Keep profile in step
    _profile = _profile.copyWith(weightKg: kg);
    await _storage.saveProfile(_userId, _profile);
    if (_userId != null && !_isGuest && !_userId!.startsWith('guest')) {
      unawaited(_auth.saveUserProfile(_userId!, _profile));
    }

    notifyListeners();
    await refreshRecommendations();
  }

  // -------------------- favourites --------------------

  bool isFavourite(String recipeId) => _favourites.contains(recipeId);

  Future<void> toggleFavourite(String recipeId) async {
    if (!_favourites.remove(recipeId)) {
      _favourites.add(recipeId);
    }
    await _storage.saveFavourites(_userId, _favourites);

    if (_userId != null && !_isGuest && !_userId!.startsWith('guest')) {
      unawaited(_auth.toggleFavorite(_userId!, recipeId));
    }

    notifyListeners();
  }

  List<Recipe> get favouriteRecipes =>
      _allRecipes.where((r) => _favourites.contains(r.id)).toList();

  // -------------------- assistant --------------------

  Future<void> sendChatMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _assistantThinking) return;

    _chat.add(ChatMessage(
      role: ChatRole.user,
      text: trimmed,
      at: DateTime.now(),
    ));
    _assistantThinking = true;
    notifyListeners();

    final history = _chat
        .take(_chat.length - 1)
        .map((m) => m.text)
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed
        .toList();

    final reply = await _assistant.ask(
      question: trimmed,
      profile: _profile,
      recipes: _allRecipes,
      history: history,
    );

    _chat.add(ChatMessage(
      role: ChatRole.assistant,
      text: reply.text,
      at: DateTime.now(),
      citedRecipeIds: reply.citedRecipeIds,
    ));
    _assistantThinking = false;
    await _storage.saveChat(_userId, _chat);
    notifyListeners();
  }

  Future<void> clearChat() async {
    _chat.clear();
    await _storage.saveChat(_userId, _chat);
    notifyListeners();
  }

  // -------------------- reset --------------------

  Future<void> resetAllData() async {
    await _storage.clearAll();
    await _storage.clearSession();
    _userId = null;
    _profile = UserProfile.initial();
    _onboarded = false;
    _signedIn = false;
    _isGuest = false;
    _meals.clear();
    _weights.clear();
    _favourites.clear();
    _chat.clear();
    _generatedRecipes.clear();
    _baseRecommendations = const [];
    notifyListeners();
  }

  // -------------------- helpers --------------------

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _idCounter = 0;
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  @override
  void dispose() {
    _recipes.dispose();
    _assistant.dispose();
    super.dispose();
  }
}

/// Fire-and-forget helper so tasks run in background without blocking caller.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    debugPrint('[LoseIt] background task failed: $e');
  });
}
