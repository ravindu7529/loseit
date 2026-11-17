import 'package:flutter/foundation.dart';

/// One Sri Lankan recipe from the 300-item dataset.
///
/// Field names mirror the JSON keys produced by `backend/generate_recipes.py`
/// so the same file can be bundled as a Flutter asset and read by the
/// Python training pipeline without a translation layer.
@immutable
class Recipe {
  final String id;
  final String name;
  final String category;
  final String mainIngredient;
  final String dietaryTag;
  final String mealType;
  final String spiceLevel;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final int prepTimeMin;
  final int cookTimeMin;
  final int servings;
  final String keyIngredients;
  final String description;
  final String foodGroup;
  final String? imageUrl;
  final String? cookingSteps;
  final bool isGenerated;
  final int? noveltyScorePercent;
  final String? inspirationRecipe;

  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.mainIngredient,
    required this.dietaryTag,
    required this.mealType,
    required this.spiceLevel,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.prepTimeMin,
    required this.cookTimeMin,
    required this.servings,
    required this.keyIngredients,
    required this.description,
    required this.foodGroup,
    this.imageUrl,
    this.cookingSteps,
    this.isGenerated = false,
    this.noveltyScorePercent,
    this.inspirationRecipe,
  });

  int get totalTimeMin => prepTimeMin + cookTimeMin;

  /// Comma-separated `Key_Ingredients` split into a display list.
  List<String> get ingredientList => keyIngredients
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Short badges shown on cards ("High protein", "Low fat", ...).
  /// Derived from the nutrition numbers rather than stored, so they stay
  /// consistent if the dataset is regenerated.
  List<String> get tags {
    final out = <String>[];
    if (isGenerated) {
      out.add('AI Invented');
    }
    if (protein >= 20) {
      out.add('High protein');
    }
    if (fiber >= 4) {
      out.add('High fibre');
    }
    if (fat <= 8) {
      out.add('Low fat');
    }
    if (calories <= 200) {
      out.add('Light');
    }
    if (dietaryTag == 'Vegan') {
      out.add('Vegan');
    }
    return out.take(2).toList();
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  factory Recipe.fromJson(Map<String, dynamic> json) {
    final noveltyMap = json['novelty'] is Map ? (json['novelty'] as Map<String, dynamic>) : null;
    return Recipe(
      id: json['Recipe_ID'] as String? ?? '',
      name: json['Recipe_Name'] as String? ?? 'Unnamed recipe',
      category: json['Category'] as String? ?? '',
      mainIngredient: json['Main_Ingredient'] as String? ?? '',
      dietaryTag: json['Dietary_Tag'] as String? ?? 'Non-Vegetarian',
      mealType: json['Meal_Type'] as String? ?? 'Lunch',
      spiceLevel: json['Spice_Level'] as String? ?? 'Medium',
      calories: _toInt(json['Calories_kcal']),
      protein: _toDouble(json['Protein_g']),
      carbs: _toDouble(json['Carbs_g']),
      fat: _toDouble(json['Fat_g']),
      fiber: _toDouble(json['Fiber_g']),
      prepTimeMin: _toInt(json['Prep_Time_Min']),
      cookTimeMin: _toInt(json['Cook_Time_Min']),
      servings: _toInt(json['Servings']),
      keyIngredients: json['Key_Ingredients'] as String? ?? '',
      description: json['Short_Description'] as String? ?? '',
      foodGroup: json['Food_Group'] as String? ?? '',
      imageUrl: json['Image_Url'] as String? ?? json['image_url'] as String? ?? json['Image'] as String?,
      cookingSteps: json['Cooking_Steps'] as String?,
      isGenerated: json['is_generated'] as bool? ?? false,
      noveltyScorePercent: noveltyMap != null ? (noveltyMap['novelty_score_percent'] as num?)?.toInt() : null,
      inspirationRecipe: noveltyMap != null ? noveltyMap['closest_inspiration'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'Recipe_ID': id,
        'Recipe_Name': name,
        'Category': category,
        'Main_Ingredient': mainIngredient,
        'Dietary_Tag': dietaryTag,
        'Meal_Type': mealType,
        'Spice_Level': spiceLevel,
        'Calories_kcal': calories,
        'Protein_g': protein,
        'Carbs_g': carbs,
        'Fat_g': fat,
        'Fiber_g': fiber,
        'Prep_Time_Min': prepTimeMin,
        'Cook_Time_Min': cookTimeMin,
        'Servings': servings,
        'Key_Ingredients': keyIngredients,
        'Short_Description': description,
        'Food_Group': foodGroup,
        'Image_Url': imageUrl,
        'Cooking_Steps': cookingSteps,
        'is_generated': isGenerated,
        'novelty': {
          'novelty_score_percent': noveltyScorePercent ?? 0,
          'closest_inspiration': inspirationRecipe ?? '',
        },
      };

  @override
  bool operator ==(Object other) => other is Recipe && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A recipe paired with the score that ranked it, plus where that score
/// came from. The UI surfaces the source so it is always honest about
/// whether the trained model or the offline fallback produced the list.
@immutable
class ScoredRecipe {
  final Recipe recipe;
  final double score;
  final ScoreSource source;

  const ScoredRecipe({
    required this.recipe,
    required this.score,
    required this.source,
  });
}

enum ScoreSource {
  /// Scored by the trained MLP served from the FastAPI backend.
  trainedModel,

  /// Scored on-device by the rule-based fallback in `recipe_service.dart`.
  localFallback,
}

extension ScoreSourceLabel on ScoreSource {
  String get label => switch (this) {
        ScoreSource.trainedModel => 'AI PICK',
        ScoreSource.localFallback => 'OFFLINE',
      };

  String get description => switch (this) {
        ScoreSource.trainedModel =>
          'Ranked by the trained neural network on the Spice & Scale server.',
        ScoreSource.localFallback =>
          'Server unreachable - ranked on-device by the rule-based fallback.',
      };
}
