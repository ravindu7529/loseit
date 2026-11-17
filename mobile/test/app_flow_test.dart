import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loseit/main.dart';
import 'package:loseit/models/recipe.dart';
import 'package:loseit/services/auth_service.dart';
import 'package:loseit/services/recipe_service.dart';
import 'package:loseit/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real app through the whole journey a user takes:
/// login -> profile setup -> dashboard -> log a meal -> recipes ->
/// assistant -> profile. The backend is stubbed as unreachable, so this
/// also proves the offline fallback keeps every screen working.
///
/// Note: `testWidgets` runs the body inside a fake-async zone, so any
/// real I/O (loading the bundled recipes.json) must go through
/// `tester.runAsync`, otherwise the future never completes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A client that handles auth and stubs recommender as offline.
  http.Client offlineClient() => MockClient((req) async {
        if (req.url.path.endsWith('/auth/login') ||
            req.url.path.endsWith('/auth/register')) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': 'Logged in',
              'user_id': 'user_123',
              'name': 'Kasun',
              'email': 'kasun@test.lk',
              'is_onboarded': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('unavailable', 503);
      });

  Future<AppState> newState(WidgetTester tester) async {
    late AppState state;
    await tester.runAsync(() async {
      final client = offlineClient();
      state = AppState(
        recipeService: RecipeService(client: client),
        authService: AuthService(client: client),
      );
      await state.bootstrap();
      // bootstrap() kicks off the first recommendation fetch without
      // awaiting it. Drain it here so the dashboard is not sitting on a
      // CircularProgressIndicator, which never lets pumpAndSettle finish.
      if (state.isOnboarded) await state.refreshRecommendations();
    });
    return state;
  }

  Future<AppState> pumpApp(WidgetTester tester) async {
    final state = await newState(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const LoseItApp()),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('loads the bundled 300-recipe dataset', (tester) async {
    final state = await newState(tester);
    expect(state.allRecipes.length, 300);
    expect(state.allRecipes.every((r) => r.id.isNotEmpty), isTrue);
    expect(state.allRecipes.every((r) => r.calories > 0), isTrue);
    // All four dietary tags are represented.
    final tags = state.allRecipes.map((r) => r.dietaryTag).toSet();
    expect(tags, containsAll(['Vegan', 'Vegetarian', 'Non-Vegetarian']));
  });

  testWidgets('cold start lands on the login screen', (tester) async {
    await pumpApp(tester);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('login validates before letting the user through',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'kasun@test.lk');
    await tester.enterText(find.byType(TextFormField).last, 'hunter22');
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Tell us about yourself'), findsOneWidget);
  });

  testWidgets('guest -> setup -> dashboard -> log meal -> tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = await pumpApp(tester);

    // --- Guest sign-in ---------------------------------------------
    await tester.tap(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    expect(find.text('Tell us about yourself'), findsOneWidget);

    // --- Fill the multi-step profile form -------------------------
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '29'); // age
    await tester.enterText(fields.at(1), '178'); // height
    await tester.enterText(fields.at(2), '92'); // weight
    await tester.enterText(fields.at(3), '80'); // target
    await tester.testTextInput.receiveAction(TextInputAction.done);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // Step 1 -> Step 2
    await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
    await tester.pumpAndSettle();

    // Step 2: Dietary & Spice
    await tester.tap(find.byKey(const ValueKey('diet_Vegetarian')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spice_Hot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wizard_next_button')));
    await tester.pumpAndSettle();

    // Step 3: Allergies & Avoidances -> Calculate My Plan
    await tester.tap(find.text('Calculate My Plan'));
    await tester.pumpAndSettle();

    // --- Profile stored and plan computed --------------------------
    expect(state.isOnboarded, isTrue);
    expect(state.profile.age, 29);
    expect(state.profile.dietaryPref, 'Vegetarian');
    expect(state.profile.weightKg, 92);
    expect(state.profile.dailyCalorieTarget, greaterThan(1500));

    // --- Dashboard rendered ----------------------------------------
    expect(find.textContaining('Ayubowan'), findsWidgets);
    expect(find.text('CALORIES REMAINING'), findsOneWidget);
    expect(find.text('Weight Progress'), findsOneWidget);

    // Backend is stubbed as down, so the fallback must have produced
    // a list and the UI must say it is offline.
    expect(state.recommendations, isNotEmpty);
    expect(state.scoreSource, ScoreSource.localFallback);

    // --- Hard dietary filter holds across the ranked list ----------
    for (final s in state.recommendations) {
      expect(
        state.profile.allowsDiet(s.recipe.dietaryTag),
        isTrue,
        reason: '${s.recipe.name} (${s.recipe.dietaryTag}) leaked past the '
            'vegetarian filter',
      );
    }

    // --- Log the featured meal -------------------------------------
    expect(state.caloriesConsumedToday, 0);
    final logMeal = find.byTooltip('Log this meal');
    final dashList = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(logMeal, 150, scrollable: dashList);
    // Scroll a little further: freshly-revealed content sits at the
    // bottom edge, where the FAB would swallow the tap.
    await tester.drag(dashList, const Offset(0, -220));
    await tester.pumpAndSettle();

    await tester.tap(logMeal);
    await tester.pumpAndSettle();

    expect(state.todaysMeals.length, 1);
    expect(state.caloriesConsumedToday, greaterThan(0));
    expect(
      state.caloriesRemainingToday,
      state.profile.dailyCalorieTarget.round() - state.caloriesConsumedToday,
    );

    // --- Recipes tab -----------------------------------------------
    await tester.tap(find.byIcon(Icons.restaurant_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Personalised nutrition paths tailored for you'), findsOneWidget);

    // Search spans the whole eligible dataset, not just the ranked
    // shortlist, so a known dish is always findable.
    await tester.enterText(find.byType(TextField).first, 'brinjal');
    await tester.pumpAndSettle();
    expect(find.textContaining('Brinjal'), findsWidgets);

    // --- Assistant tab ---------------------------------------------
    await tester.tap(find.byIcon(Icons.smart_toy_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Spice & Scale Assistant'), findsOneWidget);
    expect(find.textContaining('Kohomada'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'how many calories should i eat',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(state.chat.length, 2);
    expect(
      state.chat.last.text,
      contains('${state.profile.dailyCalorieTarget.round()}'),
    );

    // --- Profile tab -----------------------------------------------
    await tester.tap(find.byIcon(Icons.person_outline_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('YOUR TARGETS'), findsOneWidget);
    expect(find.text('Daily calorie target'), findsOneWidget);
  });

  testWidgets('state persists across a restart', (tester) async {
    final first = await newState(tester);
    await tester.runAsync(() async {
      await first.continueAsGuest();
      await first.saveProfile(
        first.profile.copyWith(age: 41, dietaryPref: 'Vegan', weightKg: 77),
        completeOnboarding: true,
      );
      await first.logWeight(76.4);
    });

    // A fresh AppState reading the same storage.
    final second = await newState(tester);

    expect(second.isSignedIn, isTrue);
    expect(second.isOnboarded, isTrue);
    expect(second.profile.age, 41);
    expect(second.profile.dietaryPref, 'Vegan');
    expect(second.latestWeight, 76.4);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: second, child: const LoseItApp()),
    );
    await tester.pumpAndSettle();

    // Goes straight to the dashboard, skipping login and setup.
    expect(find.textContaining('Ayubowan'), findsWidgets);
  });

  testWidgets('weigh-in lowers the calorie target', (tester) async {
    final state = await newState(tester);
    await tester.runAsync(() async {
      await state.continueAsGuest();
      await state.saveProfile(
        state.profile.copyWith(weightKg: 95),
        completeOnboarding: true,
      );
    });

    final targetBefore = state.profile.dailyCalorieTarget;
    await tester.runAsync(() => state.logWeight(90));
    final targetAfter = state.profile.dailyCalorieTarget;

    // Losing weight lowers BMR, so the target drops with it.
    expect(targetAfter, lessThan(targetBefore));
    expect(state.latestWeight, 90);
    expect(state.totalWeightChange, closeTo(-5, 0.001));
  });

  testWidgets('reset clears everything', (tester) async {
    final state = await newState(tester);
    await tester.runAsync(() async {
      await state.continueAsGuest();
      await state.saveProfile(state.profile, completeOnboarding: true);
      await state.toggleFavourite(state.allRecipes.first.id);
      await state.logMeal(state.allRecipes.first);
    });

    expect(state.favourites, isNotEmpty);
    expect(state.meals, isNotEmpty);

    await tester.runAsync(state.resetAllData);

    expect(state.favourites, isEmpty);
    expect(state.meals, isEmpty);
    expect(state.weightEntries, isEmpty);
    expect(state.isOnboarded, isFalse);
    expect(state.isSignedIn, isFalse);
  });
}
