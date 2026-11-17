import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tracking.dart';
import '../models/user_profile.dart';

/// Structured response result from authentication requests.
@immutable
class AuthResult {
  final bool success;
  final String message;
  final String? userId;
  final String? name;
  final String? email;
  final bool isOnboarded;
  final UserProfile? profile;
  final bool isOffline;

  const AuthResult({
    required this.success,
    required this.message,
    this.userId,
    this.name,
    this.email,
    this.isOnboarded = false,
    this.profile,
    this.isOffline = false,
  });

  factory AuthResult.failure(String message, {bool isOffline = false}) =>
      AuthResult(
        success: false,
        message: message,
        isOffline: isOffline,
      );

  factory AuthResult.success({
    required String message,
    required String userId,
    required String name,
    required String email,
    bool isOnboarded = false,
    UserProfile? profile,
  }) =>
      AuthResult(
        success: true,
        message: message,
        userId: userId,
        name: name,
        email: email,
        isOnboarded: isOnboarded,
        profile: profile,
      );
}

/// Authentication service that talks to the FastAPI MongoDB backend.
class AuthService {
  AuthService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? defaultBaseUrl;

  final http.Client _client;
  String _baseUrl;

  static String get defaultBaseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static const Duration _timeout = Duration(seconds: 8);

  String get baseUrl => _baseUrl;
  set baseUrl(String value) => _baseUrl = value.trim();

  Future<http.Response> _postWithFallback(String path, String payload) async {
    try {
      return await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}

    final candidateUrls = <String>[];
    if (_baseUrl.contains('10.0.2.2')) {
      candidateUrls.add(_baseUrl.replaceAll('10.0.2.2', '127.0.0.1'));
    } else if (_baseUrl.contains('127.0.0.1') || _baseUrl.contains('localhost')) {
      candidateUrls.add(_baseUrl.replaceAll('127.0.0.1', '10.0.2.2').replaceAll('localhost', '10.0.2.2'));
    }
    if (_baseUrl.contains(':8000')) {
      candidateUrls.add(_baseUrl.replaceAll(':8000', ':8001'));
    }

    for (final altBase in candidateUrls) {
      try {
        final res = await _client
            .post(
              Uri.parse('$altBase$path'),
              headers: {'Content-Type': 'application/json'},
              body: payload,
            )
            .timeout(const Duration(seconds: 4));
        _baseUrl = altBase;
        return res;
      } catch (_) {}
    }
    throw const SocketException('Unable to reach backend server');
  }

