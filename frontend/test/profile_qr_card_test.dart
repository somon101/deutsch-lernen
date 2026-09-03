import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/core/auth/user.dart';
import 'package:deutsch_lernen/features/profile/data/profile_gamification_repository.dart';
import 'package:deutsch_lernen/features/profile/presentation/widgets/profile_qr_card.dart';
import 'package:deutsch_lernen/l10n/app_localizations.dart';

const _overview = ProfileGamificationOverview(
  social: SocialStats(followers: 1240, mutual: 42, following: 67),
  streakDays: 47,
  studyMinutes: 24 * 60 + 30,
  level: LevelProgress(code: 'B2', name: 'Upper-Intermediate', percent: 68, hint: '', score: 4.2),
  achievements: [],
  rank: RankInfo(place: 348, topPercent: 12, periodLabel: 'По неделе', totalStudents: 8452),
  weeklyActivity: WeeklyActivity(days: [true, true, true, true, true, true, null], avgHoursPerDay: 4.2, trendPercent: 12),
  learningLanguage: 'английский',
);

AppUser _userWithName(String firstName, String lastName) => AppUser(
      id: 'uuid-should-never-render',
      publicId: '004213087',
      firstName: firstName,
      lastName: lastName,
      email: 'a@b.com',
      username: 'mansur',
      role: UserRole.user,
      status: UserStatus.active,
      avatarUrl: null,
      bio: null,
      birthDate: null,
      canEditProfile: true,
      lastLoginAt: null,
      lastActiveAt: null,
    );

Future<void> _pumpCard(WidgetTester tester, {required AppUser user, double width = 360}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileQrCard(repaintKey: GlobalKey(), user: user, avatarUrl: null, overview: _overview),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders at 360px width with no overflow, no photo', (tester) async {
    await _pumpCard(tester, user: _userWithName('Иван', 'Иванов'));

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.person), findsOneWidget); // silhouette placeholder
    expect(find.textContaining('uuid-should-never-render'), findsNothing);
    expect(find.text('004213087'), findsOneWidget); // public ID shown, not the UUID
  });

  testWidgets('renders a 25+ character name at 360px width with no overflow', (tester) async {
    await _pumpCard(tester, user: _userWithName('Александра', 'Константинопольская'));

    expect(tester.takeException(), isNull);
  });
}
