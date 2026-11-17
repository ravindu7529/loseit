import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/recipe.dart';
import '../models/user_profile.dart';

/// Loads the recipe dataset and produces ranked recommendations.
///
/// Two scoring paths, in priority order:
///
///  1. `POST /recommend` on the FastAPI backend, which runs the trained
///     neural network. This is the real recommender.
///  2. If that request fails or times out, an on-device rule-based
///     fallback so the app still works offline.
///
/// The fallback is deliberately SIMPLER than the model's training label
/// function - it uses calorie fit and protein only, with no spice-
/// preference term. That gap is exactly what the trained model learned
/// beyond the hand-written rule, and keeping the two different is what
/// makes the baseline-vs-model comparison in the report meaningful
/// rather than circular. Do not "improve" this to match the model.
class RecipeService {
  RecipeService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? defaultBaseUrl;

  final http.Client _client;
  String _baseUrl;

  /// Android emulators reach the host machine's localhost on 10.0.2.2;
  /// every other target can use 127.0.0.1 directly.
  static String get defaultBaseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static const Duration _timeout = Duration(seconds: 10);

  String get baseUrl => _baseUrl;
  set baseUrl(String value) => _baseUrl = value.trim();

  List<Recipe>? _cache;

  /// The full 300-recipe dataset, loaded once from the bundled asset.
  /// Bundling means recipe browsing works with no network at all.
  Future<List<Recipe>> loadRecipes() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/data/recipes.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    _cache = decoded
        .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return _cache!;
  }

  /// True when the backend is up. Used to show the model-status banner.
  /// Supports adaptive fallback between 127.0.0.1 (USB/adb/web), 10.0.2.2 (emulator),
  /// and alternate ports 8000 / 8001.
  Future<bool> checkHealth() async {
    try {
      final res = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return true;
    } catch (_) {}

    final candidateUrls = <String>[];
    if (_baseUrl.contains('10.0.2.2')) {
      candidateUrls.add(_baseUrl.replaceAll('10.0.2.2', '127.0.0.1'));
    } else if (_baseUrl.contains('127.0.0.1') || _baseUrl.contains('localhost')) {
      candidateUrls.add(_baseUrl.replaceAll('127.0.0.1', '10.0.2.2').replaceAll('localhost', '10.0.2.2'));
    }
    if (_baseUrl.contains(':8000')) {
      candidateUrls.add(_baseUrl.replaceAll(':8000', ':8001'));
    }

    for (final altUrl in candidateUrls) {
      try {
        final res = await _client
            .get(Uri.parse('$altUrl/health'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          _baseUrl = altUrl;
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Ranked recommendations for [profile], trying the trained model first.
  ///
  /// [mealType] optionally narrows to Breakfast/Lunch/Dinner/Snack.
  Future<RecommendationResult> recommend(
    UserProfile profile, {
    int topN = 30,
    String? mealType,
  }) async {
    final recipes = await loadRecipes();
    return recommendWithRecipes(
      profile,
      recipes,
      topN: topN,
      mealType: mealType,
    );
  }

  /// Same as [recommend] but against a caller-supplied dataset, so the
  /// API-vs-fallback behaviour can be tested without the asset bundle.
  @visibleForTesting
  Future<RecommendationResult> recommendWithRecipes(
    UserProfile profile,
    List<Recipe> recipes, {
    int topN = 30,
    String? mealType,
  }) async {
    try {
      final scored = await _recommendFromApi(
        profile,
        recipes,
        topN: topN,
        mealType: mealType,
      );
      debugPrint('[LoseIt] Recommendations served by trained-model API.');
      return RecommendationResult(
        items: scored,
        source: ScoreSource.trainedModel,
      );
    } catch (e) {
      debugPrint('[LoseIt] API unavailable ($e) - using local rule-based fallback.');
      final scored = scoreLocally(
        profile,
        recipes,
        topN: topN,
        mealType: mealType,
      );
      return RecommendationResult(
        items: scored,
        source: ScoreSource.localFallback,
      );
    }
  }

  Future<List<ScoredRecipe>> _recommendFromApi(
    UserProfile profile,
    List<Recipe> recipes, {
    required int topN,
    String? mealType,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/recommend'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(profile.toApiRequest(topN: topN, mealType: mealType)),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw HttpException('recommend returned ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final recs = (body['recommendations'] as List?) ?? const [];
    if (recs.isEmpty) {
      throw const HttpException('recommend returned no recommendations');
    }

    // The API returns IDs and scores; the full recipe detail comes from
    // the bundled asset so both paths render from identical data.
    final byId = {for (final r in recipes) r.id: r};
    final out = <ScoredRecipe>[];
    for (final item in recs) {
      final map = item as Map<String, dynamic>;
      final recipe = byId[map['recipe_id']];
      if (recipe == null) continue;
      out.add(ScoredRecipe(
        recipe: recipe,
        score: (map['predicted_score'] as num?)?.toDouble() ?? 0,
        source: ScoreSource.trainedModel,
      ));
    }
    if (out.isEmpty) {
      throw const HttpException('no returned recipe IDs matched the local dataset');
    }
    return out;
  }

  // ---------------------------------------------------------------
  // Local rule-based fallback (see the class doc before editing).
  // ---------------------------------------------------------------

  /// Rule-based score for one recipe: calorie fit weighted 0.7 plus a
  /// protein bonus weighted 0.75, matching `baseline_score` in
  /// `backend/generate_dataset.py`.
  @visibleForTesting
  static double baselineScore(Recipe recipe, double perMealTarget) {
    final calorieFit = (100 -
            (recipe.calories - perMealTarget).abs() / perMealTarget * 100)
        .clamp(0.0, 100.0);
    final proteinBonus = recipe.protein.clamp(0.0, 40.0);
    return calorieFit * 0.7 + proteinBonus * 0.75;
  }

  /// On-device ranking used when the backend is unreachable.
  List<ScoredRecipe> scoreLocally(
    UserProfile profile,
    List<Recipe> recipes, {
    int topN = 30,
    String? mealType,
  }) {
    // Hard dietary and allergy/avoidance filter first - applied outside
    // any scoring, exactly as the backend does.
    var eligible =
        recipes.where((r) => profile.allowsRecipe(r)).toList();

    if (mealType != null) {
      final byMeal = eligible.where((r) => r.mealType == mealType).toList();
      // Only narrow when something survives, so a sparse meal type can
      // never produce an empty screen.
      if (byMeal.isNotEmpty) eligible = byMeal;
    }

    final target = profile.perMealTarget;
    final scored = eligible
        .map((r) => ScoredRecipe(
              recipe: r,
              score: baselineScore(r, target),
              source: ScoreSource.localFallback,
            ))
        .toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topN).toList();
  }

  /// Generates a brand-new Sri Lankan recipe from scratch via the generative AI engine.
  Future<GeneratedRecipeResult> generateRecipe({
    required String prompt,
    required UserProfile profile,
    String? mealType,
  }) async {
    final url = Uri.parse('$_baseUrl/generate-recipe');
    final payload = {
      'prompt': prompt,
      'dietary_pref': profile.dietaryPref,
      'spice_pref': profile.spicePref,
      'meal_type': mealType ?? 'Dinner',
      'allergies': profile.allergies,
      'avoid_ingredients': profile.avoidList,
    };

    final res = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final recipeJson = data['recipe'] as Map<String, dynamic>;
      final recipe = Recipe.fromJson(recipeJson);
      final novelty = (recipeJson['novelty'] as Map<String, dynamic>?) ?? {};
      return GeneratedRecipeResult(
        recipe: recipe,
        modelName: data['model'] as String? ?? 'Sri Lankan Recipe Generative Engine',
        novelty: novelty,
        promptOrigin: prompt,
      );
    }
    throw HttpException('Server returned ${res.statusCode}: ${res.body}');
  }

  void dispose() => _client.close();
}

@immutable
class GeneratedRecipeResult {
  final Recipe recipe;
  final String modelName;
  final Map<String, dynamic> novelty;
  final String promptOrigin;

  const GeneratedRecipeResult({
    required this.recipe,
    required this.modelName,
    required this.novelty,
    required this.promptOrigin,
  });
}

@immutable
class RecommendationResult {
  final List<ScoredRecipe> items;
  final ScoreSource source;

  const RecommendationResult({required this.items, required this.source});

  bool get isEmpty => items.isEmpty;
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
