part of 'platform_security_integration_test.dart';

const _adminPassword = 'test-only-password-24-characters';
const _companyKeyPrefix = 'storeos_platform';

String _token(String label) => newUuid().replaceAll('-', '').padRight(43, 'x');

String _password(String label) => '$label-${newUuid()}-test-only';

Future<SessionPrincipal> _selfSession(
  _Fixture f,
  String accountId,
  String token,
) async {
  await f.owner.execute(
    Sql.named(
      'INSERT INTO "${f.schema}".auth_sessions '
      '(account_id, token_hash, expires_at) '
      "VALUES (CAST(@id AS uuid), @hash, clock_timestamp() + interval '2 hours')",
    ),
    parameters: {'id': accountId, 'hash': digestToken(token)},
  );
  final principal = await PostgresAuthStore(
    f.database.pool,
    schemaName: f.schema,
  ).findSession(digestToken(token));
  expect(principal, isNotNull, reason: 'fixture session must resolve');
  return principal!;
}

Future<String> _createAccount(
  _Fixture f,
  PasswordHasher hasher, {
  required String role,
  required String password,
}) async {
  final id = newUuid();
  final username = 'user_${id.replaceAll('-', '').substring(0, 12)}';
  await f.owner.execute(
    Sql.named(
      'INSERT INTO "${f.schema}".accounts '
      '(id, username, username_key, password_hash, company_id, location_id, '
      'role, is_active) '
      'VALUES (CAST(@id AS uuid), @username, @usernameKey, @hash, '
      'CAST(@companyId AS uuid), CAST(@locationId AS uuid), @role, true)',
    ),
    parameters: {
      'id': id,
      'username': username,
      'usernameKey': username.toLowerCase(),
      'hash': await hasher.hash(password),
      'companyId': _company,
      'locationId': _home,
      'role': role,
    },
  );
  return id;
}

Future<Map<String, dynamic>> _accountRow(_Fixture f, String id) async {
  final row = await f.owner.execute(
    'SELECT password_hash, version, is_active FROM "${f.schema}".accounts '
    "WHERE id = '$id'::uuid",
  );
  return row.single.toColumnMap();
}

Future<int> _activeSessionCount(_Fixture f, String id) async {
  final row = await f.owner.execute(
    'SELECT count(*)::int AS count FROM "${f.schema}".auth_sessions '
    "WHERE account_id = '$id'::uuid AND revoked_at IS NULL",
  );
  return row.single.toColumnMap()['count']! as int;
}

Future<List<Map<String, dynamic>>> _passwordAudits(_Fixture f) async {
  final rows = await f.owner.execute(
    'SELECT actor_id::text AS actor_id, entity_id::text AS entity_id, '
    'location_id::text AS location_id, changes FROM "${f.schema}".audit_entries '
    "WHERE action = 'identity.user.password_changed' ORDER BY id",
  );
  return rows.map((row) => row.toColumnMap()).toList();
}

Future<AuthService> _loginService(_Fixture f, PasswordHasher hasher) =>
    AuthService.create(
      store: PostgresAuthStore(f.database.pool, schemaName: f.schema),
      companyId: _company,
      locationId: _home,
      sessionTtl: const Duration(hours: 1),
      passwordHasher: hasher,
    );

