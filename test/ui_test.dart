import 'package:famgpslink/family_controller.dart';
import 'package:famgpslink/main.dart';
import 'package:famgpslink/models.dart';
import 'package:famgpslink/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class TestAuth extends Fake implements FirebaseAuth {}

class TestDatabase extends Fake implements FirebaseDatabase {}

void main() {
  testWidgets(
    'first sign-in failure reports its cause and retry opens onboarding',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        FamilyStartup(
          open: () async {
            attempts++;
            if (attempts == 1) {
              throw FirebaseAuthException(
                code: 'network-request-failed',
                message: 'private diagnostic payload',
              );
            }
            return FamilyController(auth: TestAuth(), database: TestDatabase())
              ..loading = false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('could not reach sign-in'), findsOneWidget);
      expect(find.textContaining('network-request-failed'), findsOneWidget);
      expect(find.textContaining('not connected'), findsNothing);
      expect(find.textContaining('private diagnostic payload'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Join my family'), findsOneWidget);
      expect(find.textContaining('Error code:'), findsNothing);
    },
  );

  testWidgets(
    'secure storage failure offers retry without declaring a missing build config',
    (tester) async {
      await tester.pumpWidget(
        FamilyStartup(
          open: () async {
            throw PlatformException(
              code: 'read',
              message: 'private storage details',
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('saved profile'), findsOneWidget);
      expect(find.text('Error code: read'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('not connected'), findsNothing);
      expect(find.textContaining('private storage details'), findsNothing);
    },
  );

  testWidgets(
    'disabled anonymous sign-in explains settings instead of a bad APK',
    (tester) async {
      await tester.pumpWidget(
        FamilyStartup(
          open: () async {
            throw FirebaseAuthException(code: 'operation-not-allowed');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('check sign-in settings'), findsOneWidget);
      expect(find.textContaining('operation-not-allowed'), findsOneWidget);
      expect(find.textContaining('not connected'), findsNothing);
    },
  );
  testWidgets(
    'unconfigured build explains that a configured family build is needed',
    (tester) async {
      await tester.pumpWidget(const FamGpsApp());
      expect(find.text('Your family, connected'), findsOneWidget);
      expect(find.textContaining('not connected'), findsOneWidget);
    },
  );
  testWidgets('shared manual pin has no mode label or invented precision', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 11, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedMemberTile(
            member: const Member('owner', 'Adi', 'uid'),
            now: now,
            location: SharedLocation(
              latitude: 1,
              longitude: 2,
              measuredAt: now
                  .subtract(const Duration(minutes: 20))
                  .millisecondsSinceEpoch,
              publishedAt: now.millisecondsSinceEpoch,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Adi'), findsOneWidget);
    expect(find.text('20 min ago · Stale'), findsOneWidget);
    expect(find.textContaining('Manual'), findsNothing);
    expect(find.textContaining('±'), findsNothing);
  });
}
