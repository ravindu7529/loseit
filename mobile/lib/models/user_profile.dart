import 'package:flutter/foundation.dart';

import 'recipe.dart';

/// Values must match the strings the trained model was fitted on -
/// they are sent verbatim to the API and one-hot encoded there.
const List<String> kGenders = ['Male', 'Female', 'Other'];
const List<String> kActivityLevels = ['Sedentary', 'Light', 'Moderate', 'Active'];
const List<String> kDietaryPrefs = [
  'Non-Vegetarian',
  'Pescatarian',
  'Vegetarian',
  'Vegan',
];
const List<String> kSpicePrefs = ['Mild', 'Medium', 'Hot'];

const Map<String, double> kActivityMultiplier = {
  'Sedentary': 1.2,
  'Light': 1.375,
  'Moderate': 1.55,
  'Active': 1.725,
};

const Map<String, String> kActivityBlurb = {
  'Sedentary': 'Office job, very little exercise',
  'Light': 'Light movement, 1-2 workouts/week',
  'Moderate': 'Daily movement, 3-4 workouts/week',
  'Active': 'Physical job, daily intense exercise',
};

/// Diets ranked from most to least restrictive. A recipe is eligible when
/// its tag rank is <= the user's preference rank. Used by the on-device
/// hard dietary filter, mirroring `DIET_RANK` in the backend.
const Map<String, int> kDietRank = {
  'Vegan': 0,
  'Vegetarian': 1,
  'Pescatarian': 2,
  'Non-Vegetarian': 3,
};

@immutable
class UserProfile {
  final String name;
  final String email;
  final int age;
  final String gender;
  final double heightCm;
  final double weightKg;
  final double targetWeightKg;
  final String activityLevel;
  final String dietaryPref;
  final String spicePref;
  final String allergies;

  const UserProfile({
    this.name = 'Guest',
    this.email = '',
    required this.age,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.targetWeightKg,
    required this.activityLevel,
    required this.dietaryPref,
    required this.spicePref,
    this.allergies = '',
  });

  /// A neutral starting point for the profile form.
  factory UserProfile.initial() => const UserProfile(
        age: 25,
        gender: 'Male',
        heightCm: 175,
        weightKg: 80,
        targetWeightKg: 72,
        activityLevel: 'Moderate',
        dietaryPref: 'Non-Vegetarian',
        spicePref: 'Medium',
        allergies: '',
      );

  // ---------------------------------------------------------------
  // Nutrition maths. Mifflin-St Jeor BMR -> TDEE -> 500 kcal deficit.
  // These formulas are documented and defended in the report; do not
  // change them without updating it (see spec section 6).
  // ---------------------------------------------------------------

  /// Mifflin-St Jeor basal metabolic rate.
  ///
  /// The equation only defines male and female constants. 'Other' uses the
  /// female constant, which yields the lower (more conservative) calorie
  /// target - the safer direction to err in for a weight-loss app.
  double get bmr {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return gender == 'Male' ? base + 5 : base - 161;
  }

  /// Total daily energy expenditure - BMR scaled by activity level.
  double get maintenanceCalories =>
      bmr * (kActivityMultiplier[activityLevel] ?? 1.2);

  /// 500 kcal/day deficit ≈ 0.5 kg/week of loss, floored at a safe
  /// minimum intake so the target never drops into unsafe territory.
  double get dailyCalorieTarget {
    final safeMin = gender == 'Male' ? 1500.0 : 1200.0;
    final target = maintenanceCalories - 500;
    return target < safeMin ? safeMin : target;
  }

  /// A main meal is budgeted at 30% of the daily target.
  double get perMealTarget => dailyCalorieTarget * 0.30;

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  String get bmiCategory {
    final b = bmi;
    if (b < 18.5) return 'Underweight';
    if (b < 25) return 'Healthy';
    if (b < 30) return 'Overweight';
    return 'Obese';
  }

  double get weightToLose {
    final diff = weightKg - targetWeightKg;
    return diff < 0 ? 0 : diff;
  }

  /// Estimated weeks to goal at the 0.5 kg/week the 500 kcal deficit implies.
  int get estimatedWeeksToGoal => (weightToLose / 0.5).ceil();