void passwordChangeTests() {
  test(
    'self password change updates only the actor and revokes all sessions',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final service = IdentityService(f.database, hasher);
      final principal = await _selfSession(f, f.admin.id, _token('caller'));
      final secondToken = _token('second');
      await _selfSession(f, f.admin.id, secondToken);
      final otherId = await _createAccount(
        f,
        hasher,
        role: 'viewer',
        password: _password('other'),
      );
      final otherBefore = await _accountRow(f, otherId);

      final newPassword = _password('replacement');
      await service.changeOwnPassword(principal, {
        'currentPassword': _adminPassword,
        'newPassword': newPassword,
      });

      final stored = await _accountRow(f, f.admin.id);
      expect(stored['version'], 2);
      expect(stored['password_hash'], isNot(isEmpty));
      expect(
        await hasher.verify(_adminPassword, stored['password_hash']! as String),
        isFalse,
      );
      expect(
        await hasher.verify(newPassword, stored['password_hash']! as String),
        isTrue,
      );
      expect(await _activeSessionCount(f, f.admin.id), 0);

      final otherAfter = await _accountRow(f, otherId);
      expect(otherAfter, otherBefore);

      final audits = await _passwordAudits(f);
      expect(audits, hasLength(1));
      expect(audits.single['actor_id'], f.admin.id);
      expect(audits.single['entity_id'], f.admin.id);
      expect(audits.single['location_id'], _home);
      expect(audits.single['changes'], {'version': 2});
      expect(jsonEncode(audits), isNot(contains(_adminPassword)));
      expect(jsonEncode(audits), isNot(contains(newPassword)));
      expect(jsonEncode(audits), isNot(contains(stored['password_hash'])));

      final auth = await _loginService(f, hasher);
      await expectLater(
        auth.login(
          LoginRequest(username: 'security_admin', password: _adminPassword),
          remoteKey: 'test',
        ),
        throwsA(isA<AuthFailure>()),
      );
      final login = await auth.login(
        LoginRequest(username: 'security_admin', password: newPassword),
        remoteKey: 'test',
      );
      expect(login.user.id, f.admin.id);
    }),
  );

  test(
    'every supported human role without an employee link may change its own password',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final service = IdentityService(f.database, hasher);
      for (final role in ['admin', 'auditor', 'employee', 'viewer']) {
        final currentPassword = role == 'admin'
            ? _adminPassword
            : _password('role-$role');
        final accountId = role == 'admin'
            ? f.admin.id
            : await _createAccount(
                f,
                hasher,
                role: role,
                password: currentPassword,
              );
        final principal = await _selfSession(
          f,
          accountId,
          _token('role-$role'),
        );
        await service.changeOwnPassword(principal, {
          'currentPassword': currentPassword,
          'newPassword': _password('changed-$role'),
        });
        expect(await _activeSessionCount(f, accountId), 0);
      }
      expect(await _passwordAudits(f), hasLength(4));
    }),
  );

  test(
    'wrong current password performs zero state mutation and is limiter-counted',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      var now = DateTime.now().toUtc();
      final limiter = PasswordVerificationLimiter(clock: () => now);
      final service = IdentityService(f.database, hasher, limiter: limiter);
      final principal = await _selfSession(f, f.admin.id, _token('wrong'));
      final before = await _accountRow(f, f.admin.id);

      for (var attempt = 0; attempt < 5; attempt++) {
        await expectLater(
          service.changeOwnPassword(principal, {
            'currentPassword': 'incorrect-current-password',
            'newPassword': _password('never'),
          }),
          throwsA(
            isA<PlatformFailure>().having(
              (error) => error.code,
              'code',
              'invalid_current_password',
            ),
          ),
        );
      }
      expect(limiter.allows(f.admin.id), isFalse);

      // Blocked before verification: even the correct password is refused and
      // the blocked attempt adds no further failure.
      await expectLater(
        service.changeOwnPassword(principal, {
          'currentPassword': _adminPassword,
          'newPassword': _password('blocked'),
        }),
        throwsA(
          isA<PlatformFailure>().having(
            (error) => error.code,
            'code',
            'rate_limited',
          ),
        ),
      );
      expect(await _accountRow(f, f.admin.id), before);
      expect(await _activeSessionCount(f, f.admin.id), 1);
      expect(await _passwordAudits(f), isEmpty);

      // Success after the window clears the bucket.
      now = now.add(const Duration(minutes: 16));
      expect(limiter.allows(f.admin.id), isTrue);
      final newPassword = _password('after-window');
      await service.changeOwnPassword(principal, {
        'currentPassword': _adminPassword,
        'newPassword': newPassword,
      });
      expect(limiter.allows(f.admin.id), isTrue);
      expect(
        await hasher.verify(
          newPassword,
          (await _accountRow(f, f.admin.id))['password_hash']! as String,
        ),
        isTrue,
      );
    }),
  );

  test(
    'password validation follows the shared UTF-8 byte policy before any DB work',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final service = IdentityService(f.database, hasher);
      final principal = await _selfSession(f, f.admin.id, _token('policy'));
      final before = await _accountRow(f, f.admin.id);

      Future<void> rejects(Map<String, dynamic> body) async {
        await expectLater(
          service.changeOwnPassword(principal, body),
          throwsA(
            isA<PlatformFailure>().having(
              (error) => error.code,
              'code',
              'invalid_request',
            ),
          ),
        );
      }

      await rejects({
        'currentPassword': _adminPassword,
        'newPassword': _adminPassword,
      });
      await rejects({
        'currentPassword': _adminPassword,
        'newPassword': 'short',
      });
      await rejects({'currentPassword': '', 'newPassword': _password('x')});
      await rejects({
        'currentPassword': _adminPassword,
        'newPassword': _password('x'),
        'userId': f.admin.id,
      });
      await rejects({'currentPassword': _adminPassword, 'newPassword': 2});
      // 5 two-byte characters are 10 UTF-8 bytes, below the 12-byte minimum.
      await rejects({
        'currentPassword': _adminPassword,
        'newPassword': 'ä' * 5,
      });
      expect(await _accountRow(f, f.admin.id), before);

      // 6 two-byte characters are only 6 code points but exactly 12 bytes and
      // therefore satisfy the byte-based policy.
      final multibyte = 'ä' * 6;
      expect(multibyte.length, 6);
      await service.changeOwnPassword(principal, {
        'currentPassword': _adminPassword,
        'newPassword': multibyte,
      });
      expect(
        await hasher.verify(
          multibyte,
          (await _accountRow(f, f.admin.id))['password_hash']! as String,
        ),
        isTrue,
      );
    }),
  );

  test(
    'disabled accounts and revoked sessions are rejected without mutation',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final service = IdentityService(f.database, hasher);
      final principal = await _selfSession(f, f.admin.id, _token('reject'));

      await f.owner.execute(
        'UPDATE "${f.schema}".accounts SET is_active = false '
        "WHERE id = '${f.admin.id}'::uuid",
      );
      await expectLater(
        service.changeOwnPassword(principal, {
          'currentPassword': _adminPassword,
          'newPassword': _password('disabled'),
        }),
        throwsA(
          isA<PlatformFailure>().having((error) => error.status, 'status', 401),
        ),
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".accounts SET is_active = true '
        "WHERE id = '${f.admin.id}'::uuid",
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".auth_sessions SET revoked_at = now() '
        "WHERE account_id = '${f.admin.id}'::uuid",
      );
      await expectLater(
        service.changeOwnPassword(principal, {
          'currentPassword': _adminPassword,
          'newPassword': _password('revoked'),
        }),
        throwsA(
          isA<PlatformFailure>().having((error) => error.status, 'status', 401),
        ),
      );
      expect(await _passwordAudits(f), isEmpty);
    }),
  );

  test(
    'audit failure after password update and revocation rolls everything back',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final limiter = PasswordVerificationLimiter();
      final service = IdentityService(f.database, hasher, limiter: limiter);
      final principal = await _selfSession(f, f.admin.id, _token('rollback'));
      final original = await _accountRow(f, f.admin.id);
      final newPassword = _password('rollback-new');

      // Four verification failures roll their transactions back but must
      // remain counted in the in-memory limiter.
      for (var attempt = 0; attempt < 4; attempt++) {
        await expectLater(
          service.changeOwnPassword(principal, {
            'currentPassword': 'incorrect-current-password',
            'newPassword': newPassword,
          }),
          throwsA(
            isA<PlatformFailure>().having(
              (error) => error.code,
              'code',
              'invalid_current_password',
            ),
          ),
        );
      }

      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries '
        'FROM "${f.runtimeUser}"',
      );
      try {
        await expectLater(
          service.changeOwnPassword(principal, {
            'currentPassword': _adminPassword,
            'newPassword': newPassword,
          }),
          throwsA(isA<PgException>()),
        );
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries '
          'TO "${f.runtimeUser}"',
        );
      }

      final restored = await _accountRow(f, f.admin.id);
      expect(restored['password_hash'], original['password_hash']);
      expect(restored['version'], original['version']);
      expect(await _activeSessionCount(f, f.admin.id), 1);
      expect(await _passwordAudits(f), isEmpty);
      expect(
        await hasher.verify(
          _adminPassword,
          restored['password_hash']! as String,
        ),
        isTrue,
      );
      expect(
        await hasher.verify(newPassword, restored['password_hash']! as String),
        isFalse,
      );

      // The rolled-back success path must not have cleared the limiter: the
      // fifth wrong attempt is still counted and the sixth is throttled.
      await expectLater(
        service.changeOwnPassword(principal, {
          'currentPassword': 'incorrect-current-password',
          'newPassword': newPassword,
        }),
        throwsA(
          isA<PlatformFailure>().having(
            (error) => error.code,
            'code',
            'invalid_current_password',
          ),
        ),
      );
      expect(limiter.allows(f.admin.id), isFalse);
      await expectLater(
        service.changeOwnPassword(principal, {
          'currentPassword': 'incorrect-current-password',
          'newPassword': newPassword,
        }),
        throwsA(
          isA<PlatformFailure>().having(
            (error) => error.code,
            'code',
            'rate_limited',
          ),
        ),
      );
    }),
  );

  test(
    'admin reset that commits first wins the lock and the self change fails verification',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final service = IdentityService(f.database, hasher);
      final principal = await _selfSession(
        f,
        f.admin.id,
        _token('admin-first'),
      );
      final adminPassword = _password('admin-wins');
      final adminHash = await hasher.hash(adminPassword);
      final key = '$_companyKeyPrefix:${f.schema}:$_company';
      final locked = Completer<void>();
      final release = Completer<void>();
      final blocker = f.owner.runTx((tx) async {
        await tx.execute(
          Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
          parameters: {'key': key},
        );
        locked.complete();
        await release.future;
        await tx.execute(
          Sql.named(
            'UPDATE "${f.schema}".accounts '
            'SET password_hash = @hash, version = version + 1 '
            "WHERE id = '${f.admin.id}'::uuid",
          ),
          parameters: {'hash': adminHash},
        );
      });
      await locked.future;
      final pending = service.changeOwnPassword(principal, {
        'currentPassword': _adminPassword,
        'newPassword': _password('self-loses'),
      });
      try {
        await _waitForCompanyLock(f.database.pool, key);
      } finally {
        release.complete();
        await blocker;
      }
      await expectLater(
        pending,
        throwsA(
          isA<PlatformFailure>().having(
            (error) => error.code,
            'code',
            'invalid_current_password',
          ),
        ),
      );
      final stored = await _accountRow(f, f.admin.id);
      expect(stored['password_hash'], adminHash);
      expect(
        await hasher.verify(adminPassword, stored['password_hash']! as String),
        isTrue,
      );
      expect(await _passwordAudits(f), isEmpty);
    }),
  );

  test(
    'self change that commits first makes a stale admin reset fail without overwrite',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final service = IdentityService(f.database, hasher);
      final principal = await _selfSession(f, f.admin.id, _token('self-first'));
      final selfPassword = _password('self-wins');
      await service.changeOwnPassword(principal, {
        'currentPassword': _adminPassword,
        'newPassword': selfPassword,
      });
      final stored = await _accountRow(f, f.admin.id);
      expect(stored['version'], 2);

      await expectLater(
        service.setPassword(f.admin, f.admin.id, {
          'password': _password('stale-admin'),
          'expectedVersion': 1,
        }),
        throwsA(
          isA<PlatformFailure>().having(
            (error) => error.code,
            'code',
            'version_conflict',
          ),
        ),
      );
      final after = await _accountRow(f, f.admin.id);
      expect(after['password_hash'], stored['password_hash']);
      expect(
        await hasher.verify(selfPassword, after['password_hash']! as String),
        isTrue,
      );
    }),
  );

  test(
    'two self sessions race: exactly one commits and all sessions are revoked',
    () => _withPlatform((f) async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final service = IdentityService(f.database, hasher);
      final first = await _selfSession(f, f.admin.id, _token('race-one'));
      final second = await _selfSession(f, f.admin.id, _token('race-two'));
      final firstPassword = _password('race-one-new');
      final secondPassword = _password('race-two-new');

      Future<Object?> attempt(
        SessionPrincipal principal,
        String newPassword,
      ) async {
        try {
          await service.changeOwnPassword(principal, {
            'currentPassword': _adminPassword,
            'newPassword': newPassword,
          });
          return null;
        } on Object catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        attempt(first, firstPassword),
        attempt(second, secondPassword),
      ]);
      final failures = results.whereType<PlatformFailure>().toList();
      expect(results.where((result) => result == null), hasLength(1));
      expect(failures, hasLength(1));
      expect(failures.single.status, 401);
      expect(await _activeSessionCount(f, f.admin.id), 0);
      expect(await _passwordAudits(f), hasLength(1));
      final stored =
          (await _accountRow(f, f.admin.id))['password_hash']! as String;
      final firstWon = await hasher.verify(firstPassword, stored);
      final secondWon = await hasher.verify(secondPassword, stored);
      expect(firstWon ^ secondWon, isTrue);
    }),
  );
}
