import 'billing_baseline.dart';
import 'invoice_service.dart';
import 'resource_service.dart';
import 'supabase_service.dart';

/// Builds the as-on-date management update: PO position, what NATRAX has
/// actually invoiced, what is computed but unbilled, track utilisation and
/// resource allocation.
///
/// The governing rule is that an estimate is never presented as a billed fact.
/// Invoiced figures come from uploaded originals; anything the app computed is
/// labelled as such, so management can tell the difference.
class ManagementReportService {
  static ManagementReportService? _instance;
  static ManagementReportService get instance =>
      _instance ??= ManagementReportService._();
  ManagementReportService._();

  static const _defaultTo = 'praharshithkumar_komaragiri@goodyear.com';
  static const _defaultCc = [
    'v_vimal@goodyear.com',
    'ashish_pandit@goodyear.com',
    'yeswanth_golla@goodyear.com',
    'niranjan_poloju@goodyear.com',
  ];

  /// Gathers everything and renders the mail without sending it.
  Future<ManagementUpdate> generate({
    required String projectName,
    String? vehicleName,
    DateTime? asOn,
  }) async {
    final client = SupabaseService.instance.client;
    final date = asOn ?? DateTime.now();

    // ── Purchase orders ──────────────────────────────────────────────────
    final poRows = await client.from('po_trackers').select().order('created_at');
    final pos = (poRows as List).cast<Map<String, dynamic>>();
    final poTotal = pos.fold<double>(
        0,
        (s, p) =>
            s +
            ((p['total_po_value'] as num?)?.toDouble() ?? 0) +
            ((p['tax_amount'] as num?)?.toDouble() ?? 0));

    // ── Invoices actually raised ─────────────────────────────────────────
    final invoices =
        await InvoiceService.instance.list(projectName: projectName);
    invoices.sort((a, b) => (a.periodMonth ?? '').compareTo(b.periodMonth ?? ''));
    final invoicedTotal = invoices.fold<double>(0, (s, i) => s + i.totalAmount);
    final invoicedMonths = {
      for (final i in invoices)
        if ((i.periodMonth ?? '').isNotEmpty) i.periodMonth!: i.totalAmount
    };

    // ── Computed but unbilled ────────────────────────────────────────────
    final baseline = BillingBaseline.forProject(projectName);
    final unbilled =
        baseline.where((m) => !invoicedMonths.containsKey(m.month)).toList();
    final unbilledTotal = unbilled.fold<double>(0, (s, m) => s + m.inclGst);

    final balance = poTotal - invoicedTotal;
    final projected = balance - unbilledTotal;
    final utilisationPct = poTotal <= 0 ? 0.0 : invoicedTotal / poTotal;
    final projectedPct =
        poTotal <= 0 ? 0.0 : (invoicedTotal + unbilledTotal) / poTotal;

    // ── Track utilisation ────────────────────────────────────────────────
    final sessionRows = await client
        .from('engineer_sessions')
        .select('track_code, track_name, duration_minutes, project_name, started_at')
        .eq('session_status', 'completed');

    final trackHours = <String, double>{};
    var totalHours = 0.0;
    var sessionCount = 0;
    for (final s in sessionRows as List) {
      final raw = (s['project_name'] as String?)?.trim().toLowerCase() ?? '';
      final normalised =
          (raw.isEmpty || raw == 'general') ? 'mahindra ev poc' : raw;
      if (normalised != projectName.toLowerCase()) continue;
      final hrs = (s['duration_minutes'] as int? ?? 0) / 60.0;
      final code = (s['track_name'] as String?)?.trim().isNotEmpty == true
          ? s['track_name'] as String
          : (s['track_code'] as String? ?? 'Unknown');
      trackHours[code] = (trackHours[code] ?? 0) + hrs;
      totalHours += hrs;
      sessionCount++;
    }
    final tracks = trackHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ── Resources ────────────────────────────────────────────────────────
    // Optional: the tables may not exist yet on a given environment.
    List<ResourceUtilisation> resources = [];
    try {
      final windowStart = baseline.isNotEmpty
          ? DateTime.parse('${baseline.first.month}-01')
          : DateTime(date.year, date.month - 2, 1);
      resources = await ResourceService.instance.utilisation(
        from: windowStart,
        to: date,
        projectName: projectName,
      );
    } catch (_) {
      resources = [];
    }

    // ── Points needing attention ─────────────────────────────────────────
    final attention = <String>[];

    for (final m in unbilled) {
      final monthsOld = _monthsBetween(DateTime.parse('${m.month}-01'), date);
      attention.add(
          '<b>${_monthLabel(m.month)} invoice outstanding.</b> Testing completed in '
          '${_monthLabel(m.month)} has not been invoiced'
          '${monthsOld >= 2 ? ' after ~$monthsOld months' : ''}. '
          'Computed value ${_inr(m.inclGst)}. Recommend following up with '
          'NATRAX finance so the PO position reflects committed spend.');
    }

    for (final m in baseline) {
      final billed = invoicedMonths[m.month];
      if (billed == null) continue;
      final diff = billed - m.inclGst;
      if (diff.abs() < 100) continue;
      attention.add(
          '<b>${_monthLabel(m.month)} billed ${_inr(diff.abs())} '
          '${diff > 0 ? 'above' : 'below'} our record.</b> NATRAX invoiced '
          '${_inr(billed)} against our computed ${_inr(m.inclGst)}. '
          'To be reconciled.');
    }

    if (projectedPct >= 0.85) {
      attention.add(
          '<b>PO headroom is tight.</b> At ${(projectedPct * 100).toStringAsFixed(0)}% '
          'projected utilisation once unbilled work is invoiced, the current PO '
          'covers little beyond work already done. A follow-on PO will be needed '
          'before further track booking.');
    }

    final overAllocated = resources.where((r) => r.isOverAllocated).toList();
    if (overAllocated.isNotEmpty) {
      attention.add(
          '<b>${overAllocated.length} resource(s) over-allocated:</b> '
          '${overAllocated.map((r) => r.resource.name).join(', ')}. '
          'Allocation exceeds available hours in the period.');
    }

    if (resources.isEmpty) {
      attention.add(
          '<b>Resource allocation not yet populated.</b> Availability and '
          'allocation data is being set up and will be included from the next '
          'update.');
    }

    final subject = 'NATRAX ${_short(projectName)} — PO & Expense Status '
        'as on ${_fmtDate(date)}';

    final html = _html(
      projectName: projectName,
      vehicleName: vehicleName,
      asOn: date,
      pos: pos,
      poTotal: poTotal,
      invoices: invoices,
      invoicedTotal: invoicedTotal,
      unbilled: unbilled,
      unbilledTotal: unbilledTotal,
      balance: balance,
      projected: projected,
      utilisationPct: utilisationPct,
      projectedPct: projectedPct,
      tracks: tracks,
      totalHours: totalHours,
      sessionCount: sessionCount,
      resources: resources,
      attention: attention,
    );

    final plain = _plainText(
      projectName: projectName,
      asOn: date,
      pos: pos,
      byPo: {
        for (final i in invoices)
          if ((i.poNumber ?? '').isNotEmpty)
            i.poNumber!: (invoices
                .where((x) => x.poNumber == i.poNumber)
                .fold<double>(0, (s, x) => s + x.totalAmount))
      },
      poTotal: poTotal,
      invoicedTotal: invoicedTotal,
      balance: balance,
      unbilledTotal: unbilledTotal,
      projected: projected,
      attention: attention,
    );

    return ManagementUpdate(
      subject: subject,
      html: html,
      plainText: plain,
      poTotal: poTotal,
      invoicedTotal: invoicedTotal,
      unbilledTotal: unbilledTotal,
      balance: balance,
      projectedBalance: projected,
      attentionCount: attention.length,
    );
  }