  /// Macro split: 30% protein, 40% carbs, 30% fat, converted from kcal to
  /// grams (protein/carbs 4 kcal/g, fat 9 kcal/g).
  double get proteinTargetG => dailyCalorieTarget * 0.30 / 4;
  double get carbsTargetG => dailyCalorieTarget * 0.40 / 4;
  double get fatTargetG => dailyCalorieTarget * 0.30 / 9;

  /// Normalized list of foods and allergens to strictly avoid.
  List<String> get avoidList {
    if (allergies.trim().isEmpty) return const [];
    final set = <String>{};
    for (final raw in allergies.split(RegExp(r'[,;\n]'))) {
      final s = raw.trim().toLowerCase();
      if (s.isEmpty) continue;
      set.add(s);
      if (s.endsWith('ies') && s.length > 4) {
        set.add('${s.substring(0, s.length - 3)}y');
      } else if (s.endsWith('es') && s.length > 3) {
        set.add(s.substring(0, s.length - 2));
      } else if (s.endsWith('s') && s.length > 3) {
        set.add(s.substring(0, s.length - 1));
      }
    }
    return set.toList();
  }

  /// True when [recipeDietaryTag] is allowed for this user's preference.
  /// This is a hard filter, applied before any scoring - never learned.
  bool allowsDiet(String recipeDietaryTag) {
    final pref = kDietRank[dietaryPref] ?? 3;
    final tag = kDietRank[recipeDietaryTag] ?? 3;
    return tag <= pref;
  }

  /// True when the recipe satisfies dietary rank AND contains none of the user's
  /// specified allergens or avoided foods.
  bool allowsRecipe(Recipe r) {
    if (!allowsDiet(r.dietaryTag)) return false;
    final avoids = avoidList;
    if (avoids.isEmpty) return true;

    final targetText = '${r.name} ${r.mainIngredient} ${r.keyIngredients} ${r.category} ${r.description}'.toLowerCase();
    for (final avoid in avoids) {
      if (avoid.isEmpty) continue;
      if (targetText.contains(avoid)) {
        return false;
      }
    }
    return true;
  }

  UserProfile copyWith({
    String? name,
    String? email,
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
    double? targetWeightKg,
    String? activityLevel,
    String? dietaryPref,
    String? spicePref,
    String? allergies,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      dietaryPref: dietaryPref ?? this.dietaryPref,
      spicePref: spicePref ?? this.spicePref,
      allergies: allergies ?? this.allergies,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'age': age,
        'gender': gender,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'target_weight_kg': targetWeightKg,
        'activity_level': activityLevel,
        'dietary_pref': dietaryPref,
        'spice_pref': spicePref,
        'allergies': allergies,
      };

  /// The exact payload shape `POST /recommend` expects.
  Map<String, dynamic> toApiRequest({int topN = 30, String? mealType}) => {
        'age': age,
        'gender': gender,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'activity_level': activityLevel,
        'dietary_pref': dietaryPref,
        'spice_pref': spicePref,
        'allergies': allergies,
        'avoid_ingredients': avoidList,
        'top_n': topN,
        'meal_type': ?mealType,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    double d(String k, double fallback) {
      final v = json[k];
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? fallback;
    }

    String s(String k, String fallback, List<String> allowed) {
      final v = json[k];
      return (v is String && allowed.contains(v)) ? v : fallback;
    }

    return UserProfile(
      name: json['name'] as String? ?? 'Guest',
      email: json['email'] as String? ?? '',
      age: (json['age'] as num?)?.round() ?? 25,
      gender: s('gender', 'Male', kGenders),
      heightCm: d('height_cm', 175),
      weightKg: d('weight_kg', 80),
      targetWeightKg: d('target_weight_kg', 72),
      activityLevel: s('activity_level', 'Moderate', kActivityLevels),
      dietaryPref: s('dietary_pref', 'Non-Vegetarian', kDietaryPrefs),
      spicePref: s('spice_pref', 'Medium', kSpicePrefs),
      allergies: json['allergies'] as String? ?? '',
    );
  }
}
