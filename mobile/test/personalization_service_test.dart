import 'package:flutter_test/flutter_test.dart';
import 'package:loseit/models/recipe.dart';
import 'package:loseit/models/tracking.dart';
import 'package:loseit/services/personalization_service.dart';

Recipe _recipe({
  required String id,
  required String foodGroup,
  required String category,
  required String spiceLevel,
  required int calories,
  required double protein,
  String mealType = 'Lunch',
}) =>
    Recipe.fromJson({
      'Recipe_ID': id,
      'Recipe_Name': id,
      'Category': category,
      'Dietary_Tag': 'Non-Vegetarian',
      'Meal_Type': mealType,
      'Spice_Level': spiceLevel,
      'Calories_kcal': calories,
      'Protein_g': protein,
      'Carbs_g': 20.0,
      'Fat_g': 10.0,
      'Fiber_g': 2.0,
      'Prep_Time_Min': 10,
      'Cook_Time_Min': 10,
      'Servings': 2,
      'Key_Ingredients': 'test',
      'Food_Group': foodGroup,
    });

void main() {
  final service = PersonalizationService();

  final highProteinCurry = _recipe(
    id: 'R1',
    foodGroup: 'Rice & Curry',
    category: 'Curry',
    spiceLevel: 'Hot',
    calories: 300,
    protein: 30, // high protein share
  );
  final lightSalad = _recipe(
    id: 'R2',
    foodGroup: 'Salad',
    category: 'Salad',
    spiceLevel: 'Mild',
    calories: 150,
    protein: 5, // low protein share
  );
  final neutralSoup = _recipe(
    id: 'R3',
    foodGroup: 'Soup',
    category: 'Soup',
    spiceLevel: 'Medium',
    calories: 200,
    protein: 10,
  );
  final allRecipes = [highProteinCurry, lightSalad, neutralSoup];

  List<ScoredRecipe> baseRanking() => [
        ScoredRecipe(recipe: neutralSoup, score: 80, source: ScoreSource.trainedModel),
        ScoredRecipe(recipe: lightSalad, score: 75, source: ScoreSource.trainedModel),
        ScoredRecipe(
            recipe: highProteinCurry, score: 70, source: ScoreSource.trainedModel),
      ];

  test('returns the base ranking unchanged when there is no interaction history', () {
    final result = service.personalize(
      baseRanking(),
      meals: const [],
      favouriteIds: const {},
      allRecipes: allRecipes,
    );

    expect(result.items.map((s) => s.recipe.id).toList(),
        baseRanking().map((s) => s.recipe.id).toList());
    expect(result.insight, isNull);
  });

  test('a clear favourite pattern eventually re-ranks a lower-scored match above it',
      () {
    // Repeatedly favouriting/logging recipes from the same food group should
    // be enough signal to promote another high-protein curry above items
    // the base model scored higher, once confidence has ramped up.
    final meals = List.generate(
      10,
      (i) => MealLog(
        id: 'm$i',
        recipeId: highProteinCurry.id,
        recipeName: highProteinCurry.name,
        calories: highProteinCurry.calories,
        protein: highProteinCurry.protein,
        carbs: highProteinCurry.carbs,
        fat: highProteinCurry.fat,
        mealType: highProteinCurry.mealType,
        loggedAt: DateTime.now(),
      ),
    );

    final result = service.personalize(
      baseRanking(),
      meals: meals,
      favouriteIds: const {},
      allRecipes: allRecipes,
    );

    expect(result.items.first.recipe.id, highProteinCurry.id);
    expect(result.insight, isNotNull);
  });

  test('old meal logs count for less than recent ones (recency decay)', () {
    final oldMeal = MealLog(
      id: 'old',
      recipeId: highProteinCurry.id,
      recipeName: highProteinCurry.name,
      calories: highProteinCurry.calories,
      protein: highProteinCurry.protein,
      carbs: highProteinCurry.carbs,
      fat: highProteinCurry.fat,
      mealType: highProteinCurry.mealType,
      loggedAt: DateTime.now().subtract(const Duration(days: 90)),
    );
    final recentMeal = MealLog(
      id: 'recent',
      recipeId: highProteinCurry.id,
      recipeName: highProteinCurry.name,
      calories: highProteinCurry.calories,
      protein: highProteinCurry.protein,
      carbs: highProteinCurry.carbs,
      fat: highProteinCurry.fat,
      mealType: highProteinCurry.mealType,
      loggedAt: DateTime.now(),
    );

    // An anchor favourite in a different food group gives both profiles a
    // fixed reference point, so the normalised (0-1) weight for "Rice &
    // Curry" actually reflects the decayed meal-log weight relative to it,
    // rather than both trivially normalising to 1.0 as the only signal.
    final oldProfile = service.buildProfile(
      meals: [oldMeal],
      favouriteIds: {lightSalad.id},
      allRecipes: allRecipes,
    );
    final recentProfile = service.buildProfile(
      meals: [recentMeal],
      favouriteIds: {lightSalad.id},
      allRecipes: allRecipes,
    );

    expect(
      recentProfile.foodGroupWeights['Rice & Curry']!,
      greaterThan(oldProfile.foodGroupWeights['Rice & Curry']!),
    );
  });

  test('personalisation never introduces a recipe absent from the base list', () {
    final meals = List.generate(
      5,
      (i) => MealLog(
        id: 'm$i',
        recipeId: lightSalad.id,
        recipeName: lightSalad.name,
        calories: lightSalad.calories,
        protein: lightSalad.protein,
        carbs: lightSalad.carbs,
        fat: lightSalad.fat,
        mealType: lightSalad.mealType,
        loggedAt: DateTime.now(),
      ),
    );

    final base = [
      ScoredRecipe(recipe: neutralSoup, score: 80, source: ScoreSource.trainedModel),
      ScoredRecipe(
          recipe: highProteinCurry, score: 70, source: ScoreSource.trainedModel),
    ];

    final result = service.personalize(
      base,
      meals: meals,
      favouriteIds: {lightSalad.id, 'does-not-exist'},
      allRecipes: allRecipes,
    );

    expect(result.items.length, base.length);
    expect(result.items.map((s) => s.recipe.id).toSet(),
        base.map((s) => s.recipe.id).toSet());
  });
}