  /// Sends the update. Defaults to the standing manager + CC list.
  Future<Map<String, dynamic>> send({
    required ManagementUpdate update,
    String? toEmail,
    List<String>? ccEmails,
    String recipientName = 'Harsh',
  }) async {
    final client = SupabaseService.instance.client;
    final to = toEmail ?? _defaultTo;
    final cc = ccEmails ?? _defaultCc;
    try {
      final response = await client.functions.invoke(
        'send-report-email',
        body: {
          'recipientEmail': to,
          'recipientName': recipientName,
          'ccEmails': cc,
          'subject': update.subject,
          'htmlBody': update.html,
          'reportType': 'management',
          'poData': {
            'totalPo': update.poTotal,
            'invoiced': update.invoicedTotal,
            'balance': update.balance,
          },
          'spendBreakdown': {
            'invoiced': update.invoicedTotal,
            'notYetBilled': update.unbilledTotal,
          },
          'sessionSummary': const [],
        },
      );
      final data = response.data as Map<String, dynamic>?;
      final success = data?['success'] == true;

      await client.from('email_send_log').insert({
        'recipient_email': to,
        'report_type': 'management',
        'status': success ? 'sent' : 'failed',
        'error_message': success ? null : (data?['error'] as String?),
      });

      return {'success': success, 'error': data?['error']};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Rendering ──────────────────────────────────────────────────────────────

  String _html({
    required String projectName,
    required String? vehicleName,
    required DateTime asOn,
    required List<Map<String, dynamic>> pos,
    required double poTotal,
    required List<NatraxInvoice> invoices,
    required double invoicedTotal,
    required List<MonthBaseline> unbilled,
    required double unbilledTotal,
    required double balance,
    required double projected,
    required double utilisationPct,
    required double projectedPct,
    required List<MapEntry<String, double>> tracks,
    required double totalHours,
    required int sessionCount,
    required List<ResourceUtilisation> resources,
    required List<String> attention,
  }) {
    const th = 'style="text-align:left;padding:7px 10px;background:#0057e6;'
        'color:#fff;font-size:12px;font-weight:600;"';
    const td = 'style="padding:7px 10px;border-bottom:1px solid #e6e9f0;'
        'font-size:13px;"';
    const tdr = 'style="padding:7px 10px;border-bottom:1px solid #e6e9f0;'
        'font-size:13px;text-align:right;"';

    // Drawdown per PO, from the PO each invoice names. This is what answers
    // "which PO paid for track time and which paid for manpower".
    final byPo = <String, double>{};
    for (final i in invoices) {
      final po = (i.poNumber ?? '').trim();
      if (po.isEmpty) continue;
      byPo[po] = (byPo[po] ?? 0) + i.totalAmount;
    }
    final knownPos = pos
        .map((p) => (p['po_number'] as String? ?? '').trim())
        .where((p) => p.isNotEmpty)
        .toSet();
    final orphans = invoices
        .where((i) => !knownPos.contains((i.poNumber ?? '').trim()))
        .toList();

    final poRows = pos.map((p) {
      final number = (p['po_number'] as String? ?? '').trim();
      final base = (p['total_po_value'] as num?)?.toDouble() ?? 0;
      final tax = (p['tax_amount'] as num?)?.toDouble() ?? 0;
      final total = base + tax;
      final drawn = byPo[number] ?? 0;
      final left = total - drawn;
      final pct = total <= 0 ? 0 : (drawn / total * 100);
      return '<tr><td $td>PO $number<br>'
          '<span style="color:#0057e6;font-size:10px;font-weight:600;">'
          '${_categoryLabel(p['category'] as String? ?? 'other')}</span>'
          '<span style="color:#6b7490;font-size:11px;"> · '
          '${_truncate(p['description'] as String? ?? '', 70)}</span></td>'
          '<td $tdr>${_inr(total)}</td>'
          '<td $tdr>${_inr(drawn)}'
          '<span style="color:#6b7490;font-size:10px;"> (${pct.toStringAsFixed(0)}%)</span></td>'
          '<td $tdr style="color:${left < 0 ? '#c62828' : '#1a7f37'};">'
          '<b>${_inr(left)}</b></td></tr>';
    }).join();

    final orphanRow = orphans.isEmpty
        ? ''
        : '<tr><td $td colspan="4" style="background:#fff8e1;color:#b26a00;'
            'font-size:12px;">'
            '${_inr(orphans.fold<double>(0, (s, i) => s + i.totalAmount))} '
            'invoiced against PO '
            '${orphans.map((i) => i.poNumber ?? '(none)').toSet().join(', ')}, '
            'which is not yet loaded in the tracker — available funding above '
            'is understated.</td></tr>';

    final invoiceRows = invoices.isEmpty
        ? '<tr><td $td colspan="4" style="color:#b26a00;">No invoices uploaded yet</td></tr>'
        : invoices.map((i) {
            return '<tr><td $td>${i.invoiceNumber}</td>'
                '<td $td>${i.invoiceDate == null ? '—' : _fmtDate(i.invoiceDate!)}</td>'
                '<td $td>${i.periodMonth == null ? '—' : _monthLabel(i.periodMonth!)}</td>'
                '<td $tdr><b>${_inr(i.totalAmount)}</b></td></tr>';
          }).join();

    final unbilledRows = unbilled.isEmpty
        ? '<tr><td $td colspan="2" style="color:#1a7f37;">Everything billed to date</td></tr>'
        : unbilled
            .map((m) => '<tr><td $td>${_monthLabel(m.month)} '
                '<span style="color:#6b7490;font-size:11px;">(computed, not invoiced)</span></td>'
                '<td $tdr>${_inr(m.inclGst)}</td></tr>')
            .join();

    final trackRows = tracks.isEmpty
        ? '<tr><td $td colspan="3">No sessions logged</td></tr>'
        : tracks.map((t) {
            final pct = totalHours <= 0 ? 0.0 : t.value / totalHours * 100;
            return '<tr><td $td>${t.key}</td>'
                '<td $tdr>${t.value.toStringAsFixed(1)} h</td>'
                '<td $tdr>${pct.toStringAsFixed(0)}%</td></tr>';
          }).join();

    // A resource with nothing allocated and nothing used contributes no
    // information to a management update — it just pads the table with zeros.
    // Count them instead, so the capacity is still acknowledged.
    final engaged = resources
        .where((r) => r.allocatedHours > 0 || r.utilisedHours > 0)
        .toList();
    final idleCount = resources.length - engaged.length;

    final resourceSection = engaged.isEmpty
        ? '<p style="font-size:13px;color:#6b7490;">'
            '${resources.isEmpty ? 'Resource availability and allocation is being set up and will be included from the next update.' : '${resources.length} resource(s) on record, none allocated or utilised in this period.'}'
            '</p>'
        : '''
<table style="border-collapse:collapse;width:100%;margin-top:6px;">
<tr><th $th>Resource</th><th $th>Role</th>
<th $th style="text-align:right">Available</th>
<th $th style="text-align:right">Allocated</th>
<th $th style="text-align:right">Utilised</th>
<th $th style="text-align:right">Util. %</th></tr>
${engaged.map((r) {
            final warn = r.isOverAllocated;
            return '<tr><td $td>${r.resource.name}'
                '${r.utilisationFromSessions ? '' : '<span style="color:#6b7490;font-size:11px;"> (manual)</span>'}</td>'
                '<td $td>${r.resource.roleTitle ?? r.resource.type}</td>'
                '<td $tdr>${r.availableHours.toStringAsFixed(0)} h</td>'
                '<td $tdr${warn ? ' bgcolor="#fff3e0"' : ''}>${r.allocatedHours.toStringAsFixed(0)} h</td>'
                '<td $tdr>${r.utilisedHours.toStringAsFixed(1)} h</td>'
                '<td $tdr>${(r.utilisationRate * 100).toStringAsFixed(0)}%</td></tr>';
          }).join()}
</table>
<p style="font-size:11px;color:#6b7490;margin-top:4px;">
Utilised is taken from logged sessions where the resource is a test engineer;
rows marked (manual) use hours recorded against the allocation.${idleCount > 0 ? ' A further $idleCount resource(s) on record had no allocation or logged hours this period.' : ''}</p>''';

    final attentionItems = attention.isEmpty
        ? '<li>Nothing outstanding.</li>'
        : attention.map((a) => '<li style="margin-bottom:9px;">$a</li>').join();

    return '''
<div style="font-family:Segoe UI,Arial,sans-serif;color:#1a1f36;max-width:760px;">
<h2 style="margin:0 0 2px;font-size:19px;">NATRAX Proving Ground — ${_short(projectName)}</h2>
<p style="margin:0 0 16px;color:#6b7490;font-size:13px;">
Goodyear SightLine tire intelligence validation${vehicleName == null ? '' : ' · $vehicleName'}
&nbsp;|&nbsp; Status as on <b>${_fmtDate(asOn)}</b></p>

<div style="background:#f4f7fb;border-left:4px solid #0057e6;padding:12px 14px;margin-bottom:18px;">
<table style="width:100%;font-size:14px;">
<tr><td style="padding:3px 0;">Total PO value (incl. tax)</td>
    <td style="text-align:right;"><b>${_inr(poTotal)}</b></td></tr>
<tr><td style="padding:3px 0;">Invoiced by NATRAX to date</td>
    <td style="text-align:right;"><b>${_inr(invoicedTotal)}</b>
    <span style="color:#6b7490;">(${(utilisationPct * 100).toStringAsFixed(0)}%)</span></td></tr>
<tr><td style="padding:3px 0;font-size:15px;"><b>Balance available</b></td>
    <td style="text-align:right;font-size:15px;color:${balance < 0 ? '#c62828' : '#1a7f37'};">
    <b>${_inr(balance)}</b></td></tr>
</table></div>

<h3 style="font-size:14px;margin:18px 0 6px;">Purchase orders — what each covers and what is left</h3>
<table style="border-collapse:collapse;width:100%;">
<tr><th $th>PO / purpose</th><th $th style="text-align:right">PO value</th>
<th $th style="text-align:right">Invoiced</th>
<th $th style="text-align:right">Balance</th></tr>
$poRows
$orphanRow
</table>
<p style="font-size:11px;color:#6b7490;margin-top:4px;">
Each invoice is attributed to the PO it names (Buyer's Order No.), so track
booking and manpower spend are drawn from their own POs.</p>

<h3 style="font-size:14px;margin:18px 0 6px;">Invoices raised</h3>
<table style="border-collapse:collapse;width:100%;">
<tr><th $th>Invoice</th><th $th>Dated</th><th $th>Billing period</th>
<th $th style="text-align:right">Amount</th></tr>
$invoiceRows
<tr><td $td colspan="3"><b>Total invoiced</b></td>
    <td $tdr><b>${_inr(invoicedTotal)}</b></td></tr>
</table>
<p style="font-size:11px;color:#6b7490;margin-top:4px;">
Originals are on file and verified against our session records.</p>

<h3 style="font-size:14px;margin:18px 0 6px;">Not yet billed</h3>
<table style="border-collapse:collapse;width:100%;">
$unbilledRows
<tr><td $td><b>Projected balance once billed</b></td>
    <td $tdr><b>${_inr(projected)}</b>
    <span style="color:#6b7490;font-size:11px;">
    (${(projectedPct * 100).toStringAsFixed(0)}% utilised)</span></td></tr>
</table>

<h3 style="font-size:14px;margin:18px 0 6px;">Track utilisation</h3>
<p style="margin:0 0 4px;font-size:13px;">
<b>${totalHours.toStringAsFixed(1)} hours</b> across <b>$sessionCount sessions</b></p>
<table style="border-collapse:collapse;width:100%;">
<tr><th $th>Track</th><th $th style="text-align:right">Hours</th>
<th $th style="text-align:right">Share</th></tr>
$trackRows
</table>

<h3 style="font-size:14px;margin:18px 0 6px;">Testing resources</h3>
$resourceSection

<h3 style="font-size:14px;margin:18px 0 6px;">Points needing attention</h3>
<ol style="font-size:13px;line-height:1.55;padding-left:18px;margin:0;">
$attentionItems
</ol>

<p style="margin-top:22px;font-size:12px;color:#6b7490;">
Live dashboard: <a href="https://sightlinevalidation.web.app">sightlinevalidation.web.app</a><br>
Generated by TrackLog on ${_fmtDate(asOn)}. Figures marked <i>computed</i> are
derived from session records and rate cards; all other amounts come from
invoices raised by NATRAX.</p>
</div>''';
  }

  /// A compact readable version for the compose window, before the formatted
  /// report is pasted over it. Kept short — mailto bodies get truncated.
  String _plainText({
    required String projectName,
    required DateTime asOn,
    required List<Map<String, dynamic>> pos,
    required Map<String, double> byPo,
    required double poTotal,
    required double invoicedTotal,
    required double balance,
    required double unbilledTotal,
    required double projected,
    required List<String> attention,
  }) {
    final b = StringBuffer()
      ..writeln('$projectName — NATRAX Proving Ground')
      ..writeln('Status as on ${_fmtDate(asOn)}')
      ..writeln()
      ..writeln('PO POSITION')
      ..writeln('  Total PO value      ${_inr(poTotal)}')
      ..writeln('  Invoiced to date    ${_inr(invoicedTotal)}')
      ..writeln('  Balance available   ${_inr(balance)}');

    if (unbilledTotal > 0) {
      b
        ..writeln('  Not yet billed      ${_inr(unbilledTotal)} (computed)')
        ..writeln('  Projected balance   ${_inr(projected)}');
    }

    if (pos.isNotEmpty) {
      b
        ..writeln()
        ..writeln('BY PURCHASE ORDER');
      for (final p in pos) {
        final number = (p['po_number'] as String? ?? '').trim();
        final total = ((p['total_po_value'] as num?)?.toDouble() ?? 0) +
            ((p['tax_amount'] as num?)?.toDouble() ?? 0);
        final drawn = byPo[number] ?? 0;
        b.writeln('  PO $number '
            '(${_categoryLabel(p['category'] as String? ?? 'other').toLowerCase()})'
            ' — invoiced ${_inr(drawn)} of ${_inr(total)}, '
            'balance ${_inr(total - drawn)}');
      }
    }

    if (attention.isNotEmpty) {
      b
        ..writeln()
        ..writeln('POINTS NEEDING ATTENTION');
      for (var i = 0; i < attention.length; i++) {
        b.writeln('  ${i + 1}. ${_stripTags(attention[i])}');
      }
    }

    b
      ..writeln()
      ..writeln('Live dashboard: https://sightlinevalidation.web.app')
      ..writeln('Figures marked computed are derived from session records; '
          'all other amounts come from invoices raised by NATRAX.');

    return b.toString();
  }

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&');

  // ── Formatting ─────────────────────────────────────────────────────────────

  static String _inr(double v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(0);
    // Indian grouping: last three, then pairs.
    final buf = StringBuffer();
    final last3 = s.length > 3 ? s.substring(s.length - 3) : s;
    var rest = s.length > 3 ? s.substring(0, s.length - 3) : '';
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    buf.write(parts.isEmpty ? last3 : '${parts.join(',')},$last3');
    return '${neg ? '-' : ''}₹ ${buf.toString()}';
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} '
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} '
      '${d.year}';

  static String _monthLabel(String yyyyMm) {
    final p = yyyyMm.split('-');
    if (p.length != 2) return yyyyMm;
    final m = int.tryParse(p[1]);
    if (m == null || m < 1 || m > 12) return yyyyMm;
    return '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1]} ${p[0]}';
  }

  static int _monthsBetween(DateTime from, DateTime to) =>
      (to.year - from.year) * 12 + (to.month - from.month);

  static String _short(String project) => project;

  static String _categoryLabel(String c) => switch (c) {
        'track_booking' => 'TRACK BOOKING',
        'manpower' => 'MANPOWER',
        'workshop' => 'WORKSHOP',
        'instrumentation' => 'INSTRUMENTATION',
        _ => 'UNCATEGORISED',
      };

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

/// A rendered update, ready to preview or send.
class ManagementUpdate {
  final String subject;
  final String html;

  /// Readable fallback for a mailto body, which cannot carry HTML.
  final String plainText;
  final double poTotal;
  final double invoicedTotal;
  final double unbilledTotal;
  final double balance;
  final double projectedBalance;
  final int attentionCount;

  const ManagementUpdate({
    required this.subject,
    required this.html,
    this.plainText = '',
    required this.poTotal,
    required this.invoicedTotal,
    required this.unbilledTotal,
    required this.balance,
    required this.projectedBalance,
    required this.attentionCount,
  });
}
