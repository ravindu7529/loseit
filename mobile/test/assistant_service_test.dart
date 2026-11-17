import 'package:flutter_test/flutter_test.dart';
import 'package:loseit/models/recipe.dart';
import 'package:loseit/models/user_profile.dart';
import 'package:loseit/services/assistant_service.dart';

List<Recipe> _fixtures() => [
      Recipe.fromJson({
        'Recipe_ID': 'A1',
        'Recipe_Name': 'Pol Sambol',
        'Dietary_Tag': 'Vegan',
        'Meal_Type': 'Breakfast',
        'Spice_Level': 'Hot',
        'Calories_kcal': 180,
        'Protein_g': 3.0,
        'Carbs_g': 8.0,
        'Fat_g': 15.0,
        'Fiber_g': 4.5,
        'Prep_Time_Min': 10,
        'Cook_Time_Min': 0,
        'Servings': 4,
        'Key_Ingredients': 'Coconut, chilli, lime, onion',
        'Food_Group': 'Sambol',
      }),
      Recipe.fromJson({
        'Recipe_ID': 'A2',
        'Recipe_Name': 'Chicken Kottu',
        'Dietary_Tag': 'Non-Vegetarian',
        'Meal_Type': 'Dinner',
        'Spice_Level': 'Medium',
        'Calories_kcal': 620,
        'Protein_g': 28.0,
        'Carbs_g': 62.0,
        'Fat_g': 22.0,
        'Fiber_g': 3.0,
        'Prep_Time_Min': 20,
        'Cook_Time_Min': 15,
        'Servings': 2,
        'Key_Ingredients': 'Godamba roti, chicken, leeks, egg',
        'Food_Group': 'Rice & Curry',
      }),
      Recipe.fromJson({
        'Recipe_ID': 'A3',
        'Recipe_Name': 'Dhal Curry',
        'Dietary_Tag': 'Vegan',
        'Meal_Type': 'Lunch',
        'Spice_Level': 'Mild',
        'Calories_kcal': 240,
        'Protein_g': 12.0,
        'Carbs_g': 34.0,
        'Fat_g': 7.0,
        'Fiber_g': 8.0,
        'Prep_Time_Min': 10,
        'Cook_Time_Min': 25,
        'Servings': 4,
        'Key_Ingredients': 'Red lentils, coconut milk, turmeric',
        'Food_Group': 'Rice & Curry',
      }),
    ];

const _profile = UserProfile(
  name: 'Kasun',
  age: 30,
  gender: 'Male',
  heightCm: 175,
  weightKg: 85,
  targetWeightKg: 75,
  activityLevel: 'Moderate',
  dietaryPref: 'Non-Vegetarian',
  spicePref: 'Medium',
);

void main() {
  late AssistantService service;

  setUp(() => service = AssistantService());
  tearDown(() => service.dispose());

  test('defaults to the offline engine when no API key is configured', () {
    expect(service.hasApiKey, isFalse);
  });

  group('retrieval', () {
    test('finds a dish by name', () {
      final hits = service.retrieve('calories in pol sambol', _profile, _fixtures());
      expect(hits.first.id, 'A1');
    });

    test('matches on ingredients too', () {
      final hits = service.retrieve('lentils', _profile, _fixtures());
      expect(hits.map((r) => r.id), contains('A3'));
    });

    test('respects the hard dietary filter', () {
      final vegan = _profile.copyWith(dietaryPref: 'Vegan');
      final hits = service.retrieve('kottu chicken', vegan, _fixtures());
      expect(hits.map((r) => r.id), isNot(contains('A2')));
    });

    test('returns nothing for a question with no usable tokens', () {
      expect(service.retrieve('the a of', _profile, _fixtures()), isEmpty);
    });
  });

  group('offline answers', () {
    test('quotes stored calories for a named dish', () {
      final reply = service.answerLocally(
        'how many calories in pol sambol',
        _profile,
        _fixtures(),
      );
      expect(reply.source, AssistantSource.localGrounded);
      expect(reply.text, contains('180 kcal'));
      expect(reply.citedRecipeIds, contains('A1'));
    });

    test('reports the calculated daily target', () {
      final reply = service.answerLocally(
        'how many calories should i eat a day',
        _profile,
        _fixtures(),
      );
      expect(
        reply.text,
        contains('${_profile.dailyCalorieTarget.round()}'),
      );
    });

    test('reports BMI from the profile', () {
      final reply = service.answerLocally('what is my bmi', _profile, _fixtures());
      expect(reply.text, contains(_profile.bmi.toStringAsFixed(1)));
    });

    test('high-protein request ranks the highest-protein dish first', () {
      final reply = service.answerLocally(
        'high protein dinner ideas',
        _profile,
        _fixtures(),
      );
      expect(reply.citedRecipeIds.first, 'A2'); // 28g protein
    });

    test('low-calorie request ranks the lightest dish first', () {
      final reply = service.answerLocally(
        'low calorie options please',
        _profile,
        _fixtures(),
      );
      expect(reply.citedRecipeIds.first, 'A1'); // 180 kcal
    });

    test('suggestions never breach the dietary filter', () {
      final vegan = _profile.copyWith(dietaryPref: 'Vegan');
      final reply = service.answerLocally(
        'suggest a high protein dinner',
        vegan,
        _fixtures(),
      );
      expect(reply.citedRecipeIds, isNot(contains('A2')));
    });

    test('greets and states the target', () {
      final reply = service.answerLocally('hello', _profile, _fixtures());
      expect(reply.text, contains('Ayubowan'));
    });

    test('answers ingredient questions from stored data', () {
      final reply = service.answerLocally(
        'what ingredients are in dhal curry',
        _profile,
        _fixtures(),
      );
      expect(reply.text.toLowerCase(), contains('lentils'));
    });

    test('says so plainly when nothing matches', () {
      final reply = service.answerLocally(
        'tell me about quantum tunnelling',
        _profile,
        _fixtures(),
      );
      expect(reply.text, contains('could not match'));
      expect(reply.citedRecipeIds, isEmpty);
    });

    test('every cited calorie figure exists in the dataset', () {
      // Guards the core property: the offline engine can only quote
      // numbers it read out of the dataset.
      final questions = [
        'calories in pol sambol',
        'calories in chicken kottu',
        'calories in dhal curry',
      ];
      final byId = {for (final r in _fixtures()) r.id: r};

      for (final q in questions) {
        final reply = service.answerLocally(q, _profile, _fixtures());
        for (final id in reply.citedRecipeIds) {
          expect(reply.text, contains('${byId[id]!.calories} kcal'));
        }
      }
    });
  });
}
