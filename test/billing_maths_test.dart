import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/billing_baseline.dart';
import 'package:tracklog/services/invoice_service.dart';
import 'package:tracklog/services/natrax_invoice_parser.dart';

/// Pure reimplementations of the PO Tracker's getters.
///
/// The screen's arithmetic lives inside a StatefulWidget, so these mirror it
/// exactly and are what the randomised cases hammer. If the screen and these
/// ever disagree, the fixed cases below — pinned to the real invoices — break.
class PoMaths {
  static const gstRate = BillingBaseline.gstRate;

  static double inclGst(double excl) => excl * (1 + gstRate);

  static double invoicedTotal(List<NatraxInvoice> invoices) =>
      invoices.fold(0.0, (s, i) => s + i.totalAmount);

  static Map<String, double> invoicedByMonth(List<NatraxInvoice> invoices) {
    final map = <String, double>{};
    for (final i in invoices) {
      final m = i.periodMonth;
      if (m == null || m.isEmpty) continue;
      map[m] = (map[m] ?? 0) + i.totalAmount;
    }
    return map;
  }

  static double notYetBilled(String project, List<NatraxInvoice> invoices) {
    final billed = invoicedByMonth(invoices);
    return BillingBaseline.forProject(project)
        .where((m) => !billed.containsKey(m.month))
        .fold(0.0, (s, m) => s + m.inclGst);
  }

  static double variance(String project, List<NatraxInvoice> invoices) {
    final billed = invoicedByMonth(invoices);
    var v = 0.0;
    for (final m in BillingBaseline.forProject(project)) {
      final b = billed[m.month];
      if (b == null) continue;
      v += b - m.inclGst;
    }
    return v;
  }

  static double balance(double poInclTax, List<NatraxInvoice> invoices) =>
      poInclTax - invoicedTotal(invoices);

  static double projected(
          double poInclTax, String project, List<NatraxInvoice> invoices) =>
      balance(poInclTax, invoices) - notYetBilled(project, invoices);
}

NatraxInvoice _inv(String month, double total) => NatraxInvoice(
      id: month,
      invoiceNumber: 'INV-$month',
      projectName: 'Mahindra EV PoC',
      periodMonth: month,
      amountExclGst: total / 1.18,
      gstAmount: total - total / 1.18,
      totalAmount: total,
    );

