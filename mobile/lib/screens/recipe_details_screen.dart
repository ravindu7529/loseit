import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Full recipe view: hero, macros, a healthier-swap suggestion,
/// ingredients, and the log/favourite actions.
class RecipeDetailsScreen extends StatelessWidget {
  const RecipeDetailsScreen({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isFav = state.isFavourite(recipe.id);
    final perMeal = state.profile.perMealTarget;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: isFav ? 'Remove from favourites' : 'Save to favourites',
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border_rounded,
                  color: Colors.white,
                ),
                onPressed: () => state.toggleFavourite(recipe.id),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  RecipeThumbnail(
                    recipe: recipe,
                    height: 260,
                    borderRadius: BorderRadius.zero,
                    showFoodGroup: false,
                  ),
                  // Scrim so the overlaid title stays readable.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pill(
                          recipe.dietaryTag,
                          background: Colors.white.withValues(alpha: 0.92),
                          dense: true,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          recipe.name,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          children: [
                            _HeroFact(
                              icon: Icons.schedule_rounded,
                              label: '${recipe.totalTimeMin} Min',
                            ),
                            _HeroFact(
                              icon: Icons.local_fire_department_outlined,
                              label: '${recipe.calories} Cal',
                            ),
                            _HeroFact(
                              icon: Icons.people_outline_rounded,
                              label: '${recipe.servings} Servings',
                            ),
                            _HeroFact(
                              icon: Icons.whatshot_outlined,
                              label: recipe.spiceLevel,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            sliver: SliverList.list(
              children: [
                // --- Macros -------------------------------------
                Row(
                  children: [
                    Expanded(
                      child: _MacroTile(
                        label: 'PROTEIN',
                        grams: recipe.protein,
                        fraction: (recipe.protein / 40).clamp(0.0, 1.0),
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MacroTile(
                        label: 'CARBS',
                        grams: recipe.carbs,
                        fraction: (recipe.carbs / 80).clamp(0.0, 1.0),
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MacroTile(
                        label: 'FAT',
                        grams: recipe.fat,
                        fraction: (recipe.fat / 40).clamp(0.0, 1.0),
                        color: AppColors.fat,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // --- Fit against the user's budget ---------------
                AppCard(
                  color: AppColors.mintSoft,
                  child: Row(
                    children: [
                      const Icon(Icons.insights_rounded,
                          color: AppColors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _budgetFit(recipe.calories, perMeal),
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- Healthier swap ------------------------------
                _HealthierSwapCard(recipe: recipe),
                const SizedBox(height: 16),

                // --- AI Generative Novelty Banner ----------------
                if (recipe.isGenerated) ...[
                  AppCard(
                    color: AppColors.mintSoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, color: AppColors.mint, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'AI Generative Model Creation',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: AppColors.primaryDeep,
                                    ),
                                  ),
                                  Text(
                                    'Novelty Score: ${recipe.noveltyScorePercent ?? 75}% unique combination',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (recipe.inspirationRecipe != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.mint),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lightbulb_outline_rounded, size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Inspired by database recipe: ${recipe.inspirationRecipe}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryDeep),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Text('Ingredients',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      for (var i = 0;
                          i < recipe.ingredientList.length;
                          i++) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.circle,
                                  size: 6, color: AppColors.textMuted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _capitalise(recipe.ingredientList[i]),
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (i != recipe.ingredientList.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- Cooking Steps (if available) ----------------
                if (recipe.cookingSteps != null && recipe.cookingSteps!.trim().isNotEmpty) ...[
                  Text('Cooking Instructions',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  AppCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final step in recipe.cookingSteps!.split('\n').where((s) => s.trim().isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.restaurant_menu_rounded, size: 18, color: AppColors.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    step.trim(),
                                    style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                Text('About this dish',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.description,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      _DetailRow('Category', recipe.category),
                      _DetailRow('Food group', recipe.foodGroup),
                      _DetailRow('Main ingredient', recipe.mainIngredient),
                      _DetailRow('Meal type', recipe.mealType),
                      _DetailRow('Prep / cook',
                          '${recipe.prepTimeMin} / ${recipe.cookTimeMin} min'),
                      _DetailRow('Fibre',
                          '${recipe.fiber.toStringAsFixed(1)} g'),
                      _DetailRow('Recipe ID', recipe.id, isLast: true),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Log this Meal'),
                  onPressed: () async {
                    await state.logMeal(recipe);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${recipe.name} logged - '
                          '${state.caloriesRemainingToday} kcal left today',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border_rounded,
                  ),
                  label: Text(
                    isFav ? 'Saved to Favourites' : 'Save to Favourites',
                  ),
                  onPressed: () => state.toggleFavourite(recipe.id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _budgetFit(int calories, double perMeal) {
    final delta = calories - perMeal;
    if (delta.abs() <= 60) {
      return 'This lands almost exactly on your ${perMeal.round()} kcal '
          'per-meal budget.';
    }
    if (delta > 0) {
      return 'This is ${delta.round()} kcal above your ${perMeal.round()} kcal '
          'per-meal budget - consider a smaller portion or a lighter side.';
    }
    return 'This is ${delta.abs().round()} kcal below your ${perMeal.round()} '
        'kcal per-meal budget, leaving room for a side or dessert.';
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _HeroFact extends StatelessWidget {
  const _HeroFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.label,
    required this.grams,
    required this.fraction,
    required this.color,
  });

  final String label;
  final double grams;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(
            '${grams.toStringAsFixed(grams >= 10 ? 0 : 1)}g',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => LinearProgressIndicator(
                value: t,
                minHeight: 5,
                backgroundColor: const Color(0xFFECEFEE),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A deterministic, rule-derived "healthier swap" suggestion.
///
/// This is explicitly NOT model output - it is a documented lookup based
/// on the recipe's own ingredients, so the app never presents a made-up
/// nutritional claim as if a model produced it.
class _HealthierSwapCard extends StatelessWidget {
  const _HealthierSwapCard({required this.recipe});

  final Recipe recipe;

  /// ingredient trigger -> (swap, rationale)
  static const List<(String, String, String, String)> _swaps = [
    (
      'coconut milk',
      'Full-fat coconut milk',
      'Light coconut milk + cashew paste',
      'Cuts saturated fat by roughly half while keeping the creamy '
          'mouthfeel of a traditional curry.',
    ),
    (
      'white rice',
      'White rice',
      'Red or samba rice',
      'More fibre and a lower glycaemic load, so you stay full longer '
          'on the same portion.',
    ),
    (
      'rice',
      'Polished rice',
      'Red rice or kurakkan',
      'Swapping to unpolished grain adds fibre and slows the '
          'blood-sugar spike after a meal.',
    ),
    (
      'sugar',
      'Refined sugar',
      'Kithul treacle, used sparingly',
      'Traditional, lower on the glycaemic index, and you need less of '
          'it for the same sweetness.',
    ),
    (
      'oil',
      'Deep frying',
      'Air-fry or shallow-fry',
      'Removes most of the added cooking oil without changing the '
          'spice profile.',
    ),
  ];

  (String, String, String)? _findSwap() {
    final haystack =
        '${recipe.keyIngredients} ${recipe.category} ${recipe.name}'
            .toLowerCase();
    for (final (trigger, from, to, why) in _swaps) {
      if (haystack.contains(trigger)) return (from, to, why);
    }
    if (recipe.fat > 18) {
      return (
        'Generous oil / coconut',
        'Half the oil, finish with lime',
        'Fat is the densest source of calories - halving it here saves '
            'roughly 80-100 kcal per serving.',
      );
    }
    if (recipe.protein < 10) {
      return (
        'As written',
        'Add an egg, dhal or soya',
        'This dish is light on protein; adding some improves satiety '
            'and helps protect muscle in a deficit.',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final swap = _findSwap();
    if (swap == null) return const SizedBox.shrink();
    final (from, to, why) = swap;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 20, color: Color(0xFFFFB690)),
              const SizedBox(width: 9),
              Text(
                'Healthier Swap',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Traditional',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        from,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Colors.white),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Lighter choice',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        to,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFB690),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            why,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.isLast = false});

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
