import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/recipe.dart';
import '../models/user_profile.dart';

/// The AI Assistant behind the chat tab.
///
/// This is a SEPARATE feature from the recommendation engine. The trained
/// neural network ranks recipes; this answers open-ended nutrition
/// questions. Two answer paths:
///
///  1. **Grounded local engine** (always available, no network, no key).
///     Classifies the question, retrieves matching recipes from the
///     bundled 300-recipe dataset, and composes an answer from the
///     user's own calculated targets. Every number it states comes from
///     the dataset or the Mifflin-St Jeor maths - it cannot hallucinate
///     a calorie count, because it only ever quotes stored values.
///
///  2. **Claude (Anthropic Messages API)**, used only when an API key is
///     supplied. The key is never hardcoded - it comes from either a
///     `--dart-define=ANTHROPIC_API_KEY=...` compile-time variable or a
///     key the user pastes into Settings. Retrieved recipes are passed
///     as context so the LLM answers from the same dataset.
///
/// Path 1 is the default so the app is fully functional offline and
/// demonstrable without any paid API access.
class AssistantService {
  AssistantService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Compile-time key. Supply with:
  ///   flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...
  /// Never commit a real key - this reads it from the build environment
  /// so it never appears in source control.
  static const String _compileTimeKey =
      String.fromEnvironment('ANTHROPIC_API_KEY');

  /// Runtime key, set from the Settings screen. Takes priority over the
  /// compile-time one so a demo can enable the LLM without rebuilding.
  String? _runtimeKey;

  set apiKey(String? value) =>
      _runtimeKey = (value == null || value.trim().isEmpty) ? null : value.trim();

  String? get _activeKey {
    if (_runtimeKey != null) return _runtimeKey;
    if (_compileTimeKey.isNotEmpty) return _compileTimeKey;
    return null;
  }

  bool get hasApiKey => _activeKey != null;

  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _model = 'claude-3-5-sonnet-20241022';
  static const String _apiVersion = '2023-06-01';

  static const String systemPrompt =
      'You are a helpful nutrition assistant specializing in Sri Lankan '
      'cuisine and healthy weight loss. Keep answers concise and '
      'practical. Only quote calorie and macro numbers that appear in the '
      'recipe context you are given - never invent them. If the context '
      "does not cover the question, say so rather than guessing.";

  /// Answers [question] for [profile]. Falls back to the local engine if
  /// the API call fails for any reason, so the chat never dead-ends.
  Future<AssistantReply> ask({
    required String question,
    required UserProfile profile,
    required List<Recipe> recipes,
    List<String> history = const [],
  }) async {
    final matched = retrieve(question, profile, recipes);

    if (hasApiKey) {
      try {
        final text = await _askClaude(
          question: question,
          profile: profile,
          context: matched,
          history: history,
        );
        return AssistantReply(
          text: text,
          citedRecipeIds: matched.map((r) => r.id).toList(),
          source: AssistantSource.llm,
        );
      } catch (e) {
        debugPrint('[LoseIt] Claude call failed ($e) - using local assistant.');
      }
    }

    return answerLocally(question, profile, recipes);
  }

  // ---------------------------------------------------------------
  // Path 2: Anthropic Messages API over raw HTTP.
  // Dart has no official Anthropic SDK, so this is the documented raw
  // HTTP shape: POST /v1/messages with x-api-key + anthropic-version.
  // ---------------------------------------------------------------

