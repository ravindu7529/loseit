import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loseit/models/recipe.dart';
import 'package:loseit/models/user_profile.dart';
import 'package:loseit/services/recipe_service.dart';

/// A small stand-in dataset covering every dietary tag.
List<Recipe> _fixtures() => [
      Recipe.fromJson({
        'Recipe_ID': 'T001',
        'Recipe_Name': 'Chicken Curry',
        'Category': 'Curry',
        'Main_Ingredient': 'Chicken',
        'Dietary_Tag': 'Non-Vegetarian',
        'Meal_Type': 'Lunch',
        'Spice_Level': 'Medium',
        'Calories_kcal': 340,
        'Protein_g': 21.0,
        'Carbs_g': 6.0,
        'Fat_g': 13.0,
        'Fiber_g': 2.5,
        'Prep_Time_Min': 18,
        'Cook_Time_Min': 17,
        'Servings': 4,
        'Key_Ingredients': 'Chicken, coconut milk, curry leaves',
        'Short_Description': 'A light everyday chicken curry.',
        'Food_Group': 'Rice & Curry',
      }),
      Recipe.fromJson({
        'Recipe_ID': 'T002',
        'Recipe_Name': 'Fish Ambul Thiyal',
        'Dietary_Tag': 'Pescatarian',
        'Meal_Type': 'Dinner',
        'Spice_Level': 'Hot',
        'Calories_kcal': 320,
        'Protein_g': 32.0,
        'Carbs_g': 12.0,
        'Fat_g': 8.0,
        'Fiber_g': 1.5,
        'Prep_Time_Min': 20,
        'Cook_Time_Min': 25,
        'Servings': 2,
        'Key_Ingredients': 'Tuna, goraka, black pepper',
        'Food_Group': 'Seafood',
      }),
      Recipe.fromJson({
        'Recipe_ID': 'T003',
        'Recipe_Name': 'Egg Hoppers',
        'Dietary_Tag': 'Vegetarian',
        'Meal_Type': 'Breakfast',
        'Spice_Level': 'Mild',
        'Calories_kcal': 210,
        'Protein_g': 9.0,
        'Carbs_g': 28.0,
        'Fat_g': 6.0,
        'Fiber_g': 1.0,
        'Prep_Time_Min': 15,
        'Cook_Time_Min': 10,
        'Servings': 2,
        'Key_Ingredients': 'Rice flour, coconut milk, egg',
        'Food_Group': 'Bread & Hoppers',
      }),
      Recipe.fromJson({
        'Recipe_ID': 'T004',
        'Recipe_Name': 'Gotu Kola Sambol',
        'Dietary_Tag': 'Vegan',
        'Meal_Type': 'Lunch',
        'Spice_Level': 'Medium',
        'Calories_kcal': 120,
        'Protein_g': 4.0,
        'Carbs_g': 12.0,
        'Fat_g': 5.0,
        'Fiber_g': 6.0,
        'Prep_Time_Min': 10,
        'Cook_Time_Min': 0,
        'Servings': 2,
        'Key_Ingredients': 'Gotu kola, coconut, lime',
        'Food_Group': 'Leafy Greens',
      }),
    ];

const _vegan = UserProfile(
  age: 30,
  gender: 'Female',
  heightCm: 165,
  weightKg: 72,
  targetWeightKg: 65,
  activityLevel: 'Light',
  dietaryPref: 'Vegan',
  spicePref: 'Medium',
);

const _omnivore = UserProfile(
  age: 30,
  gender: 'Male',
  heightCm: 178,
  weightKg: 88,
  targetWeightKg: 78,
  activityLevel: 'Moderate',
  dietaryPref: 'Non-Vegetarian',
  spicePref: 'Hot',
);

