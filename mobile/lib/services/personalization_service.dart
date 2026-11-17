import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/recipe.dart';
import '../models/tracking.dart';

/// Learns a lightweight per-user preference profile from the interactions
/// the app already records - favourites and logged meals - and re-ranks the
/// content-based recommendations the trained model returns.
///
/// This is deliberately a SECOND STAGE on top of the trained MLP, not a
/// replacement for it:
///   Stage 1 (backend `train.py` / `serve.py`): scores every eligible recipe
///   against the user's STATED profile (age, weight, activity, goals). This
///   is what makes the very first recommendation - before any interaction
///   history exists - possible at all (the cold-start case).
///   Stage 2 (this class, on-device): nudges that ranking using what the
///   user has actually DONE - favourited, logged, ignored - so the list
///   keeps improving the more the app is used, instead of only ever
///   reflecting the profile form filled in once at onboarding. This is the
///   piece that was previously entirely missing: the two pieces of state
///   the app already stored (favourites, meal history) never fed back into
///   what got recommended.
///
/// The hard dietary/safety filter always happens further upstream (server
/// or local fallback, see `recipe_service.dart`) and is never touched here -
/// personalisation can only re-order already-safe options, never introduce
/// an unsafe one.
class PersonalizationService {
  /// How many days until a logged meal's influence halves. Recent eating
  /// habits should matter more than what was logged a month ago.
  static const double _halfLifeDays = 14.0;

  /// Interactions needed before personalisation reaches full strength.
  /// Below this, boosts are scaled down so a single stray favourite can't
  /// dominate the list; a new user effectively sees the unmodified model
  /// ranking, exactly as before.
  static const int _confidenceFloor = 8;

  /// Maximum points the re-rank can add to a recipe's score (the trained
  /// model's `predicted_score` / the fallback's `baselineScore` both sit
  /// roughly in the 0-100 range, so this is a meaningful but bounded nudge,
  /// never enough to override a strong model score with a weak one).
  static const double _maxBoost = 18.0;

  /// Builds the affinity profile from the user's stored interactions.
  @visibleForTesting
  UserAffinityProfile buildProfile({
    required List<MealLog> meals,
    required Set<String> favouriteIds,
    required List<Recipe> allRecipes,
  }) {
    final byId = {for (final r in allRecipes) r.id: r};
    final now = DateTime.now();

    final foodGroup = <String, double>{};
    final category = <String, double>{};
    final spice = <String, double>{};
    double weightedProteinShare = 0;
    double totalWeight = 0;

    void addSignal(Recipe r, double weight) {
      foodGroup.update(r.foodGroup, (v) => v + weight, ifAbsent: () => weight);
      category.update(r.category, (v) => v + weight, ifAbsent: () => weight);
      spice.update(r.spiceLevel, (v) => v + weight, ifAbsent: () => weight);
      final proteinShare = r.calories > 0
          ? (r.protein * 4 / r.calories).clamp(0.0, 1.0)
          : 0.0;
      weightedProteinShare += proteinShare * weight;
      totalWeight += weight;
    }

    // Favourites carry a flat, strong weight - an explicit "I like this" is
    // a stronger signal than an incidentally-logged meal, and favourites
    // don't carry a timestamp to decay by age.
    for (final id in favouriteIds) {
      final recipe = byId[id];
      if (recipe != null) addSignal(recipe, 3.0);
    }

    // Logged meals carry an implicit, recency-weighted signal. Logging the
    // same dish repeatedly compounds its weight naturally, which is what
    // should happen - a recipe eaten five times says more than one eaten
    // once.
    for (final meal in meals) {
      final recipe = byId[meal.recipeId];
      if (recipe == null) continue;
      final ageDays = now.difference(meal.loggedAt).inHours / 24.0;
      final decay = math.pow(0.5, ageDays / _halfLifeDays).toDouble();
      addSignal(recipe, 1.0 * decay);
    }

    final sampleSize = favouriteIds.length + meals.length;
    if (totalWeight == 0 || allRecipes.isEmpty) {
      return UserAffinityProfile.empty(sampleSize: sampleSize);
    }

    // Catalogue-wide average protein share, so the profile stores a
    // relative preference ("this user favours recipes N points more
    // protein-dense than the average recipe") rather than an absolute
    // number that means nothing without context.
    final catalogueAvgProteinShare = allRecipes
            .map((r) => r.calories > 0
                ? (r.protein * 4 / r.calories).clamp(0.0, 1.0)
                : 0.0)
            .fold(0.0, (a, b) => a + b) /
        allRecipes.length;

    final preferredProteinShare = weightedProteinShare / totalWeight;

    return UserAffinityProfile(
      foodGroupWeights: _normalize(foodGroup),
      categoryWeights: _normalize(category),
      spiceWeights: _normalize(spice),
      preferredProteinShare: preferredProteinShare,
      proteinAffinity:
          (preferredProteinShare - catalogueAvgProteinShare).clamp(-1.0, 1.0),
      sampleSize: sampleSize,
    );
  }

