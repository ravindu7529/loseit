import 'package:flutter_test/flutter_test.dart';
import 'package:loseit/models/recipe.dart';
import 'package:loseit/models/user_profile.dart';

void main() {
  group('Mifflin-St Jeor BMR', () {
    test('male formula matches the published equation', () {
      const p = UserProfile(
        age: 30,
        gender: 'Male',
        heightCm: 180,
        weightKg: 80,
        targetWeightKg: 75,
        activityLevel: 'Sedentary',
        dietaryPref: 'Non-Vegetarian',
        spicePref: 'Medium',
      );
      // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5
      expect(p.bmr, closeTo(1780, 0.001));
    });

    test('female formula uses the -161 constant', () {
      const p = UserProfile(
        age: 30,
        gender: 'Female',
        heightCm: 165,
        weightKg: 70,
        targetWeightKg: 62,
        activityLevel: 'Light',
        dietaryPref: 'Vegetarian',
        spicePref: 'Mild',
      );
      // 10*70 + 6.25*165 - 5*30 - 161 = 700 + 1031.25 - 150 - 161
      expect(p.bmr, closeTo(1420.25, 0.001));
    });

    test("'Other' uses the lower (female) constant as the safer estimate", () {
      const other = UserProfile(
        age: 30,
        gender: 'Other',
        heightCm: 170,
        weightKg: 75,
        targetWeightKg: 70,
        activityLevel: 'Moderate',
        dietaryPref: 'Vegan',
        spicePref: 'Hot',
      );
      const female = UserProfile(
        age: 30,
        gender: 'Female',
        heightCm: 170,
        weightKg: 75,
        targetWeightKg: 70,
        activityLevel: 'Moderate',
        dietaryPref: 'Vegan',
        spicePref: 'Hot',
      );
      expect(other.bmr, female.bmr);
    });
  });

  group('calorie targets', () {
    test('applies the activity multiplier then a 500 kcal deficit', () {
      const p = UserProfile(
        age: 30,
        gender: 'Male',
        heightCm: 180,
        weightKg: 80,
        targetWeightKg: 75,
        activityLevel: 'Moderate',
        dietaryPref: 'Non-Vegetarian',
        spicePref: 'Medium',
      );
      expect(p.maintenanceCalories, closeTo(1780 * 1.55, 0.001));
      expect(p.dailyCalorieTarget, closeTo(1780 * 1.55 - 500, 0.001));
      expect(p.perMealTarget, closeTo(p.dailyCalorieTarget * 0.30, 0.001));
    });

    test('never drops below the safe floor', () {
      // A very small sedentary profile would otherwise fall under 1200.
      const p = UserProfile(
        age: 60,
        gender: 'Female',
        heightCm: 150,
        weightKg: 45,
        targetWeightKg: 45,
        activityLevel: 'Sedentary',
        dietaryPref: 'Vegetarian',
        spicePref: 'Mild',
      );
      expect(p.maintenanceCalories - 500, lessThan(1200));
      expect(p.dailyCalorieTarget, 1200);
    });

    test('male floor is 1500', () {
      const p = UserProfile(
        age: 70,
        gender: 'Male',
        heightCm: 155,
        weightKg: 48,
        targetWeightKg: 48,
        activityLevel: 'Sedentary',
        dietaryPref: 'Non-Vegetarian',
        spicePref: 'Mild',
      );
      expect(p.dailyCalorieTarget, 1500);
    });
  });

  group('hard dietary filter', () {
    const base = UserProfile(
      age: 30,
      gender: 'Female',
      heightCm: 165,
      weightKg: 70,
      targetWeightKg: 62,
      activityLevel: 'Light',
      dietaryPref: 'Vegan',
      spicePref: 'Medium',
    );

    test('vegan accepts only vegan', () {
      expect(base.allowsDiet('Vegan'), isTrue);
      expect(base.allowsDiet('Vegetarian'), isFalse);
      expect(base.allowsDiet('Pescatarian'), isFalse);
      expect(base.allowsDiet('Non-Vegetarian'), isFalse);
    });

    test('vegetarian accepts vegan and vegetarian', () {
      final p = base.copyWith(dietaryPref: 'Vegetarian');
      expect(p.allowsDiet('Vegan'), isTrue);
      expect(p.allowsDiet('Vegetarian'), isTrue);
      expect(p.allowsDiet('Pescatarian'), isFalse);
      expect(p.allowsDiet('Non-Vegetarian'), isFalse);
    });

    test('pescatarian accepts everything except non-vegetarian', () {
      final p = base.copyWith(dietaryPref: 'Pescatarian');
      expect(p.allowsDiet('Vegan'), isTrue);
      expect(p.allowsDiet('Vegetarian'), isTrue);
      expect(p.allowsDiet('Pescatarian'), isTrue);
      expect(p.allowsDiet('Non-Vegetarian'), isFalse);
    });

    test('non-vegetarian accepts everything', () {
      final p = base.copyWith(dietaryPref: 'Non-Vegetarian');
      for (final tag in kDietaryPrefs) {
        expect(p.allowsDiet(tag), isTrue, reason: 'should allow $tag');
      }
    });
  });

  group('derived values', () {
    test('BMI and category', () {
      const p = UserProfile(
        age: 28,
        gender: 'Female',
        heightCm: 162,
        weightKg: 78,
        targetWeightKg: 68,
        activityLevel: 'Light',
        dietaryPref: 'Vegetarian',
        spicePref: 'Medium',
      );
      expect(p.bmi, closeTo(78 / (1.62 * 1.62), 0.001));
      expect(p.bmi, closeTo(29.72, 0.01));
      expect(p.bmiCategory, 'Overweight'); // 25 <= BMI < 30
      expect(p.weightToLose, closeTo(10, 0.001));
      expect(p.estimatedWeeksToGoal, 20); // 10kg at 0.5kg/week
    });

    test('BMI category boundaries', () {
      const base = UserProfile(
        age: 30,
        gender: 'Female',
        heightCm: 100, // 1m, so weightKg == BMI
        weightKg: 50,
        targetWeightKg: 50,
        activityLevel: 'Light',
        dietaryPref: 'Vegetarian',
        spicePref: 'Medium',
      );
      expect(base.copyWith(weightKg: 18.0).bmiCategory, 'Underweight');
      expect(base.copyWith(weightKg: 18.5).bmiCategory, 'Healthy');
      expect(base.copyWith(weightKg: 24.9).bmiCategory, 'Healthy');
      expect(base.copyWith(weightKg: 25.0).bmiCategory, 'Overweight');
      expect(base.copyWith(weightKg: 29.9).bmiCategory, 'Overweight');
      expect(base.copyWith(weightKg: 30.0).bmiCategory, 'Obese');
    });

    test('weightToLose never goes negative', () {
      const p = UserProfile(
        age: 28,
        gender: 'Male',
        heightCm: 175,
        weightKg: 70,
        targetWeightKg: 75,
        activityLevel: 'Active',
        dietaryPref: 'Non-Vegetarian',
        spicePref: 'Hot',
      );
      expect(p.weightToLose, 0);
    });

    test('macro targets split 30/40/30 by calories', () {
      const p = UserProfile(
        age: 30,
        gender: 'Male',
        heightCm: 180,
        weightKg: 80,
        targetWeightKg: 75,
        activityLevel: 'Moderate',
        dietaryPref: 'Non-Vegetarian',
        spicePref: 'Medium',
      );
      final kcalFromMacros =
          p.proteinTargetG * 4 + p.carbsTargetG * 4 + p.fatTargetG * 9;
      expect(kcalFromMacros, closeTo(p.dailyCalorieTarget, 0.001));
    });
  });

  group('serialisation', () {
    test('round-trips through JSON', () {
      const p = UserProfile(
        name: 'Kasun',
        email: 'kasun@example.com',
        age: 34,
        gender: 'Male',
        heightCm: 174.5,
        weightKg: 82.3,
        targetWeightKg: 74,
        activityLevel: 'Active',
        dietaryPref: 'Pescatarian',
        spicePref: 'Hot',
      );
      final restored = UserProfile.fromJson(p.toJson());
      expect(restored.name, p.name);
      expect(restored.email, p.email);
      expect(restored.age, p.age);
      expect(restored.heightCm, p.heightCm);
      expect(restored.weightKg, p.weightKg);
      expect(restored.dietaryPref, p.dietaryPref);
      expect(restored.spicePref, p.spicePref);
      expect(restored.bmr, p.bmr);
    });

    test('falls back to safe defaults on corrupt values', () {
      final p = UserProfile.fromJson({
        'gender': 'Martian',
        'activity_level': 'Hyperactive',
        'dietary_pref': 'Carnivore',
        'spice_pref': 'Nuclear',
      });
      expect(kGenders, contains(p.gender));
      expect(kActivityLevels, contains(p.activityLevel));
      expect(kDietaryPrefs, contains(p.dietaryPref));
      expect(kSpicePrefs, contains(p.spicePref));
    });

    test('API request payload carries the model input fields', () {
      const p = UserProfile(
        age: 28,
        gender: 'Female',
        heightCm: 162,
        weightKg: 78,
        targetWeightKg: 68,
        activityLevel: 'Light',
        dietaryPref: 'Vegetarian',
        spicePref: 'Medium',
      );
      final body = p.toApiRequest(topN: 5, mealType: 'Dinner');
      expect(body['age'], 28);
      expect(body['gender'], 'Female');
      expect(body['activity_level'], 'Light');
      expect(body['dietary_pref'], 'Vegetarian');
      expect(body['spice_pref'], 'Medium');
      expect(body['top_n'], 5);
      expect(body['meal_type'], 'Dinner');
    });

    test('meal_type is omitted when not requested', () {
      final body = UserProfile.initial().toApiRequest();
      expect(body.containsKey('meal_type'), isFalse);
    });

    test('allergies field parses into normalized avoidList', () {
      final p = UserProfile.initial().copyWith(allergies: 'Peanuts, Dairy; Shellfish \n mushrooms');
      expect(p.avoidList, containsAll(['peanuts', 'peanut', 'dairy', 'shellfish', 'mushrooms', 'mushroom']));
    });

    test('allowsRecipe filters both dietary tag and avoided ingredients', () {
      final p = UserProfile.initial().copyWith(
        dietaryPref: 'Vegetarian',
        allergies: 'peanuts, mushroom',
      );

      const r1 = Recipe(
        id: '1',
        name: 'Dhal Curry with Coconut Milk',
        category: 'Curry',
        mainIngredient: 'Red Lentils',
        dietaryTag: 'Vegetarian',
        mealType: 'Dinner',
        spiceLevel: 'Medium',
        calories: 220,
        protein: 12,
        carbs: 30,
        fat: 5,
        fiber: 6,
        prepTimeMin: 10,
        cookTimeMin: 20,
        servings: 2,
        keyIngredients: 'Lentils, coconut milk, curry leaves',
        description: 'Traditional Sri Lankan dhal curry',
        foodGroup: 'Legumes',
      );

      const r2 = Recipe(
        id: '2',
        name: 'Spiced Mushroom Curry',
        category: 'Curry',
        mainIngredient: 'Mushroom',
        dietaryTag: 'Vegetarian',
        mealType: 'Dinner',
        spiceLevel: 'Medium',
        calories: 180,
        protein: 6,
        carbs: 18,
        fat: 4,
        fiber: 4,
        prepTimeMin: 10,
        cookTimeMin: 15,
        servings: 2,
        keyIngredients: 'Mushroom, onion, curry powder',
        description: 'Fragrant mushroom curry',
        foodGroup: 'Vegetables',
      );

      const r3 = Recipe(
        id: '3',
        name: 'Chicken Kottu',
        category: 'Kottu',
        mainIngredient: 'Chicken',
        dietaryTag: 'Non-Vegetarian',
        mealType: 'Dinner',
        spiceLevel: 'Hot',
        calories: 450,
        protein: 28,
        carbs: 55,
        fat: 14,
        fiber: 3,
        prepTimeMin: 15,
        cookTimeMin: 15,
        servings: 1,
        keyIngredients: 'Roti, chicken, leeks, egg',
        description: 'Street-style kottu',
        foodGroup: 'Meat',
      );

      expect(p.allowsRecipe(r1), isTrue);
      expect(p.allowsRecipe(r2), isFalse); // contains mushroom (avoided)
      expect(p.allowsRecipe(r3), isFalse); // non-veg (excluded by vegetarian pref)
    });
  });
}
