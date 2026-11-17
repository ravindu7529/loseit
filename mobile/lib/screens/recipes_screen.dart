import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_recipe_generator_sheet.dart';
import '../widgets/common.dart';
import '../widgets/recipe_card.dart';
import 'recipe_details_screen.dart';

/// Browse and search the 300-recipe dataset.
///
/// "For You" shows the ranked output of the recommender; the other
/// filters browse the full dataset (still behind the hard dietary
/// filter, which is never bypassed).
class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String _filter = 'For You';

  static const List<String> _filters = [
    'For You',
    '✨ AI Created',
    'Favourites',
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'High protein',
    'Low calorie',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<ScoredRecipe> _visible(AppState state) {
    final profile = state.profile;
    final target = profile.perMealTarget;
    final searching = _query.trim().isNotEmpty;

    List<ScoredRecipe> items;
    if (_filter == 'For You' && !searching) {
      items = List.of(state.recommendations);
    } else {
      final ranked = {
        for (final s in state.recommendations) s.recipe.id: s,
      };
      items = state.allRecipes
          .where((r) => profile.allowsRecipe(r))
          .map((r) =>
              ranked[r.id] ??
              ScoredRecipe(
                recipe: r,
                score: 0,
                source: state.scoreSource,
              ))
          .toList();
    }

    switch (_filter) {
      case '✨ AI Created':
        items = state.generatedRecipes
            .map((r) => ScoredRecipe(
                  recipe: r,
                  score: 100,
                  source: ScoreSource.trainedModel,
                ))
            .toList();
        break;
      case 'Favourites':
        items = items
            .where((s) => state.isFavourite(s.recipe.id))
            .toList();
        break;
      case 'Breakfast':
      case 'Lunch':
      case 'Dinner':
      case 'Snack':
        items = items.where((s) => s.recipe.mealType == _filter).toList();
        items.sort((a, b) => (a.recipe.calories - target)
            .abs()
            .compareTo((b.recipe.calories - target).abs()));
        break;
      case 'High protein':
        items.sort((a, b) => b.recipe.protein.compareTo(a.recipe.protein));
        break;
      case 'Low calorie':
        items.sort((a, b) => a.recipe.calories.compareTo(b.recipe.calories));
        break;
    }

    if (searching) {
      final q = _query.toLowerCase().trim();
      items = items.where((s) {
        final r = s.recipe;
        return r.name.toLowerCase().contains(q) ||
            r.category.toLowerCase().contains(q) ||
            r.mainIngredient.toLowerCase().contains(q) ||
            r.keyIngredients.toLowerCase().contains(q);
      }).toList();
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = _visible(state);
    final isSearching = _query.trim().isNotEmpty;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.refreshRecommendations(),
        child: CustomScrollView(
          slivers: [
            // ----- Clean Top Header ---------------------------------------
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  AppColors.primaryDeep,
                                  AppColors.primary,
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'Recipes',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Personalised nutrition paths tailored for you',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          AiRecipeGeneratorSheet.show(context);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.mintSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.mint),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded,
                                  size: 16, color: AppColors.primary),
                              SizedBox(width: 5),
                              Text(
                                'AI Lab',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDeep,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ----- AI Craving Lab Banner Card ---------------------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    AiRecipeGeneratorSheet.show(context);
                  },
                  borderRadius: AppRadius.card,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryLight],
                      ),
                      borderRadius: AppRadius.card,
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.mint,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'AI Recipe Generator',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontFamily,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.mint,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'GEN AI',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primaryDeep,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Got ingredients or a craving? Invent a custom Sri Lankan meal.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.88),
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ----- Search bar ------------------------------------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search healthy recipes...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                              _searchFocus.unfocus();
                            },
                          ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.card,
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadius.card,
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.card,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),

            // ----- Filter chips ----------------------------------------
            SliverToBoxAdapter(
              child: SizedBox(
                height: 50,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = _filters[i];
                    final selected = f == _filter;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = f);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.surface,
                          borderRadius: AppRadius.pill,
                          border: selected
                              ? null
                              : Border.all(
                                  color: AppColors.border, width: 1),
                          boxShadow: selected ? AppShadows.card : null,
                        ),
                        child: Text(
                          f,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: ModelSourceBanner(
                  source: state.scoreSource,
                  onRetry: () => state.refreshRecommendations(),
                ),
              ),
            ),

            // Result count
            if (items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    '${items.length} recipe${items.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),

            // ----- Recipe list / empty / loading -----------------------
            if (state.isLoadingRecommendations && items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: _filter == 'Favourites'
                      ? Icons.favorite_border_rounded
                      : Icons.search_off_rounded,
                  title: _filter == 'Favourites'
                      ? 'No favourites yet'
                      : 'Nothing matched',
                  message: _filter == 'Favourites'
                      ? 'Tap the heart on any recipe to save it here.'
                      : 'Try a different search term or filter.',
                ),
              )
            else if (isSearching)
              // Search results: single-column for better readability
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => _buildCard(
                      context, items[i], state, isForYou: false),
                ),
              )
            else
              // Browsing: 2-column grid
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                sliver: SliverGrid.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _buildGridCard(
                      context, items[i], state),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ScoredRecipe scored,
    AppState state, {
    required bool isForYou,
  }) {
    return RecipeCard(
      recipe: scored.recipe,
      source: isForYou ? scored.source : null,
      isFavourite: state.isFavourite(scored.recipe.id),
      rationale: isForYou && _filter == 'For You'
          ? buildRationale(scored, state.profile.perMealTarget)
          : null,
      onFavourite: () => state.toggleFavourite(scored.recipe.id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecipeDetailsScreen(recipe: scored.recipe),
        ),
      ),
    );
  }

  Widget _buildGridCard(
      BuildContext context, ScoredRecipe scored, AppState state) {
    final recipe = scored.recipe;
    final isFav = state.isFavourite(recipe.id);

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
                  builder: (_) => RecipeDetailsScreen(recipe: recipe)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  RecipeThumbnail(
                    recipe: recipe,
                    height: 120,
                    showFoodGroup: false,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          state.toggleFavourite(recipe.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isFav
                                ? Icons.favorite
                                : Icons.favorite_border_rounded,
                            color: isFav
                                ? AppColors.accent
                                : AppColors.textSecondary,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
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
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        Pill('${recipe.calories} kcal', dense: true),
                        Pill(
                          '${recipe.protein.toStringAsFixed(0)}g P',
                          background: const Color(0xFFFBE4D8),
                          foreground: AppColors.accentDeep,
                          dense: true,
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
    );
  }

}