  static Map<String, double> _normalize(Map<String, double> raw) {
    if (raw.isEmpty) return const {};
    final maxV = raw.values.reduce(math.max);
    if (maxV <= 0) return const {};
    return raw.map((k, v) => MapEntry(k, v / maxV));
  }

  /// Re-ranks [base] (the model/fallback output, already dietary-filtered
  /// and sorted) using the interaction history, and returns the reordered
  /// list plus a short, honest explanation of what drove it.
  PersonalizedRecommendations personalize(
    List<ScoredRecipe> base, {
    required List<MealLog> meals,
    required Set<String> favouriteIds,
    required List<Recipe> allRecipes,
  }) {
    final profile = buildProfile(
      meals: meals,
      favouriteIds: favouriteIds,
      allRecipes: allRecipes,
    );

    if (base.isEmpty || !profile.hasSignal) {
      return PersonalizedRecommendations(items: base, profile: profile);
    }

    // Ramps from 0 to 1 as interactions accumulate, so a brand-new user's
    // list is (correctly) identical to the unmodified model output.
    final confidence =
        (profile.sampleSize / _confidenceFloor).clamp(0.0, 1.0);

    final boosted = base.map((sr) {
      final r = sr.recipe;
      final proteinShare =
          r.calories > 0 ? (r.protein * 4 / r.calories).clamp(0.0, 1.0) : 0.0;
      // How close this recipe's protein density is to what the user's own
      // history shows they actually gravitate towards.
      final proteinFit = 1.0 -
          (proteinShare - profile.preferredProteinShare).abs().clamp(0.0, 1.0);

      final rawBoost = (profile.foodGroupWeights[r.foodGroup] ?? 0) * 0.4 +
          (profile.categoryWeights[r.category] ?? 0) * 0.35 +
          (profile.spiceWeights[r.spiceLevel] ?? 0) * 0.15 +
          proteinFit * 0.10;

      final appliedBoost = rawBoost * _maxBoost * confidence;
      return ScoredRecipe(
        recipe: r,
        score: sr.score + appliedBoost,
        source: sr.source,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return PersonalizedRecommendations(
      items: boosted,
      profile: profile,
      insight: _describe(profile, confidence),
    );
  }

  static String? _describe(UserAffinityProfile profile, double confidence) {
    if (!profile.hasSignal) return null;
    if (confidence < 0.25) {
      return 'Keep favouriting and logging meals - your recommendations '
          'will get more personal as we learn your taste.';
    }
    final topGroup = _topKey(profile.foodGroupWeights);
    final topCategory = _topKey(profile.categoryWeights);
    final proteinNote = profile.proteinAffinity > 0.06
        ? ', with a lean towards higher-protein dishes'
        : profile.proteinAffinity < -0.06
            ? ', favouring lighter, lower-protein dishes'
            : '';
    if (topGroup == null && topCategory == null) return null;
    final what = [?topCategory, ?topGroup].join(' and ');
    return 'Personalised from your favourites and meal log: you tend to go '
        'for $what$proteinNote, so similar recipes are ranked higher.';
  }

  static String? _topKey(Map<String, double> weights) {
    if (weights.isEmpty) return null;
    final entry =
        weights.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return entry.value >= 0.6 ? entry.key : null;
  }
}

/// A learned, per-user preference summary. Nothing here is sent to the
/// server - it is derived and consumed entirely on-device, from data the
/// app already stores locally.
@immutable
class UserAffinityProfile {
  final Map<String, double> foodGroupWeights;
  final Map<String, double> categoryWeights;
  final Map<String, double> spiceWeights;

  /// Weighted-average protein share (kcal from protein / total kcal) across
  /// the user's own favourited/logged recipes - what they actually prefer.
  final double preferredProteinShare;

  /// [preferredProteinShare] minus the catalogue-wide average, so it reads
  /// as a relative preference. Positive = prefers more protein-dense than
  /// the average recipe in the dataset.
  final double proteinAffinity;

  final int sampleSize;

  const UserAffinityProfile({
    required this.foodGroupWeights,
    required this.categoryWeights,
    required this.spiceWeights,
    required this.preferredProteinShare,
    required this.proteinAffinity,
    required this.sampleSize,
  });

  factory UserAffinityProfile.empty({int sampleSize = 0}) =>
      UserAffinityProfile(
        foodGroupWeights: const {},
        categoryWeights: const {},
        spiceWeights: const {},
        preferredProteinShare: 0,
        proteinAffinity: 0,
        sampleSize: sampleSize,
      );

  bool get hasSignal =>
      foodGroupWeights.isNotEmpty ||
      categoryWeights.isNotEmpty ||
      spiceWeights.isNotEmpty;
}

@immutable
class PersonalizedRecommendations {
  final List<ScoredRecipe> items;
  final UserAffinityProfile profile;

  /// Human-readable, honest explanation of what drove the re-ranking - or
  /// null when there isn't enough history to say anything meaningful yet.
  final String? insight;

  const PersonalizedRecommendations({
    required this.items,
    required this.profile,
    this.insight,
  });
}
