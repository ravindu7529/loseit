import 'package:flutter/foundation.dart';

/// A meal the user logged against a day's calorie budget.
@immutable
class MealLog {
  final String id;
  final String recipeId;
  final String recipeName;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final String mealType;
  final DateTime loggedAt;

  const MealLog({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.mealType,
    required this.loggedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'recipe_id': recipeId,
        'recipe_name': recipeName,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'meal_type': mealType,
        'logged_at': loggedAt.toIso8601String(),
      };

  factory MealLog.fromJson(Map<String, dynamic> json) => MealLog(
        id: json['id'] as String? ?? '',
        recipeId: json['recipe_id'] as String? ?? '',
        recipeName: json['recipe_name'] as String? ?? '',
        calories: (json['calories'] as num?)?.round() ?? 0,
        protein: (json['protein'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
        fat: (json['fat'] as num?)?.toDouble() ?? 0,
        mealType: json['meal_type'] as String? ?? 'Lunch',
        loggedAt:
            DateTime.tryParse(json['logged_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// A single weigh-in.
@immutable
class WeightEntry {
  final String id;
  final double weightKg;
  final DateTime recordedAt;

  const WeightEntry({
    required this.id,
    required this.weightKg,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'weight_kg': weightKg,
        'recorded_at': recordedAt.toIso8601String(),
      };

  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
        id: json['id'] as String? ?? '',
        weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
        recordedAt: DateTime.tryParse(json['recorded_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Who is speaking in the AI assistant transcript.
enum ChatRole { user, assistant }

@immutable
class ChatMessage {
  final ChatRole role;
  final String text;
  final DateTime at;

  /// Recipe IDs the answer was grounded in, so the UI can offer taps
  /// through to the actual recipes the assistant referred to.
  final List<String> citedRecipeIds;

  const ChatMessage({
    required this.role,
    required this.text,
    required this.at,
    this.citedRecipeIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'text': text,
        'at': at.toIso8601String(),
        'cited': citedRecipeIds,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
        text: json['text'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        citedRecipeIds:
            (json['cited'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}
