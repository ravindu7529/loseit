import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// The recipe card used on the Recipes tab and in search results.
class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    this.score,
    this.source,
    this.isFavourite = false,
    this.onTap,
    this.onFavourite,
    this.rationale,
  });

  final Recipe recipe;
  final double? score;
  final ScoreSource? source;
  final bool isFavourite;
  final VoidCallback? onTap;
  final VoidCallback? onFavourite;

  /// One-line explanation of why this dish was recommended.
  final String? rationale;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  RecipeThumbnail(recipe: recipe, height: 150),
                  if (source != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Pill(
                        source!.label,
                        icon: source == ScoreSource.trainedModel
                            ? Icons.auto_awesome
                            : Icons.cloud_off_rounded,
                        background: source == ScoreSource.trainedModel
                            ? AppColors.primary
                            : AppColors.accentDeep,
                        foreground: Colors.white,
                        dense: true,
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 19,
                        icon: Icon(
                          isFavourite
                              ? Icons.favorite
                              : Icons.favorite_border_rounded,
                          color: isFavourite
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                        tooltip: isFavourite
                            ? 'Remove from favourites'
                            : 'Save to favourites',
                        onPressed: onFavourite,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Pill(
                      '${recipe.totalTimeMin} min',
                      icon: Icons.schedule_rounded,
                      background: Colors.white.withValues(alpha: 0.92),
                      dense: true,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Pill('${recipe.calories} kcal'),
                        Pill(
                          '${recipe.protein.toStringAsFixed(0)}g Protein',
                          background: const Color(0xFFFBE4D8),
                          foreground: AppColors.accentDeep,
                        ),
                        Pill(
                          '${recipe.carbs.toStringAsFixed(0)}g Carbs',
                          background: const Color(0xFFEDEDEB),
                          foreground: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    if (rationale != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              rationale!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontStyle: FontStyle.italic,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Builds the one-line "why this dish" explanation shown on cards.
/// Derived from real numbers so it never overstates what the model did.
String buildRationale(ScoredRecipe scored, double perMealTarget) {
  final r = scored.recipe;
  final delta = (r.calories - perMealTarget).abs();

  if (r.protein >= 25) {
    return 'High protein (${r.protein.toStringAsFixed(0)}g) to keep you full '
        'through a calorie deficit.';
  }
  if (delta <= 60) {
    return 'Lands within ${delta.round()} kcal of your '
        '${perMealTarget.round()} kcal meal budget.';
  }
  if (r.fiber >= 5) {
    return 'High fibre (${r.fiber.toStringAsFixed(1)}g) for steady energy and '
        'fewer cravings.';
  }
  if (r.calories <= perMealTarget * 0.6) {
    return 'Light at ${r.calories} kcal - leaves room for a fuller main meal.';
  }
  return 'Matched to your ${r.spiceLevel.toLowerCase()} spice preference and '
      'daily calorie plan.';
}
