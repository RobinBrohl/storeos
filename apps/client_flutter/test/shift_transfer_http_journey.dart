import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/shift_transfer_controller.dart';
import 'package:storeos_client/src/application/shift_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';

void main() {
  test(
    'P4.11 real source, consent, approval restart retry and exact Guided Work',
    () async {
      final env = Platform.environment,
          base = Uri.parse(env['STOREOS_TRANSFER_URL']!),
          client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client);
      final sessions = <SessionController>[],
          platforms = <PlatformController>[],
          transfers = <ShiftTransferController>[];
      Future<ShiftTransferController> actor(
        String name, {
        bool self = true,
      }) async {
        final s = SessionController(
              HttpStoreApi(baseUri: base, client: client),
            ),
            p = PlatformController(s, api),
            c = ShiftTransferController(s, p, api, self: self);
        sessions.add(s);
        platforms.add(p);
        transfers.add(c);
        final ready = Completer<void>();
        void changed() {
          if (p.organization != null && !p.isBusy && !ready.isCompleted) {
            ready.complete();
          }
        }

        p.addListener(changed);
        await s.signIn(
          username: name,
          password: 'stock-test-only-password-strong',
        );
        changed();
        await ready.future.timeout(const Duration(seconds: 10));
        p.removeListener(changed);
        return c;
      }

      addTearDown(() {
        for (final c in transfers) {
          c.dispose();
        }
        for (final p in platforms) {
          p.dispose();
        }
        for (final s in sessions) {
          s.dispose();
        }
        client.close();
      });
      final source = await actor('guided_worker'),
          recipient = await actor('transfer_recipient'),
          manager = await actor('test_admin', self: false),
          shift = env['STOREOS_TRANSFER_SHIFT']!;
      final detail = await source.session.authorized(
        (token) => api.get(token, '/employee-home/shifts/$shift'),
      );
      await source.chooseSource(
        ShiftDto.fromJson(Map<String, dynamic>.from(detail['shift'] as Map)),
      );
      source.chooseRecipient(
        source.recipients.singleWhere(
          (r) => r['employeeId'] == env['STOREOS_TRANSFER_RECIPIENT'],
        ),
      );
      expect(await source.propose(), TransferOutcome.confirmed);
      final id = source.detail!.id;
      await recipient.select(id);
      expect(
        recipient.detail!.json['tasks'][0]['knowledgeGuidance'],
        isNotNull,
      );
      expect(
        recipient.detail!.json['tasks'][0]['planogramGuidance'],
        isNotNull,
      );
      expect(await recipient.act('accept'), TransferOutcome.confirmed);
      await manager.select(id);
      expect(await manager.act('approve'), TransferOutcome.uncertain);
      final pending = manager.pending!;
      expect(await manager.retry(), TransferOutcome.confirmed);
      expect(manager.lastConfirmed!['replayed'], true);
      expect(manager.pending, isNull);
      expect(pending.body['expectedVersion'], 2);
      final b = manager.detail!.json['replacementShiftId'] as String,
          work = ShiftController(
            recipient.session,
            recipient.platform,
            api,
            self: true,
          );
      addTearDown(work.dispose);
      await work.open(b);
      await work.openTask(work.tasks.single.id);
      final begins = work.selected!.draft.startsAt;
      while (DateTime.now().toUtc().isBefore(begins)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await work.executeTask('start');
      expect(work.execution!.status, 'in_progress');
      await work.executeTask('confirm');
      work.setNumber('3');
      await work.executeTask('record-number');
      await work.executeTask('complete');
      expect(work.execution!.status, 'completed');
      await source.select(id);
      expect(source.detail!.json, isNot(contains('results')));
    },
  );
}
