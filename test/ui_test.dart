import 'package:famgpslink/family_controller.dart';
import 'package:famgpslink/main.dart';
import 'package:famgpslink/models.dart';
import 'package:famgpslink/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class TestAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;
}

class TestDatabase extends Fake implements FirebaseDatabase {}

class ApprovalController extends FamilyController {
  ApprovalController() : super(auth: TestAuth(), database: TestDatabase()) {
    ownerMemberId = 'owner';
  }
  bool? approvedOwnerOnly;
  @override
  Stream<List<Member>> familyMembers() => Stream.value([]);
  @override
  Stream<List<PairingRequest>> pairingRequests() => Stream.value([
    PairingRequest('partner-uid', {
      'name': 'Partner',
      'code': 'ABCD2345',
      'installationId': 'A' * 32,
    }),
  ]);
  @override
  Future<void> approve(
    PairingRequest pairing, {
    String? recoverMemberId,
    bool ownerOnly = false,
  }) async {
    approvedOwnerOnly = ownerOnly;
  }
}

void main() {
  testWidgets(
    'owner can select private approval before confirming the pairing code',
    (tester) async {
      final controller = ApprovalController();
      await tester.pumpWidget(
        MaterialApp(home: AdminPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Approve or recover profile'));
      await tester.pumpAndSettle();
      expect(find.text('Private connection (only you)'), findsOneWidget);
      expect(controller.approvedOwnerOnly, null);
      await tester.tap(find.byType(SwitchListTile));
      await tester.enterText(find.byType(TextField), 'ABCD2345');
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(controller.approvedOwnerOnly, true);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets(
    'private member sees who can access their location and retains the sharing toggle',
    (tester) async {
      final controller =
          FamilyController(auth: TestAuth(), database: TestDatabase())
            ..self = const Member(
              'partner',
              'Partner',
              'partner-uid',
              ownerOnly: true,
            );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('only the owner can see your profile'),
        findsOneWidget,
      );
      expect(find.text('Share my location'), findsOneWidget);
      expect(find.text('Family administration'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
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