  /// Registers a new user account with name, email and password in MongoDB.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final payload = jsonEncode({
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    try {
      final res = await _postWithFallback('/auth/register', payload);

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return AuthResult.failure('Unexpected response from server (${res.statusCode})');
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        UserProfile? profile;
        if (body['profile'] is Map<String, dynamic>) {
          try {
            profile = UserProfile.fromJson(body['profile'] as Map<String, dynamic>);
          } catch (_) {}
        }

        return AuthResult.success(
          message: body['message'] as String? ?? 'Account registered successfully',
          userId: body['user_id'] as String? ?? '',
          name: body['name'] as String? ?? name.trim(),
          email: body['email'] as String? ?? email.trim().toLowerCase(),
          isOnboarded: body['is_onboarded'] as bool? ?? false,
          profile: profile,
        );
      } else {
        final detail = body['detail'] ?? body['message'] ?? 'Registration failed';
        return AuthResult.failure('$detail');
      }
    } on SocketException catch (_) {
      return AuthResult.failure(
        'Cannot connect to backend server at $_baseUrl. Make sure the server is running.',
        isOffline: true,
      );
    } on TimeoutException catch (_) {
      return AuthResult.failure(
        'Connection timed out while connecting to $_baseUrl.',
        isOffline: true,
      );
    } catch (e) {
      return AuthResult.failure('Authentication network error: $e', isOffline: true);
    }
  }

  /// Logs into an existing user account with email and password from MongoDB.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final payload = jsonEncode({
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    try {
      final res = await _postWithFallback('/auth/login', payload);

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return AuthResult.failure('Unexpected response from server (${res.statusCode})');
      }

      if (res.statusCode == 200) {
        UserProfile? profile;
        if (body['profile'] is Map<String, dynamic>) {
          try {
            profile = UserProfile.fromJson(body['profile'] as Map<String, dynamic>);
          } catch (_) {}
        }

        return AuthResult.success(
          message: body['message'] as String? ?? 'Login successful',
          userId: body['user_id'] as String? ?? '',
          name: body['name'] as String? ?? 'Friend',
          email: body['email'] as String? ?? email.trim().toLowerCase(),
          isOnboarded: body['is_onboarded'] as bool? ?? false,
          profile: profile,
        );
      } else {
        final detail = body['detail'] ?? body['message'] ?? 'Invalid email or password';
        return AuthResult.failure('$detail');
      }
    } on SocketException catch (_) {
      return AuthResult.failure(
        'Cannot connect to backend server at $_baseUrl. Make sure the server is running.',
        isOffline: true,
      );
    } on TimeoutException catch (_) {
      return AuthResult.failure(
        'Connection timed out while connecting to $_baseUrl.',
        isOffline: true,
      );
    } catch (e) {
      return AuthResult.failure('Authentication network error: $e', isOffline: true);
    }
  }

  /// Saves or updates the user profile in MongoDB.
  Future<bool> saveUserProfile(String userId, UserProfile profile) async {
    if (userId.isEmpty || userId.startsWith('guest')) return false;
    final uri = Uri.parse('$_baseUrl/users/$userId');
    try {
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(profile.toJson()),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[LoseIt] Could not sync profile to MongoDB: $e');
      return false;
    }
  }

  /// Fetches saved user profile from MongoDB if available.
  Future<UserProfile?> fetchUserProfile(String userId) async {
    if (userId.isEmpty || userId.startsWith('guest')) return null;
    final uri = Uri.parse('$_baseUrl/users/$userId');
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['profile'] is Map<String, dynamic>) {
          return UserProfile.fromJson(body['profile'] as Map<String, dynamic>);
        }
        return UserProfile.fromJson(body);
      }
    } catch (e) {
      debugPrint('[LoseIt] Could not fetch profile from MongoDB: $e');
    }
    return null;
  }

  /// Fetches complete user sync bundle (profile, meals, weights, favorites) in one call.
  Future<Map<String, dynamic>?> fetchUserSyncData(String userId) async {
    if (userId.isEmpty || userId.startsWith('guest')) return null;
    final uri = Uri.parse('$_baseUrl/users/$userId/sync');
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['data'] is Map<String, dynamic>) {
          return body['data'] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('[LoseIt] Could not fetch sync bundle: $e');
    }
    return null;
  }

  /// Fetches user meal logs from backend.
  Future<List<MealLog>> fetchMealLogs(String userId) async {
    if (userId.isEmpty || userId.startsWith('guest')) return [];
    final uri = Uri.parse('$_baseUrl/users/$userId/logs');
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['logs'] as List<dynamic>? ?? [];
        return list
            .map((e) => MealLog.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[LoseIt] Could not fetch meal logs: $e');
    }
    return [];
  }

  /// Saves a meal log to the backend.
  Future<bool> saveMealLog(String userId, MealLog meal) async {
    if (userId.isEmpty || userId.startsWith('guest')) return false;
    final uri = Uri.parse('$_baseUrl/users/$userId/logs');
    try {
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(meal.toJson()),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[LoseIt] Could not save meal log: $e');
      return false;
    }
  }

  /// Deletes a meal log on the backend.
  Future<bool> deleteMealLog(String userId, String mealId) async {
    if (userId.isEmpty || userId.startsWith('guest')) return false;
    final uri = Uri.parse('$_baseUrl/users/$userId/logs/$mealId');
    try {
      final res = await _client.delete(uri).timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[LoseIt] Could not delete meal log: $e');
      return false;
    }
  }

  /// Fetches user weight entries from backend.
  Future<List<WeightEntry>> fetchWeights(String userId) async {
    if (userId.isEmpty || userId.startsWith('guest')) return [];
    final uri = Uri.parse('$_baseUrl/users/$userId/weights');
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['weights'] as List<dynamic>? ?? [];
        return list
            .map((e) => WeightEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[LoseIt] Could not fetch weight logs: $e');
    }
    return [];
  }

  /// Saves a weight entry to the backend.
  Future<bool> saveWeight(String userId, WeightEntry weight) async {
    if (userId.isEmpty || userId.startsWith('guest')) return false;
    final uri = Uri.parse('$_baseUrl/users/$userId/weights');
    try {
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(weight.toJson()),
          )
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[LoseIt] Could not save weight log: $e');
      return false;
    }
  }

  /// Fetches user favorites from backend.
  Future<Set<String>> fetchFavorites(String userId) async {
    if (userId.isEmpty || userId.startsWith('guest')) return {};
    final uri = Uri.parse('$_baseUrl/users/$userId/favorites');
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['favorites'] as List<dynamic>? ?? [];
        return list.map((e) => '$e').toSet();
      }
    } catch (e) {
      debugPrint('[LoseIt] Could not fetch favorites: $e');
    }
    return {};
  }

  /// Toggles favorite recipe on the backend.
  Future<bool> toggleFavorite(String userId, String recipeId) async {
    if (userId.isEmpty || userId.startsWith('guest')) return false;
    final uri = Uri.parse('$_baseUrl/users/$userId/favorites/$recipeId');
    try {
      final res = await _client.post(uri).timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[LoseIt] Could not toggle favorite: $e');
      return false;
    }
  }
}