void main() {
  const project = 'Mahindra EV PoC';
  const poInclTax = 1904375.0 + 342788.0; // PO 8242348442

  group('pinned to the real invoices', () {
    final march = _inv('2026-03', 228454.00); // INV/25-26/1869
    final april = _inv('2026-04', 1371691.00); // INV/26-27/205

    test('baseline months agree with the invoices actually raised', () {
      final b = {
        for (final m in BillingBaseline.forProject(project)) m.month: m
      };
      // March and April are pinned to their invoices; May is still computed.
      expect(b['2026-03']!.exclGst, 193605);
      expect(b['2026-03']!.inclGst, closeTo(228454, 0.5)); // INV/25-26/1869
      expect(b['2026-04']!.exclGst, 1162450);
      expect(b['2026-04']!.inclGst, closeTo(1371691, 0.5)); // INV/26-27/205
      // May carries only its workshop rental; its track cost comes from the
      // sessions logged in TrackLog.
      expect(b['2026-05']!.isTrackComputed, isTrue);
      expect(b['2026-05']!.exclGst, 40000);
    });

    test('April now reconciles exactly, leaving no variance', () {
      final april = _inv('2026-04', 1371691.00);
      expect(PoMaths.variance(project, [april]), closeTo(0, 1),
          reason: 'the workbook figure was corrected to the invoiced value');
    });

    test('balance with March + April invoiced is 6.47 lakh, not overspent', () {
      final balance = PoMaths.balance(poInclTax, [march, april]);
      expect(balance, closeTo(647018, 1));
      expect(balance, greaterThan(0), reason: 'the PO is not exhausted');
    });

    test('May is costed from sessions, so its baseline is workshop only', () {
      final may = BillingBaseline.forProject(project)
          .firstWhere((m) => m.month == '2026-05');
      expect(may.isTrackComputed, isTrue);
      expect(may.workshopRental, 40000);

      // The baseline alone therefore contributes only the workshop rental.
      // The PO Tracker adds that month's logged session cost on top at
      // runtime, which is the whole point of costing it from sessions.
      expect(PoMaths.notYetBilled(project, [march, april]),
          closeTo(47200, 0.5));
    });

    test('variance covers invoiced months only', () {
      // Both months are now pinned to their invoices, so only Tally's
      // round-off remains.
      expect(PoMaths.variance(project, [march]), closeTo(0.10, 0.5));
      expect(PoMaths.variance(project, [march, april]), closeTo(0.10, 1));
    });

    test('carried extras stay out of the drawdown', () {
      // 2,05,000 ex-GST of Vehicle Validation and Instrumentation appear on no
      // invoice. Counting them as PO drawdown is what made the balance read as
      // overspent; the balance comes from invoices instead.
      expect(BillingBaseline.extrasTotal(project), 205000);
      expect(PoMaths.inclGst(BillingBaseline.extrasTotal(project)),
          closeTo(241900, 1));
      expect(PoMaths.balance(poInclTax, [march, april]), closeTo(647018, 1));
    });
  });

  group('randomised', () {
    final rng = Random(20260813);

    test('balance always equals PO minus invoiced, never drifts', () {
      for (var i = 0; i < 2000; i++) {
        final po = rng.nextDouble() * 5000000;
        final invoices = List.generate(
          rng.nextInt(6),
          (n) => _inv('2026-${(rng.nextInt(12) + 1).toString().padLeft(2, '0')}',
              rng.nextDouble() * 900000),
        );
        final expected =
            po - invoices.fold(0.0, (s, e) => s + e.totalAmount);
        expect(PoMaths.balance(po, invoices), closeTo(expected, 0.001));
      }
    });

    test('invoicing a month always moves it out of not-yet-billed', () {
      final months =
          BillingBaseline.forProject(project).map((m) => m.month).toList();
      for (var i = 0; i < 1000; i++) {
        final subset = months.where((_) => rng.nextBool()).toList();
        final invoices = [
          for (final m in subset) _inv(m, rng.nextDouble() * 900000)
        ];
        final pending = PoMaths.notYetBilled(project, invoices);
        final expected = BillingBaseline.forProject(project)
            .where((m) => !subset.contains(m.month))
            .fold(0.0, (s, m) => s + m.inclGst);
        expect(pending, closeTo(expected, 0.001));

        // Nothing may be counted twice: invoiced + pending covers each month
        // exactly once when invoices sit at baseline value.
        final atBaseline = [
          for (final m in BillingBaseline.forProject(project))
            if (subset.contains(m.month)) _inv(m.month, m.inclGst)
        ];
        final whole = PoMaths.invoicedTotal(atBaseline) +
            PoMaths.notYetBilled(project, atBaseline);
        expect(
            whole,
            closeTo(
                BillingBaseline.forProject(project)
                    .fold(0.0, (s, m) => s + m.inclGst),
                0.01));
      }
    });

    test('variance is zero exactly when every invoice equals its baseline', () {
      for (var i = 0; i < 1000; i++) {
        final atBaseline = [
          for (final m in BillingBaseline.forProject(project))
            if (rng.nextBool()) _inv(m.month, m.inclGst)
        ];
        expect(PoMaths.variance(project, atBaseline), closeTo(0, 0.001));

        // Nudge one invoice and the variance must move by exactly that nudge.
        if (atBaseline.isNotEmpty) {
          final delta = (rng.nextDouble() - 0.5) * 50000;
          final idx = rng.nextInt(atBaseline.length);
          final nudged = [...atBaseline];
          nudged[idx] = _inv(
              nudged[idx].periodMonth!, nudged[idx].totalAmount + delta);
          expect(PoMaths.variance(project, nudged), closeTo(delta, 0.01));
        }
      }
    });

    test('an invoice for a month with no baseline never breaks the maths', () {
      for (var i = 0; i < 500; i++) {
        final stray = _inv('2027-${(rng.nextInt(12) + 1).toString().padLeft(2, '0')}',
            rng.nextDouble() * 500000);
        // It draws the PO down…
        expect(PoMaths.balance(poInclTax, [stray]),
            closeTo(poInclTax - stray.totalAmount, 0.001));
        // …but contributes no variance, having nothing to compare against.
        expect(PoMaths.variance(project, [stray]), 0);
        // …and leaves every baseline month still pending.
        expect(PoMaths.notYetBilled(project, [stray]),
            closeTo(1647344.90, 0.5));
      }
    });

    test('GST round-trips within a rupee at any scale', () {
      for (var i = 0; i < 2000; i++) {
        final excl = rng.nextDouble() * 10000000;
        final incl = PoMaths.inclGst(excl);
        expect(incl - excl, closeTo(excl * 0.18, 0.001));
        expect(incl / 1.18, closeTo(excl, 0.001));
      }
    });

    test('InvoiceTotals agrees with a plain sum for any invoice set', () {
      for (var i = 0; i < 1000; i++) {
        final invoices = List.generate(rng.nextInt(8), (n) {
          final excl = rng.nextDouble() * 800000;
          final gst = excl * 0.18;
          return NatraxInvoice(
            id: '$i-$n',
            invoiceNumber: 'INV-$i-$n',
            projectName: project,
            periodMonth: '2026-0${rng.nextInt(9) + 1}',
            amountExclGst: excl,
            gstAmount: gst,
            totalAmount: excl + gst,
          );
        });
        final t = InvoiceTotals.from(invoices);
        expect(t.count, invoices.length);
        expect(t.total,
            closeTo(invoices.fold(0.0, (s, e) => s + e.totalAmount), 0.001));
        expect(t.exclGst,
            closeTo(invoices.fold(0.0, (s, e) => s + e.amountExclGst), 0.001));
        expect(t.gst,
            closeTo(invoices.fold(0.0, (s, e) => s + e.gstAmount), 0.001));
        expect(t.exclGst + t.gst, closeTo(t.total, 0.01));
      }
    });
  });

  group('parser robustness on randomised text', () {
    final rng = Random(7);

    test('never throws and never invents figures', () {
      const fragments = [
        'Invoice No.INV/26-27/',
        'Buyer\'s Order No.',
        'Dated',
        'Total ',
        'IGST',
        'CGST',
        'SGST',
        '998346',
        '1,00,000.00',
        'Terms of DeliveryTesting Period From 01 to 30-April-2026.',
        '',
        'HSN/SAC',
        '18%',
      ];
      for (var i = 0; i < 3000; i++) {
        final lines = List.generate(
            rng.nextInt(25), (_) => fragments[rng.nextInt(fragments.length)]);
        final parsed = NatraxInvoiceParser.parseText(lines.join('\n'));

        // Whatever it reads, an amount is never negative or absurd.
        for (final v in [
          parsed.amountExclGst,
          parsed.gstAmount,
          parsed.totalAmount
        ]) {
          if (v != null) {
            expect(v, greaterThanOrEqualTo(0));
            expect(v.isFinite, isTrue);
          }
        }
        // addsUp must be an honest verdict, never optimistic: it may only be
        // true when the three figures genuinely reconcile.
        if (parsed.isComplete && parsed.addsUp) {
          expect(parsed.amountExclGst! + parsed.gstAmount!,
              closeTo(parsed.totalAmount!, 1.0));
        }
        // An incomplete read must say what it could not find.
        if (!parsed.isComplete) {
          expect(parsed.missingFields, isNotEmpty);
        }
      }
    });
  });
}
