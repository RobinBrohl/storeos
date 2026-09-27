import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../infrastructure/auth_store.dart';
import 'login_limiter.dart';
import 'password_hasher.dart';

final _usernamePattern = RegExp(r'^[A-Za-z0-9._@-]{3,64}$');
final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

String normalizeUsername(String username) {
  final trimmed = username.trim();
  if (!_usernamePattern.hasMatch(trimmed)) {
    throw const AuthFailure(AuthFailureReason.invalidCredentials);
  }
  return trimmed.toLowerCase();
}

enum AuthFailureReason {
  invalidCredentials,
  tooManyAttempts,
  invalidSession,
  forbidden,
}

class AuthFailure implements Exception {
  const AuthFailure(this.reason);

  final AuthFailureReason reason;
}

class AuthService {
  AuthService({
    required this.store,
    required this.passwordHasher,
    required this.limiter,
    required this.companyId,
    required this.locationId,
    required this.sessionTtl,
    required this.dummyPasswordHash,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static Future<AuthService> create({
    required AuthStore store,
    required String companyId,
    required String locationId,
    required Duration sessionTtl,
    PasswordHasher? passwordHasher,
    LoginLimiter? limiter,
  }) async {
    final hasher = passwordHasher ?? PasswordHasher();
    final random = Random.secure();
    final dummyPassword = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    return AuthService(
      store: store,
      passwordHasher: hasher,
      limiter: limiter ?? LoginLimiter(),
      companyId: companyId,
      locationId: locationId,
      sessionTtl: sessionTtl,
      dummyPasswordHash: await hasher.hash(dummyPassword),
      random: random,
    );
  }

  final AuthStore store;
  final PasswordHasher passwordHasher;
  final LoginLimiter limiter;
  final String companyId;
  final String locationId;
  final Duration sessionTtl;
  final String dummyPasswordHash;
  final DateTime Function() _clock;
  final Random _random;

  Future<SessionResponse> login(
    LoginRequest request, {
    required String remoteKey,
  }) async {
    final usernameKey = normalizeUsername(request.username);
    if (request.password.isEmpty ||
        utf8.encode(request.password).length > 1024) {
      throw const AuthFailure(AuthFailureReason.invalidCredentials);
    }
    if (!limiter.begin(usernameKey, remoteKey)) {
      throw const AuthFailure(AuthFailureReason.tooManyAttempts);
    }
    try {
      final account = await store.findAccount(usernameKey);
      final validPassword = await passwordHasher.verify(
        request.password,
        account?.passwordHash ?? dummyPasswordHash,
      );
      if (account == null ||
          !account.isActive ||
          !validPassword ||
          account.companyId != companyId) {
        limiter.failure(usernameKey, remoteKey);
        throw const AuthFailure(AuthFailureReason.invalidCredentials);
      }
      final token = base64UrlEncode(
        List<int>.generate(32, (_) => _random.nextInt(256)),
      ).replaceAll('=', '');
      final expiresAt = _clock().toUtc().add(sessionTtl);
      try {
        await store.createSession(
          accountId: account.id,
          tokenHash: digestToken(token),
          expiresAt: expiresAt,
          expectedPasswordHash: account.passwordHash,
          expectedCompanyId: companyId,
        );
      } on SessionCreationRejected {
        limiter.failure(usernameKey, remoteKey);
        throw const AuthFailure(AuthFailureReason.invalidCredentials);
      }
      limiter.success(usernameKey);
      return SessionResponse(
        token: token,
        expiresAt: expiresAt,
        user: SessionUser(
          id: account.id,
          username: account.username,
          companyId: account.companyId,
          locationId: account.locationId,
        ),
      );
    } finally {
      limiter.end();
    }
  }

  Future<SessionPrincipal> authenticate(String? token) async {
    if (token == null || !_tokenPattern.hasMatch(token)) {
      throw const AuthFailure(AuthFailureReason.invalidSession);
    }
    final principal = await store.findSession(digestToken(token));
    if (principal == null || principal.companyId != companyId) {
      throw const AuthFailure(AuthFailureReason.invalidSession);
    }
    return principal;
  }

  Future<void> logout(String? token) async {
    await authenticate(token);
    if (!await store.revokeSession(digestToken(token!))) {
      throw const AuthFailure(AuthFailureReason.invalidSession);
    }
  }

  void requireLocation(SessionPrincipal principal, String pathLocationId) {
    if (principal.companyId != companyId ||
        pathLocationId.toLowerCase() != principal.locationId) {
      throw const AuthFailure(AuthFailureReason.forbidden);
    }
  }
}

String digestToken(String token) =>
    sha256.convert(utf8.encode(token)).toString();
