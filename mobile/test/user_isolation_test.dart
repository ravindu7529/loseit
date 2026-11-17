import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loseit/models/recipe.dart';
import 'package:loseit/services/auth_service.dart';
import 'package:loseit/services/recipe_service.dart';
import 'package:loseit/services/storage_service.dart';
import 'package:loseit/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Mock client supporting multi-user registration, login, and sync.
  http.Client createMockAuthClient() {
    final Map<String, Map<String, dynamic>> usersByEmail = {};
    final Map<String, List<Map<String, dynamic>>> mealsByUserId = {};
    final Map<String, List<Map<String, dynamic>>> weightsByUserId = {};
    final Map<String, List<String>> favsByUserId = {};

    return MockClient((req) async {
      final path = req.url.path;

      // Register
      if (path.endsWith('/auth/register')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final email = (body['email'] as String).toLowerCase();
        final userId = 'user_${email.replaceAll('@', '_').replaceAll('.', '_')}';
        final userDoc = {
          'user_id': userId,
          'name': body['name'],
          'email': email,
          'is_onboarded': false,
        };
        usersByEmail[email] = userDoc;
        mealsByUserId[userId] = [];
        weightsByUserId[userId] = [];
        favsByUserId[userId] = [];

        return http.Response(
          jsonEncode({
            'status': 'success',
            'message': 'Account created',
            ...userDoc,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // Login
      if (path.endsWith('/auth/login')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final email = (body['email'] as String).toLowerCase();
        final user = usersByEmail[email];
        if (user != null) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': 'Logged in',
              ...user,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'detail': 'Invalid email or password'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      }

      // User sync endpoint
      if (path.contains('/users/') && path.endsWith('/sync')) {
        final segments = path.split('/');
        final userId = segments[segments.indexOf('users') + 1];
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user_id': userId,
              'meal_logs': mealsByUserId[userId] ?? [],
              'weight_logs': weightsByUserId[userId] ?? [],
              'favorites': favsByUserId[userId] ?? [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      // Post meal log
      if (path.contains('/users/') && path.endsWith('/logs') && req.method == 'POST') {
        final segments = path.split('/');
        final userId = segments[segments.indexOf('users') + 1];
        final meal = jsonDecode(req.body) as Map<String, dynamic>;
        mealsByUserId.putIfAbsent(userId, () => []).add(meal);
        return http.Response(
          jsonEncode({'status': 'success', 'log': meal}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not found', 404);
    });
  }

  final sampleRecipe1 = const Recipe(
    id: 'REC_001',
    name: 'Pol Sambol',
    calories: 140,
    protein: 3.0,
    carbs: 8.0,
    fat: 11.0,
    fiber: 4.0,
    prepTimeMin: 10,
    cookTimeMin: 0,
    servings: 4,
    dietaryTag: 'Vegan',
    spiceLevel: 'Hot',
    foodGroup: 'Vegetable',
    mealType: 'Breakfast',
    category: 'Sambol',
    mainIngredient: 'Fresh Grated Coconut',
    keyIngredients: 'Red onion, chili, lime, salt',
    description: 'Zesty coconut chili relish',
  );

  final sampleRecipe2 = const Recipe(
    id: 'REC_002',
    name: 'Sri Lankan Chicken Curry',
    calories: 280,
    protein: 26.0,
    carbs: 6.0,
    fat: 16.0,
    fiber: 1.0,
    prepTimeMin: 15,
    cookTimeMin: 25,
    servings: 4,
    dietaryTag: 'Non-Vegetarian',
    spiceLevel: 'Medium',
    foodGroup: 'Poultry',
    mealType: 'Lunch',
    category: 'Curry',
    mainIngredient: 'Chicken Breast',
    keyIngredients: 'Roasted curry powder, coconut milk, curry leaves',
    description: 'Classic aromatic roasted curry',
  );

  test('Multi-user data isolation: User 1 and User 2 meals do not leak across sessions', () async {
    final client = createMockAuthClient();
    final storage = StorageService();
    final state = AppState(
      recipeService: RecipeService(client: client),
      authService: AuthService(client: client),
      storage: storage,
    );

    await state.bootstrap();
    expect(state.isSignedIn, isFalse);

    // 1. User 1 registers (ravindu@gmail.com)
    final u1Reg = await state.register(
      name: 'Ravindu Perera',
      email: 'ravindu@gmail.com',
      password: 'password123',
    );
    expect(u1Reg.success, isTrue);
    expect(state.userId, contains('ravindu_gmail_com'));
    expect(state.meals.length, 0);
    expect(state.todaysMeals.length, 0);
    expect(state.caloriesConsumedToday, 0);
    expect(state.caloriesRemainingToday, state.profile.dailyCalorieTarget.round());

    // 2. User 1 logs a meal (Pol Sambol) and records weight
    await state.logMeal(sampleRecipe1);
    expect(state.meals.length, 1);
    expect(state.todaysMeals.length, 1);
    expect(state.meals.first.recipeName, 'Pol Sambol');
    expect(state.caloriesConsumedToday, 140);
    expect(state.caloriesRemainingToday, state.profile.dailyCalorieTarget.round() - 140);

    await state.logWeight(78.0);
    expect(state.weightEntries.length, 1);
    expect(state.latestWeight, 78.0);

    // 3. User 1 signs out
    await state.signOut();
    expect(state.isSignedIn, isFalse);
    expect(state.userId, isNull);
    expect(state.meals.length, 0);
    expect(state.todaysMeals.length, 0);
    expect(state.caloriesConsumedToday, 0);
    expect(state.weightEntries.length, 0);

    // 4. User 2 registers (ravindu1@gmail.com)
    final u2Reg = await state.register(
      name: 'Ravindu Second Account',
      email: 'ravindu1@gmail.com',
      password: 'password123',
    );
    expect(u2Reg.success, isTrue);
    expect(state.userId, contains('ravindu1_gmail_com'));

    // Verify User 2 DOES NOT see User 1's meals, consumed calories, or weights!
    expect(state.meals.length, 0, reason: "User 2 should have 0 meals, User 1's meals must not leak!");
    expect(state.todaysMeals.length, 0);
    expect(state.caloriesConsumedToday, 0, reason: "User 2 must start with 0 calories consumed!");
    expect(state.caloriesRemainingToday, state.profile.dailyCalorieTarget.round(), reason: "User 2 should have full calorie budget remaining!");
    expect(state.weightEntries.length, 0);

    // 5. User 2 logs a different meal (Chicken Curry)
    await state.logMeal(sampleRecipe2);
    expect(state.meals.length, 1);
    expect(state.todaysMeals.length, 1);
    expect(state.meals.first.recipeName, 'Sri Lankan Chicken Curry');
    expect(state.caloriesConsumedToday, 280);
    expect(state.caloriesRemainingToday, state.profile.dailyCalorieTarget.round() - 280);

    // 6. User 2 signs out
    await state.signOut();
    expect(state.isSignedIn, isFalse);
    expect(state.meals.length, 0);
    expect(state.todaysMeals.length, 0);
    expect(state.caloriesConsumedToday, 0);

    // 7. User 1 logs back in (ravindu@gmail.com)
    final u1Login = await state.signIn(
      email: 'ravindu@gmail.com',
      password: 'password123',
    );
    expect(u1Login.success, isTrue);

    // Verify User 1's original logged meals and calories are restored!
    expect(state.meals.length, 1, reason: "User 1's original meals must be restored!");
    expect(state.todaysMeals.length, 1);
    expect(state.meals.first.recipeName, 'Pol Sambol');
    expect(state.caloriesConsumedToday, 140, reason: "User 1's consumed calories must reflect their own logged meal!");
    expect(state.caloriesRemainingToday, state.profile.dailyCalorieTarget.round() - 140);
    expect(state.weightEntries.length, 1);
    expect(state.latestWeight, 78.0);

    // 8. Test Guest Session isolation
    await state.signOut();
    await state.continueAsGuest();
    expect(state.isSignedIn, isTrue);
    expect(state.isGuest, isTrue);
    expect(state.userId, 'guest_user');
    expect(state.meals.length, 0, reason: "Guest session should start fresh without registered user data");
    expect(state.todaysMeals.length, 0);
    expect(state.caloriesConsumedToday, 0);
    expect(state.caloriesRemainingToday, state.profile.dailyCalorieTarget.round());
  });
}
