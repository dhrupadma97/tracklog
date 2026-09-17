import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tracklog/presentation/session_history_screen/widgets/hero_metric_widget.dart';
import 'package:tracklog/presentation/session_history_screen/widgets/monthly_summary_card_widget.dart';
import 'package:tracklog/presentation/session_history_screen/widgets/session_chart_widget.dart';
import 'package:tracklog/services/pin_lock_service.dart';
import 'package:tracklog/widgets/pin_pad.dart';

/// Widget tests for the parts of the UI that were carrying real bugs.
///
/// This file used to be the untouched Flutter counter template, testing a
/// button this app has never had. It could not even compile, because
/// main.dart reached universal_html's stubbed Range through email_draft.dart,
/// so the app shipped for months with zero widget coverage and nobody saw it:
/// the failure looked like a known build quirk.
void main() {
  setUpAll(() {
    // Otherwise every pump tries to fetch a font over the network.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('SessionChartWidget never invents data', () {
    testWidgets('an empty period says so instead of drawing a curve',
        (tester) async {
      await tester.pumpWidget(wrap(SessionChartWidget(
        sessions: const [],
        selectedPeriod: 0,
        onPeriodChanged: (_) {},
        periodLabels: const ['May 2026'],
      )));
      await tester.pump();

      expect(find.text('No sessions in this period'), findsOneWidget);
      // The old fallback curve peaked at 6.0 hrs on day 15 for an empty month.
      expect(find.textContaining('Peak:'), findsNothing);
    });

    testWidgets('real sessions produce a real peak', (tester) async {
      await tester.pumpWidget(wrap(SessionChartWidget(
        sessions: const [
          {'startTime': '2026-05-19T15:00:00.000', 'durationMinutes': 60},
          {'startTime': '2026-05-20T15:00:00.000', 'durationMinutes': 30},
        ],
        selectedPeriod: 0,
        onPeriodChanged: (_) {},
        periodLabels: const ['May 2026'],
      )));
      await tester.pump();

      expect(find.textContaining('Peak: 1.0 hrs on Day 19'), findsOneWidget);
      expect(find.text('No sessions in this period'), findsNothing);
    });
  });

  group('period tabs', () {
    testWidgets('one tab per month, named, not "This Month"', (tester) async {
      await tester.pumpWidget(wrap(SessionChartWidget(
        sessions: const [],
        selectedPeriod: 0,
        onPeriodChanged: (_) {},
        periodLabels: const ['May 2026', 'Apr 2026', 'Mar 2026'],
      )));
      await tester.pump();

      expect(find.text('May 2026'), findsOneWidget);
      expect(find.text('Apr 2026'), findsOneWidget);
      expect(find.text('Mar 2026'), findsOneWidget);
      // A closed programme must never be told it is running now.
      expect(find.text('This Month'), findsNothing);
    });

    testWidgets('tapping a tab reports the index', (tester) async {
      var picked = -1;
      await tester.pumpWidget(wrap(SessionChartWidget(
        sessions: const [],
        selectedPeriod: 0,
        onPeriodChanged: (p) => picked = p,
        periodLabels: const ['May 2026', 'Apr 2026'],
      )));
      await tester.pump();

      await tester.tap(find.text('Apr 2026'));
      expect(picked, 1);
    });
  });

  group('the month on screen is the month being shown', () {
    testWidgets('the summary card names the month it was given',
        (tester) async {
      await tester.pumpWidget(wrap(MonthlySummaryCardWidget(
        totalCost: 173500,
        totalHours: 8,
        sessionCount: 7,
        avgDurationMinutes: 40,
        month: DateTime(2026, 5),
      )));
      await tester.pump();

      // It used to work this out from DateTime.now(), so it printed
      // "September 2026" over May's figures.
      expect(find.textContaining('May 2026'), findsOneWidget);
    });

    testWidgets('the hero line names the period when it is not this month',
        (tester) async {
      await tester.pumpWidget(wrap(const HeroMetricWidget(
        totalHours: 8,
        totalCost: 173500,
        sessionCount: 7,
        periodLabel: 'May 2026',
      )));
      await tester.pump();

      expect(find.text('Total track usage in May 2026'), findsOneWidget);
      expect(find.text('Total track usage this month'), findsNothing);
    });

    testWidgets('without a label it keeps the natural wording', (tester) async {
      await tester.pumpWidget(wrap(const HeroMetricWidget(
        totalHours: 3,
        totalCost: 63000,
        sessionCount: 2,
      )));
      await tester.pump();

      expect(find.text('Total track usage this month'), findsOneWidget);
    });
  });

  group('PinPad', () {
    testWidgets('reports the digits once the length is reached',
        (tester) async {
      String? got;
      await tester.pumpWidget(wrap(PinPad(
        title: 'Enter your PIN',
        onComplete: (pin) async {
          got = pin;
          return null;
        },
      )));
      await tester.pump();

      for (final d in ['8', '9', '6', '1']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(got, '8961');
    });

    testWidgets('does not fire before the length is reached', (tester) async {
      var fired = false;
      await tester.pumpWidget(wrap(PinPad(
        title: 'Enter your PIN',
        onComplete: (_) async {
          fired = true;
          return null;
        },
      )));
      await tester.pump();

      for (final d in ['1', '2', '3']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      expect(fired, isFalse);
    });

    testWidgets('a rejected PIN shows the reason', (tester) async {
      await tester.pumpWidget(wrap(PinPad(
        title: 'Enter your PIN',
        onComplete: (_) async => 'Wrong PIN. 4 attempts left.',
      )));
      await tester.pump();

      for (final d in ['1', '1', '1', '1']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('Wrong PIN. 4 attempts left.'), findsOneWidget);
    });

    testWidgets('the escape route is offered when given', (tester) async {
      var escaped = false;
      await tester.pumpWidget(wrap(PinPad(
        title: 'Enter your PIN',
        onComplete: (_) async => null,
        escapeLabel: 'Use email and password',
        onEscape: () => escaped = true,
      )));
      await tester.pump();

      await tester.tap(find.text('Use email and password'));
      expect(escaped, isTrue);
    });

    test('the PIN is four digits', () {
      expect(PinLockService.pinLength, 4);
    });
  });
}