  Future<String> _askClaude({
    required String question,
    required UserProfile profile,
    required List<Recipe> context,
    required List<String> history,
  }) async {
    final contextBlock = context.isEmpty
        ? 'No specific recipes matched this question.'
        : context.map((r) {
            return '- ${r.name} (${r.dietaryTag}, ${r.mealType}, '
                '${r.spiceLevel} spice): ${r.calories} kcal, '
                '${r.protein}g protein, ${r.carbs}g carbs, ${r.fat}g fat, '
                '${r.fiber}g fibre. Ingredients: ${r.keyIngredients}.';
          }).join('\n');

    final userBlock = '''
User profile: ${profile.age}y ${profile.gender}, ${profile.heightCm.round()}cm,
${profile.weightKg.toStringAsFixed(1)}kg (BMI ${profile.bmi.toStringAsFixed(1)},
${profile.bmiCategory}), ${profile.activityLevel} activity, ${profile.dietaryPref},
prefers ${profile.spicePref} spice.
Daily calorie target: ${profile.dailyCalorieTarget.round()} kcal
(about ${profile.perMealTarget.round()} kcal per main meal).

Relevant recipes from the Spice & Scale Sri Lankan dataset:
$contextBlock

Question: $question''';

    final res = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': _activeKey!,
            'anthropic-version': _apiVersion,
          },
          body: jsonEncode({
            'model': _model,
            'max_tokens': 1024,
            'system': systemPrompt,
            'messages': [
              for (var i = 0; i < history.length; i++)
                {
                  'role': i.isEven ? 'user' : 'assistant',
                  'content': history[i],
                },
              {'role': 'user', 'content': userBlock},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('Anthropic API returned ${res.statusCode}: ${res.body}');
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

    // Guard the refusal stop reason before reading content - a refused
    // request returns 200 with an empty content array.
    if (body['stop_reason'] == 'refusal') {
      throw Exception('request was declined by the safety classifier');
    }

    // content is a list of blocks; concatenate the text ones.
    final blocks = (body['content'] as List?) ?? const [];
    final text = blocks
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join()
        .trim();

    if (text.isEmpty) throw Exception('empty response from Anthropic API');
    return text;
  }

  // ---------------------------------------------------------------
  // Path 1: local, dataset-grounded engine.
  // ---------------------------------------------------------------

  static const Set<String> _stopWords = {
    'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'to', 'of', 'in',
    'on', 'for', 'and', 'or', 'i', 'me', 'my', 'it', 'that', 'this', 'with',
    'how', 'what', 'much', 'many', 'can', 'do', 'does', 'should', 'would',
    'have', 'has', 'about', 'good', 'best', 'some', 'any', 'give', 'show',
    'tell', 'you', 'your', 'please', 'recipe', 'recipes', 'food',
    'eat', 'eating', 'get', 'want', 'need', 'there', 'from',
  };

  static List<String> _tokens(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 2 && !_stopWords.contains(t))
      .toList();

  /// Ranks recipes by how well their name/ingredients match [question],
  /// after applying the user's hard dietary filter.
  @visibleForTesting
  List<Recipe> retrieve(
    String question,
    UserProfile profile,
    List<Recipe> recipes, {
    int limit = 5,
  }) {
    final qTokens = _tokens(question);
    if (qTokens.isEmpty) return const [];

    final eligible =
        recipes.where((r) => profile.allowsRecipe(r)).toList();

    final scored = <MapEntry<Recipe, double>>[];
    for (final r in eligible) {
      final haystack =
          '${r.name} ${r.category} ${r.mainIngredient} ${r.keyIngredients} '
                  '${r.foodGroup}'
              .toLowerCase();
      var score = 0.0;
      for (final t in qTokens) {
        if (r.name.toLowerCase().contains(t)) {
          score += 3; // a name hit is the strongest signal
        } else if (haystack.contains(t)) {
          score += 1;
        }
      }
      if (score > 0) scored.add(MapEntry(r, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  /// The offline answer engine. Public so it can be unit-tested without
  /// touching the network.
  @visibleForTesting
  AssistantReply answerLocally(
    String question,
    UserProfile profile,
    List<Recipe> recipes,
  ) {
    final q = question.toLowerCase().trim();
    final eligible =
        recipes.where((r) => profile.allowsRecipe(r)).toList();

    AssistantReply reply(String text, [List<Recipe> cited = const []]) =>
        AssistantReply(
          text: text,
          citedRecipeIds: cited.map((r) => r.id).toList(),
          source: AssistantSource.localGrounded,
        );

    // --- Greetings ------------------------------------------------
    if (RegExp(r'^(hi|hello|hey|ayubowan|kohomada|good (morning|evening))\b')
        .hasMatch(q)) {
      return reply(
        'Ayubowan! I can help with calories, macros and Sri Lankan recipe '
        'ideas that fit your plan. Your daily target is '
        '${profile.dailyCalorieTarget.round()} kcal. Try asking me things '
        'like "how many calories in pol sambol", "high protein dinner", or '
        '"what should I eat for breakfast".',
      );
    }

    // --- Daily target / BMI --------------------------------------
    if (RegExp(r'\b(daily|target|budget|tdee|bmr|deficit)\b').hasMatch(q) ||
        RegExp(r'how many calories (should|can|do) i').hasMatch(q)) {
      return reply(
        'Your BMR is about ${profile.bmr.round()} kcal and your maintenance '
        'level is roughly ${profile.maintenanceCalories.round()} kcal/day. '
        'With a 500 kcal deficit your daily target is '
        '${profile.dailyCalorieTarget.round()} kcal - about '
        '${profile.perMealTarget.round()} kcal for a main meal. At that pace '
        'you would reach ${profile.targetWeightKg.toStringAsFixed(1)} kg in '
        'roughly ${profile.estimatedWeeksToGoal} weeks.',
      );
    }

    if (RegExp(r'\bbmi\b|\b(over|under)weight\b').hasMatch(q)) {
      return reply(
        'Your BMI is ${profile.bmi.toStringAsFixed(1)}, which falls in the '
        '${profile.bmiCategory.toLowerCase()} range. A healthy BMI is between '
        '18.5 and 24.9. Losing to ${profile.targetWeightKg.toStringAsFixed(1)} kg '
        'would put you at '
        '${(profile.targetWeightKg / math.pow(profile.heightCm / 100, 2)).toStringAsFixed(1)}.',
      );
    }

    if (RegExp(r'\b(protein|carb|carbs|fat|macro|macros)\b').hasMatch(q) &&
        RegExp(r'\b(target|need|daily|how much)\b').hasMatch(q)) {
      return reply(
        'On a ${profile.dailyCalorieTarget.round()} kcal day, aim for roughly '
        '${profile.proteinTargetG.round()}g protein, '
        '${profile.carbsTargetG.round()}g carbs and '
        '${profile.fatTargetG.round()}g fat. Protein matters most in a '
        'deficit - it keeps you full and protects muscle.',
      );
    }

    // --- Nutrition lookup for a named dish ------------------------
    final matched = retrieve(question, profile, recipes);
    final asksNutrition = RegExp(
      r'\b(calorie|calories|kcal|nutrition|protein|carbs|fat|fibre|fiber|healthy|good for)\b',
    ).hasMatch(q);

    if (matched.isNotEmpty && asksNutrition) {
      final r = matched.first;
      final vsTarget = r.calories - profile.perMealTarget;
      final verdict = vsTarget.abs() < 80
          ? 'That sits right on your ${profile.perMealTarget.round()} kcal '
              'per-meal budget.'
          : vsTarget > 0
              ? 'That is about ${vsTarget.round()} kcal over your '
                  '${profile.perMealTarget.round()} kcal per-meal budget, so '
                  'keep the portion modest or pair it with something light.'
              : 'That leaves about ${vsTarget.abs().round()} kcal spare in your '
                  '${profile.perMealTarget.round()} kcal per-meal budget.';
      return reply(
        '${r.name} has ${r.calories} kcal per serving, with '
        '${r.protein}g protein, ${r.carbs}g carbs, ${r.fat}g fat and '
        '${r.fiber}g fibre. $verdict',
        [r],
      );
    }

    // --- Filtered suggestions ------------------------------------
    final mealType = _detectMealType(q);
    var pool = List<Recipe>.from(eligible);
    final filters = <String>[];

    if (mealType != null) {
      final byMeal = pool.where((r) => r.mealType == mealType).toList();
      if (byMeal.isNotEmpty) {
        pool = byMeal;
        filters.add(mealType.toLowerCase());
      }
    }

    int Function(Recipe, Recipe)? sorter;
    if (RegExp(r'high[- ]?protein|more protein|protein rich').hasMatch(q)) {
      sorter = (a, b) => b.protein.compareTo(a.protein);
      filters.add('high-protein');
    } else if (RegExp(r'low[- ]?(calorie|cal)|light|fewest calories')
        .hasMatch(q)) {
      sorter = (a, b) => a.calories.compareTo(b.calories);
      filters.add('low-calorie');
    } else if (RegExp(r'low[- ]?carb').hasMatch(q)) {
      sorter = (a, b) => a.carbs.compareTo(b.carbs);
      filters.add('low-carb');
    } else if (RegExp(r'low[- ]?fat').hasMatch(q)) {
      sorter = (a, b) => a.fat.compareTo(b.fat);
      filters.add('low-fat');
    } else if (RegExp(r'fibre|fiber').hasMatch(q)) {
      sorter = (a, b) => b.fiber.compareTo(a.fiber);
      filters.add('high-fibre');
    } else if (RegExp(r'quick|fast|easy|hurry|15 min|20 min').hasMatch(q)) {
      sorter = (a, b) => a.totalTimeMin.compareTo(b.totalTimeMin);
      filters.add('quick');
    } else if (RegExp(r'vegan').hasMatch(q)) {
      pool = pool.where((r) => r.dietaryTag == 'Vegan').toList();
      filters.add('vegan');
    } else if (RegExp(r'vegetarian|veg\b').hasMatch(q)) {
      pool = pool
          .where((r) => r.dietaryTag == 'Vegan' || r.dietaryTag == 'Vegetarian')
          .toList();
      filters.add('vegetarian');
    }

    final wantsSuggestions = sorter != null ||
        filters.isNotEmpty ||
        RegExp(r'suggest|recommend|idea|ideas|what should|options|alternative|instead of')
            .hasMatch(q);

    if (wantsSuggestions && pool.isNotEmpty) {
      // Default ordering: closest to the user's per-meal calorie budget.
      sorter ??= (a, b) => (a.calories - profile.perMealTarget)
          .abs()
          .compareTo((b.calories - profile.perMealTarget).abs());
      pool.sort(sorter);
      final picks = pool.take(3).toList();
      final label = filters.isEmpty ? '' : ' ${filters.join(', ')}';
      final lines = picks
          .map((r) =>
              '- ${r.name}: ${r.calories} kcal, ${r.protein}g protein, '
              '${r.totalTimeMin} min')
          .join('\n');
      return reply(
        'Here are three$label options that fit your '
        '${profile.dietaryPref.toLowerCase()} preference and '
        '${profile.perMealTarget.round()} kcal per-meal budget:\n\n$lines',
        picks,
      );
    }

    // --- Ingredients / how to cook -------------------------------
    if (matched.isNotEmpty &&
        RegExp(r'ingredient|make|cook|prepare|how do i').hasMatch(q)) {
      final r = matched.first;
      return reply(
        '${r.name} takes about ${r.prepTimeMin} min prep and '
        '${r.cookTimeMin} min cooking, serving ${r.servings}. Key '
        'ingredients: ${r.keyIngredients}. Open the recipe for the full '
        'breakdown.',
        [r],
      );
    }

    // --- Matched something but no clear intent -------------------
    if (matched.isNotEmpty) {
      final r = matched.first;
      return reply(
        'I found ${r.name} in the dataset - ${r.calories} kcal, '
        '${r.protein}g protein, ${r.spiceLevel.toLowerCase()} spice, '
        '${r.totalTimeMin} min total. Ask me about its calories, its '
        'ingredients, or for similar options.',
        [r],
      );
    }

    // --- Fallback -------------------------------------------------
    return reply(
      "I could not match that to anything in the 300-recipe Sri Lankan "
      'dataset. Try naming a dish (for example "pol sambol" or "ambul '
      'thiyal"), or ask for a category such as "high protein dinner", '
      '"low calorie breakfast", or "quick vegan lunch".',
    );
  }

  static String? _detectMealType(String q) {
    if (q.contains('breakfast')) return 'Breakfast';
    if (q.contains('lunch')) return 'Lunch';
    if (q.contains('dinner') || q.contains('supper')) return 'Dinner';
    if (q.contains('snack') || q.contains('short eat')) return 'Snack';
    return null;
  }

  /// Suggestion chips shown under the transcript.
  static const List<String> starterPrompts = [
    'Calorie count of Kottu?',
    'High protein dinner ideas',
    'Alternative to white rice',
    'How many calories should I eat?',
    'Quick vegan lunch',
  ];

  void dispose() => _client.close();
}

enum AssistantSource { localGrounded, llm }

@immutable
class AssistantReply {
  final String text;
  final List<String> citedRecipeIds;
  final AssistantSource source;

  const AssistantReply({
    required this.text,
    this.citedRecipeIds = const [],
    required this.source,
  });
}
