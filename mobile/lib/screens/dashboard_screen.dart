import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../models/tracking.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_recipe_generator_sheet.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'log_meal_sheet.dart';
import 'progress_screen.dart';
import 'recipe_details_screen.dart';

/// Today at a glance: calories remaining, macros, weight trend and the
/// top recommendation for the current meal slot.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onSeeAllRecipes});

  final VoidCallback? onSeeAllRecipes;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;
    final remaining = state.caloriesRemainingToday;
    final overBudget = remaining < 0;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('log_meal_fab'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: () {
          HapticFeedback.mediumImpact();
          showLogMealSheet(context);
        },
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Log Meal',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => state.refreshRecommendations(),
        child: CustomScrollView(
          slivers: [
            // ---- Greeting Header --------------------------------------
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.mint, AppColors.mintSoft],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.primary, width: 1.8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials(profile.name),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ayubowan, ${profile.name.split(' ').first}!',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDeep,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              "Let's keep your vitality nourished today.",
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded,
                            color: AppColors.primaryDeep),
                        tooltip: 'Notifications',
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No new notifications')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ---- Body content ----------------------------------------
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // --- Calories -------------------------------------------
                  _CalorieCard(
                    remaining: remaining,
                    overBudget: overBudget,
                    consumed: state.caloriesConsumedToday,
                    target: profile.dailyCalorieTarget.round(),
                    progress: state.calorieProgress,
                  ),
                  const SizedBox(height: 14),

                  // --- Macros (single card) --------------------------------
                  _MacroRowCard(
                    carbsValue: state.carbsToday,
                    carbsTarget: profile.carbsTargetG,
                    proteinValue: state.proteinToday,
                    proteinTarget: profile.proteinTargetG,
                    fatValue: state.fatToday,
                    fatTarget: profile.fatTargetG,
                  ),
                  const SizedBox(height: 14),

                  // --- Today's Logged Meals --------------------------------
                  _DashboardTodaysMealsSection(state: state),
                  const SizedBox(height: 14),

                  // --- Weight ---------------------------------------------
                  AppCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ProgressScreen()),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Weight Progress',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 4),
                                  Text(
                                    _weeklyLabel(state.weeklyWeightChange),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: state.latestWeight
                                            .toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontFamily: AppTheme.fontFamily,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primaryDeep,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' kg',
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontFamily,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.trending_down_rounded,
                                        size: 14, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'See full progress',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        WeightBarChart(
                          values: state.weightSeries
                              .map((w) => w.weightKg)
                              .toList()
                              .reversed
                              .take(7)
                              .toList()
                              .reversed
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Recommendation -------------------------------------
                  SectionHeader(
                    title: 'Recommended ${state.currentMealSlot}',
                    icon: Icons.restaurant_menu_rounded,
                    trailing: 'See all',
                    onTrailingTap: onSeeAllRecipes,
                  ),
                  if (state.personalizationInsight != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      state.personalizationInsight!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _RecommendationSlot(state: state),
                  const SizedBox(height: 16),
                  const _AiRecipeGeneratorDashboardCard(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'LI';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static String _weeklyLabel(double change) {
    if (change == 0) return 'No change logged this week';
    final verb = change < 0 ? 'down' : 'up';
    return '${change.abs().toStringAsFixed(1)} kg $verb from last week';
  }
}

// ---------------------------------------------------------------------------
// AI Recipe Generator Dashboard Action Card
// ---------------------------------------------------------------------------

class _AiRecipeGeneratorDashboardCard extends StatelessWidget {
  const _AiRecipeGeneratorDashboardCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () {
        HapticFeedback.mediumImpact();
        AiRecipeGeneratorSheet.show(context);
      },
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.mint,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AI Recipe Generator',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.mintSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'AI',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDeep,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Have pantry ingredients? Invent a custom Sri Lankan recipe.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMuted,
            size: 22,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calorie hero card
// ---------------------------------------------------------------------------

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({
    required this.remaining,
    required this.overBudget,
    required this.consumed,
    required this.target,
    required this.progress,
  });

  final int remaining;
  final bool overBudget;
  final int consumed;
  final int target;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final heroColor =
        overBudget ? AppColors.accentDeep : AppColors.primaryDeep;
    final ringColor = overBudget ? AppColors.accent : AppColors.primary;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overBudget ? 'OVER BUDGET BY' : 'CALORIES REMAINING',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge,
                        children: [
                          TextSpan(
                            text: _formatNumber(remaining.abs()),
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: heroColor,
                            ),
                          ),
                          TextSpan(
                            text: ' kcal',
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          overBudget
                              ? Icons.warning_amber_rounded
                              : Icons.bolt_rounded,
                          size: 16,
                          color: heroColor,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            overBudget
                                ? 'Over target for today'
                                : 'On track for today',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: heroColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatNumber(consumed)} of '
                      '${_formatNumber(target)} kcal eaten',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              CalorieRing(
                progress: progress,
                color: ringColor,
                size: 96,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (progress).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '$target kcal goal',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatNumber(int n) {
    final s = n.abs().toString();
    if (s.length <= 3) return s;
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// Macro row card (all three macros in one card)
// ---------------------------------------------------------------------------

class _MacroRowCard extends StatelessWidget {
  const _MacroRowCard({
    required this.carbsValue,
    required this.carbsTarget,
    required this.proteinValue,
    required this.proteinTarget,
    required this.fatValue,
    required this.fatTarget,
  });

  final double carbsValue;
  final double carbsTarget;
  final double proteinValue;
  final double proteinTarget;
  final double fatValue;
  final double fatTarget;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      child: Row(
        children: [
          _MacroCell(
            label: 'Carbs',
            value: carbsValue,
            target: carbsTarget,
            color: AppColors.carbs,
          ),
          _VerticalDivider(),
          _MacroCell(
            label: 'Protein',
            value: proteinValue,
            target: proteinTarget,
            color: AppColors.protein,
          ),
          _VerticalDivider(),
          _MacroCell(
            label: 'Fats',
            value: fatValue,
            target: fatTarget,
            color: AppColors.fat,
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }
}

class _MacroCell extends StatelessWidget {
  const _MacroCell({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = (target > 0 ? value / target : 0.0).clamp(0.0, 1.0);
    return Expanded(
      child: Column(
        children: [
          // Thin progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${value.round()}g',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            'of ${target.round()}g',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recommendation slot
// ---------------------------------------------------------------------------

class _RecommendationSlot extends StatelessWidget {
  const _RecommendationSlot({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingRecommendations && state.recommendations.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.symmetric(vertical: 44),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final featured = state.featuredRecipe;
    if (featured == null) {
      return AppCard(
        child: EmptyState(
          icon: Icons.restaurant_outlined,
          title: 'No recommendation yet',
          message: state.recommendationError ??
              'Pull down to refresh and rebuild your list.',
          action: OutlinedButton(
            onPressed: () => state.refreshRecommendations(),
            child: const Text('Try again'),
          ),
        ),
      );
    }

    final recipe = featured.recipe;
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
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RecipeDetailsScreen(recipe: recipe),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  RecipeThumbnail(recipe: recipe, height: 180),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Pill(
                      featured.source.label,
                      icon: featured.source == ScoreSource.trainedModel
                          ? Icons.auto_awesome
                          : Icons.cloud_off_rounded,
                      background: featured.source == ScoreSource.trainedModel
                          ? AppColors.primary
                          : AppColors.accentDeep,
                      foreground: Colors.white,
                      dense: true,
                    ),
                  ),
                  Positioned(
                    top: 12,
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            recipe.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final t in recipe.tags) Pill(t, dense: true),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${recipe.protein.toStringAsFixed(0)}g protein  •  '
                      '${recipe.calories} kcal',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    // Single primary CTA + icon log button
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RecipeDetailsScreen(recipe: recipe),
                                ),
                              );
                            },
                            child: const Text('View Recipe'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _LogIconButton(recipe: recipe, state: state),
                      ],
                    ),
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

class _LogIconButton extends StatefulWidget {
  const _LogIconButton({required this.recipe, required this.state});
  final Recipe recipe;
  final AppState state;

  @override
  State<_LogIconButton> createState() => _LogIconButtonState();
}

class _LogIconButtonState extends State<_LogIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _log() async {
    if (_logged) return;
    HapticFeedback.mediumImpact();
    setState(() => _logged = true);
    _anim.forward();
    await widget.state.logMeal(widget.recipe);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.recipe.name} logged ✓')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Log this meal',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _logged
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
          border: _logged
              ? Border.all(color: AppColors.primary, width: 1.4)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _log,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  _logged ? Icons.check_rounded : Icons.add_rounded,
                  key: ValueKey(_logged),
                  color: _logged ? AppColors.primary : AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today's Logged Meals Dashboard Section
// ---------------------------------------------------------------------------

class _DashboardTodaysMealsSection extends StatelessWidget {
  const _DashboardTodaysMealsSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final meals = state.todaysMeals;

    if (meals.isEmpty) {
      return AppCard(
        onTap: () {
          HapticFeedback.lightImpact();
          showLogMealSheet(context);
        },
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.mintSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No meals logged yet today',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap here to track your breakfast, lunch or dinner.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      );
    }

    final recentMeals = meals.reversed.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_menu_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  "Today's Meals (${meals.length})",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProgressScreen()),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            children: [
              for (int i = 0; i < recentMeals.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                _DashboardMealItem(meal: recentMeals[i], state: state),
              ],
              if (meals.length > 3) ...[
                const Divider(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProgressScreen()),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'View all ${meals.length} meals in history',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardMealItem extends StatelessWidget {
  const _DashboardMealItem({required this.meal, required this.state});
  final MealLog meal;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat.jm().format(meal.loggedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.mintSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              meal.mealType,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDeep,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.recipeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$timeStr  •  ${meal.protein.toStringAsFixed(0)}g protein',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '${meal.calories} kcal',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: AppColors.primaryDeep,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.textMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Remove meal',
            onPressed: () => state.removeMeal(meal.id),
          ),
        ],
      ),
    );
  }
}

