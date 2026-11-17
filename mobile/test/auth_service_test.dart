import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loseit/services/auth_service.dart';

void main() {
  group('AuthService', () {
    test('register success parses user data and returns AuthResult.success', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/auth/register');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'anura@test.lk');
        expect(body['name'], 'Anura Kumara');
        return http.Response(
          jsonEncode({
            'status': 'success',
            'message': 'Account created successfully',
            'user_id': 'user_456',
            'name': 'Anura Kumara',
            'email': 'anura@test.lk',
            'is_onboarded': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final auth = AuthService(client: client);
      final result = await auth.register(
        name: 'Anura Kumara',
        email: 'anura@test.lk',
        password: 'password123',
      );

      expect(result.success, isTrue);
      expect(result.userId, 'user_456');
      expect(result.name, 'Anura Kumara');
      expect(result.email, 'anura@test.lk');
      expect(result.isOnboarded, isFalse);
    });

    test('register with duplicate email returns AuthResult.failure with message', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'detail': 'An account with this email address already exists.',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final auth = AuthService(client: client);
      final result = await auth.register(
        name: 'Anura',
        email: 'existing@test.lk',
        password: 'password123',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('already exists'));
    });

    test('login with valid credentials returns user profile and onboarded status', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/auth/login');
        return http.Response(
          jsonEncode({
            'status': 'success',
            'message': 'Logged in successfully',
            'user_id': 'user_789',
            'name': 'Dilani',
            'email': 'dilani@test.lk',
            'is_onboarded': true,
            'profile': {
              'name': 'Dilani',
              'email': 'dilani@test.lk',
              'age': 30,
              'gender': 'Female',
              'height_cm': 160.0,
              'weight_kg': 65.0,
              'target_weight_kg': 58.0,
              'activity_level': 'Light',
              'dietary_pref': 'Vegetarian',
              'spice_pref': 'Medium',
              'allergies': 'Peanuts',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final auth = AuthService(client: client);
      final result = await auth.login(
        email: 'dilani@test.lk',
        password: 'password123',
      );

      expect(result.success, isTrue);
      expect(result.userId, 'user_789');
      expect(result.isOnboarded, isTrue);
      expect(result.profile, isNotNull);
      expect(result.profile!.dietaryPref, 'Vegetarian');
      expect(result.profile!.allergies, 'Peanuts');
    });

    test('login with invalid password returns failure message', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'detail': 'Invalid email or password.'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final auth = AuthService(client: client);
      final result = await auth.login(
        email: 'dilani@test.lk',
        password: 'wrongpassword',
      );

      expect(result.success, isFalse);
      expect(result.message, 'Invalid email or password.');
    });

    test('offline connection failure returns isOffline: true', () async {
      final client = MockClient((req) async {
        throw http.ClientException('Connection refused');
      });

      final auth = AuthService(client: client);
      final result = await auth.login(
        email: 'test@test.lk',
        password: 'password123',
      );

      expect(result.success, isFalse);
      expect(result.isOffline, isTrue);
    });
  });
}