void main() {
  group('local rule-based fallback', () {
    test('never returns a recipe outside the dietary preference', () {
      final service = RecipeService();
      final result = service.scoreLocally(_vegan, _fixtures(), topN: 10);

      expect(result, isNotEmpty);
      for (final s in result) {
        expect(s.recipe.dietaryTag, 'Vegan',
            reason: '${s.recipe.name} leaked past the hard dietary filter');
      }
      service.dispose();
    });

    test('pescatarian excludes only non-vegetarian dishes', () {
      final service = RecipeService();
      final p = _omnivore.copyWith(dietaryPref: 'Pescatarian');
      final ids =
          service.scoreLocally(p, _fixtures(), topN: 10).map((s) => s.recipe.id);

      expect(ids, isNot(contains('T001'))); // chicken
      expect(ids, contains('T002')); // fish
      expect(ids, contains('T003')); // vegetarian
      expect(ids, contains('T004')); // vegan
      service.dispose();
    });

    test('baseline score matches the backend formula', () {
      // calorieFit * 0.7 + min(protein, 40) * 0.75
      final recipe = _fixtures()[1]; // 320 kcal, 32g protein
      const perMeal = 400.0;
      final calorieFit =
          (100 - (320 - perMeal).abs() / perMeal * 100).clamp(0.0, 100.0);
      final expected = calorieFit * 0.7 + 32.0 * 0.75;

      expect(RecipeService.baselineScore(recipe, perMeal),
          closeTo(expected, 0.0001));
    });

    test('ranks in descending score order', () {
      final service = RecipeService();
      final result = service.scoreLocally(_omnivore, _fixtures(), topN: 10);
      for (var i = 0; i < result.length - 1; i++) {
        expect(result[i].score, greaterThanOrEqualTo(result[i + 1].score));
      }
      service.dispose();
    });

    test('meal-type filter narrows results but never empties them', () {
      final service = RecipeService();

      final breakfast = service.scoreLocally(
        _omnivore,
        _fixtures(),
        mealType: 'Breakfast',
      );
      expect(breakfast.every((s) => s.recipe.mealType == 'Breakfast'), isTrue);

      // 'Snack' matches nothing in the fixtures - falls back to the full
      // eligible set rather than showing an empty screen.
      final snack =
          service.scoreLocally(_omnivore, _fixtures(), mealType: 'Snack');
      expect(snack, isNotEmpty);
      service.dispose();
    });

    test('honours topN', () {
      final service = RecipeService();
      expect(service.scoreLocally(_omnivore, _fixtures(), topN: 2).length, 2);
      service.dispose();
    });
  });

  group('API path', () {
    test('parses a /recommend response and marks it as trained-model', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/recommend');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['dietary_pref'], 'Non-Vegetarian');
        return http.Response(
          jsonEncode({
            'source': 'trained-model-api',
            'daily_calorie_target': 2100,
            'recommendations': [
              {'recipe_id': 'T002', 'predicted_score': 88.4},
              {'recipe_id': 'T001', 'predicted_score': 71.2},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = RecipeService(client: client);
      final scored = await service.recommendWithRecipes(
        _omnivore,
        _fixtures(),
      );

      expect(scored.source, ScoreSource.trainedModel);
      expect(scored.items.length, 2);
      expect(scored.items.first.recipe.id, 'T002');
      expect(scored.items.first.score, closeTo(88.4, 0.001));
      service.dispose();
    });

    test('falls back to local scoring when the API errors', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final service = RecipeService(client: client);

      final scored =
          await service.recommendWithRecipes(_omnivore, _fixtures());

      expect(scored.source, ScoreSource.localFallback);
      expect(scored.items, isNotEmpty);
      service.dispose();
    });

    test('falls back when the API returns unknown recipe IDs', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'recommendations': [
                {'recipe_id': 'NOT_IN_DATASET', 'predicted_score': 99.0},
              ],
            }),
            200,
          ));
      final service = RecipeService(client: client);

      final scored =
          await service.recommendWithRecipes(_omnivore, _fixtures());

      expect(scored.source, ScoreSource.localFallback);
      service.dispose();
    });

    test('checkHealth reports false when the server is down', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      final service = RecipeService(client: client);
      expect(await service.checkHealth(), isFalse);
      service.dispose();
    });
  });

  group('Recipe model', () {
    test('parses and derives values', () {
      final r = _fixtures().first;
      expect(r.id, 'T001');
      expect(r.totalTimeMin, 35);
      expect(r.ingredientList.length, 3);
      expect(r.tags, contains('High protein'));
    });

    test('tolerates missing fields', () {
      final r = Recipe.fromJson({'Recipe_ID': 'X'});
      expect(r.id, 'X');
      expect(r.calories, 0);
      expect(r.name, 'Unnamed recipe');
      expect(r.ingredientList, isEmpty);
      expect(r.imageUrl, isNull);
    });

    test('parses imageUrl from various key formats', () {
      final r1 = Recipe.fromJson({
        'Recipe_ID': 'IMG1',
        'Image_Url': 'https://images.unsplash.com/photo-test-1',
      });
      expect(r1.imageUrl, 'https://images.unsplash.com/photo-test-1');

      final r2 = Recipe.fromJson({
        'Recipe_ID': 'IMG2',
        'image_url': 'https://images.unsplash.com/photo-test-2',
      });
      expect(r2.imageUrl, 'https://images.unsplash.com/photo-test-2');

      final r3 = Recipe.fromJson({
        'Recipe_ID': 'IMG3',
        'Image': 'https://images.unsplash.com/photo-test-3',
      });
      expect(r3.imageUrl, 'https://images.unsplash.com/photo-test-3');
    });
  });
}
