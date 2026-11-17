import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Bottom sheet for logging a meal from anywhere in the app (the FAB).
Future<void> showLogMealSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _LogMealSheet(),
  );
}

class _LogMealSheet extends StatefulWidget {
  const _LogMealSheet();

  @override
  State<_LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends State<_LogMealSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;

    // Hard dietary & allergy filter applies here too
    var pool =
        state.allRecipes.where((r) => profile.allowsRecipe(r)).toList();

    if (_query.trim().isEmpty) {
      // Default view: recommendations for the current slot, so the most
      // likely choices are one tap away.
      final slot = state.currentMealSlot;
      final ranked = state.recommendations
          .map((s) => s.recipe)
          .where((r) => r.mealType == slot)
          .toList();
      pool = ranked.isNotEmpty ? ranked : pool;
    } else {
      final q = _query.toLowerCase().trim();
      pool = pool
          .where((r) =>
              r.name.toLowerCase().contains(q) ||
              r.mainIngredient.toLowerCase().contains(q) ||
              r.keyIngredients.toLowerCase().contains(q))
          .toList();
    }

    final results = pool.take(30).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Log a meal',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      Pill(
                        '${state.caloriesRemainingToday} kcal left',
                        background: state.caloriesRemainingToday < 0
                            ? const Color(0xFFFBE4D8)
                            : AppColors.mintSoft,
                        foreground: state.caloriesRemainingToday < 0
                            ? AppColors.accentDeep
                            : AppColors.primaryDeep,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _controller,
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search the 300 Sri Lankan recipes...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                  if (_query.trim().isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Suggested for ${state.currentMealSlot.toLowerCase()}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matching dishes',
                      message: 'Try a different name or ingredient.',
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _MealRow(recipe: results[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () async {
        await state.logMeal(recipe);
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${recipe.name} logged')),
        );
      },
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: RecipeThumbnail(
              recipe: recipe,
              height: 52,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${recipe.calories} kcal  •  '
                  '${recipe.protein.toStringAsFixed(0)}g protein  •  '
                  '${recipe.mealType}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(Icons.add_circle_outline_rounded,
              color: AppColors.primary),
        ],
      ),
    );
  }
}
