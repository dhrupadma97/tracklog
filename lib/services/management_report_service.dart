import 'billing_baseline.dart';
import 'invoice_service.dart';
import 'muster_service.dart';
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
    String recipientName = 'Harsh',
  }) async {
    final client = SupabaseService.instance.client;
    final date = asOn ?? DateTime.now();

    // ── Purchase orders ──────────────────────────────────────────────────
    final poRows = await client.from('po_trackers').select().order('created_at');
    final pos = (poRows as List).cast<Map<String, dynamic>>();

    // Man-days actually mustered, folded onto the PO rows rather than threaded
    // through the renderer as another argument. Days worked and days invoiced
    // are different numbers, and the report shows both.
    try {
      final mustered = await MusterService.instance.manDaysByPo();
      for (final p in pos) {
        final n = (p['po_number'] as String? ?? '').trim();
        if (mustered.containsKey(n)) p['man_days_mustered'] = mustered[n];
      }
    } catch (_) {
      // The muster table may not exist yet on a given environment.
    }
    // A PO that is spent, or has no value recorded, is not funding.
    bool bookable(Map<String, dynamic> p) {
      final s = (p['po_status'] as String? ?? '').toLowerCase();
      if (s == 'used' || s == 'closed') return false;
      return ((p['total_po_value'] as num?)?.toDouble() ?? 0) +
              ((p['tax_amount'] as num?)?.toDouble() ?? 0) >
          0;
    }

    // Both tax bases are carried through: procurement sanctions POs ex-GST,
    // invoices arrive incl-GST, and quoting only one invites the two being
    // compared against each other.
    final poTotal = pos.where(bookable).fold<double>(
        0,
        (s, p) =>
            s +
            ((p['total_po_value'] as num?)?.toDouble() ?? 0) +
            ((p['tax_amount'] as num?)?.toDouble() ?? 0));
    final poTotalExcl = pos.where(bookable).fold<double>(
        0, (s, p) => s + ((p['total_po_value'] as num?)?.toDouble() ?? 0));

    // ── Invoices actually raised ─────────────────────────────────────────
    final invoices =
        await InvoiceService.instance.list(projectName: projectName);
    invoices.sort((a, b) => (a.periodMonth ?? '').compareTo(b.periodMonth ?? ''));
    final invoicedTotal = invoices.fold<double>(0, (s, i) => s + i.totalAmount);
    final invoicedTotalExcl =
        invoices.fold<double>(0, (s, i) => s + i.amountExclGst);
    // Only track and workshop invoices can be measured against the monthly
    // baseline — it describes nothing else. A manpower invoice in the same
    // month is real spend, but comparing it here produced a nonsense variance
    // ("May billed 3,86,260 below our record" when the 59,472 was manpower).
    final baselinePos = pos
        .where((p) => BillingBaseline.baselineCategories
            .contains((p['category'] as String? ?? '').toLowerCase()))
        .map((p) => (p['po_number'] as String? ?? '').trim())
        .where((p) => p.isNotEmpty)
        .toSet();

    final invoicedMonths = <String, double>{};
    for (final i in invoices) {
      final m = i.periodMonth ?? '';
      if (m.isEmpty) continue;
      if (!baselinePos.contains((i.poNumber ?? '').trim())) continue;
      invoicedMonths[m] = (invoicedMonths[m] ?? 0) + i.totalAmount;
    }

    // ── Track utilisation and live session cost ──────────────────────────
    // Costed before the unbilled figure below, which depends on it: a month
    // with no fixed track figure is priced from these sessions.
    final sessionRows = await client
        .from('engineer_sessions')
        .select('id, total_cost, track_code, track_name, duration_minutes, '
            'project_name, started_at')
        .eq('session_status', 'completed');

    final servicesRows = await client
        .from('session_additional_services')
        .select('session_id, total_cost');
    final svcBySession = <String, double>{};
    for (final s in servicesRows as List) {
      final sid = s['session_id'] as String?;
      if (sid == null) continue;
      svcBySession[sid] = (svcBySession[sid] ?? 0) +
          ((s['total_cost'] as num?)?.toDouble() ?? 0);
    }

    final trackHours = <String, double>{};
    final liveCostByMonth = <String, double>{};
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

      final startedAt = DateTime.tryParse(s['started_at'] as String? ?? '');
      if (startedAt == null) continue;
      final key = '${startedAt.year}-'
          '${startedAt.month.toString().padLeft(2, '0')}';
      final sid = s['id'] as String?;
      liveCostByMonth[key] = (liveCostByMonth[key] ?? 0) +
          ((s['total_cost'] as num?)?.toDouble() ?? 0) +
          (sid == null ? 0 : (svcBySession[sid] ?? 0));
    }
    final tracks = trackHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ── Computed but unbilled ────────────────────────────────────────────
    // A computed month carries only its workshop rental in the baseline —
    // MonthBaseline.exclGst states that callers must add the session cost.
    // This one did not, so May reported 47,200: the 40,000 rental grossed up,
    // with every hour actually logged that month missing from it.
    final baseline = BillingBaseline.forProject(projectName);
    final unbilled = baseline
        .where((m) => !invoicedMonths.containsKey(m.month))
        .map((m) => m.isTrackComputed
            ? MonthBaseline(
                month: m.month,
                trackAndAccessories: liveCostByMonth[m.month] ?? 0,
                workshopRental: m.workshopRental)
            : m)
        .toList();
    final unbilledTotal = unbilled.fold<double>(0, (s, m) => s + m.inclGst);

    final balance = poTotal - invoicedTotal;
    final balanceExcl = poTotalExcl - invoicedTotalExcl;
    final projected = balance - unbilledTotal;
    final utilisationPct = poTotal <= 0 ? 0.0 : invoicedTotal / poTotal;
    final projectedPct =
        poTotal <= 0 ? 0.0 : (invoicedTotal + unbilledTotal) / poTotal;

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
          '<b>${_monthLabel(m.month)} track billing is ${_inr(diff.abs())} '
          '${diff > 0 ? 'above' : 'below'} our record.</b> Invoiced '
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

    // The bay is held by the day, so an open period is a liability that grows
    // whether or not anyone is testing.
    final openWsDays = BillingBaseline.openWorkshopDays(date);
    if (openWsDays > 0) {
      attention.add(
          '<b>Workshop rental accruing since '
          '${_fmtDate(BillingBaseline.workshopResumedOn)}.</b> The bay has been '
          'held for $openWsDays day${openWsDays == 1 ? '' : 's'} at '
          '${_inr(BillingBaseline.workshopDayRate)}/day — '
          '${_inr(BillingBaseline.openWorkshopRental(date))} not yet invoiced '
          'and growing daily. It will draw on the track PO once NATRAX raises '
          'it.');
    }

    // Manpower is contracted in days, so it runs out in days rather than in
    // rupees — and the muster can run ahead of what MOICARS has billed.
    final invoicedExclByPo = <String, double>{};
    for (final i in invoices) {
      final po = (i.poNumber ?? '').trim();
      if (po.isEmpty) continue;
      invoicedExclByPo[po] = (invoicedExclByPo[po] ?? 0) + i.amountExclGst;
    }

    for (final e in _manpowerPending(pos, invoicedExclByPo)) {
      attention.add(
          '<b>Manpower worked but not invoiced on PO ${e.poNumber}.</b> The '
          'muster records ${_trimNum(e.days)} man-days more than MOICARS has '
          'billed — ${_inr(e.amountInclGst)} sitting outside PO drawdown. '
          'Recommend chasing the invoice so the position is complete.');
    }

    // Cover running out is a different question from billing lag, and needs
    // raising earlier: a new PO takes longer than an invoice.
    for (final p in pos.where(
        (p) => (p['category'] as String? ?? '').toLowerCase() == 'manpower')) {
      final number = (p['po_number'] as String? ?? '').trim();
      final contracted = (p['manpower_days'] as num?)?.toDouble() ?? 0;
      if (contracted <= 0) continue;
      final used = ((p['manpower_days_opening'] as num?)?.toDouble() ?? 0) +
          ((p['man_days_mustered'] as num?)?.toDouble() ?? 0);
      final left = contracted - used;
      if (left > 10) continue;

      attention.add(left < 0
          ? '<b>Manpower PO $number is overrun.</b> '
              '${_trimNum(used)} man-days used against '
              '${_trimNum(contracted)} contracted. A follow-on PO is needed '
              'before further manpower is booked.'
          : '<b>Manpower PO $number is nearly exhausted.</b> Only '
              '${_trimNum(left)} of ${_trimNum(contracted)} man-days remain. '
              'A follow-on PO should be raised now to avoid a gap in cover.');
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

    // Not titled by programme: the POs are a shared pool drawn on by whichever
    // vehicle is testing, and Mahindra EV PoC is finished.
    final subject =
        'NATRAX SightLine — PO & Expense Status as on ${_fmtDate(date)}';

    final html = _html(
      projectName: projectName,
      vehicleName: vehicleName,
      recipientName: recipientName,
      asOn: date,
      pos: pos,
      poTotal: poTotal,
      poTotalExcl: poTotalExcl,
      invoices: invoices,
      invoicedTotal: invoicedTotal,
      invoicedTotalExcl: invoicedTotalExcl,
      baseline: baseline,
      unbilled: unbilled,
      unbilledTotal: unbilledTotal,
      balance: balance,
      balanceExcl: balanceExcl,
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
      poTotalExcl: poTotalExcl,
      invoicedTotal: invoicedTotal,
      invoicedTotalExcl: invoicedTotalExcl,
      balance: balance,
      balanceExcl: balanceExcl,
      unbilledTotal: unbilledTotal,
      manpowerPending: _manpowerPending(pos, invoicedExclByPo)
          .fold<double>(0, (s, e) => s + e.amountInclGst),
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
    required String recipientName,
    required DateTime asOn,
    required List<Map<String, dynamic>> pos,
    required double poTotal,
    required double poTotalExcl,
    required List<NatraxInvoice> invoices,
    required double invoicedTotal,
    required double invoicedTotalExcl,
    required List<MonthBaseline> baseline,
    required List<MonthBaseline> unbilled,
    required double unbilledTotal,
    required double balance,
    required double balanceExcl,
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
    final byPoExcl = <String, double>{};
    for (final i in invoices) {
      final po = (i.poNumber ?? '').trim();
      if (po.isEmpty) continue;
      byPo[po] = (byPo[po] ?? 0) + i.totalAmount;
      byPoExcl[po] = (byPoExcl[po] ?? 0) + i.amountExclGst;
    }
    final knownPos = pos
        .map((p) => (p['po_number'] as String? ?? '').trim())
        .where((p) => p.isNotEmpty)
        .toSet();
    final orphans = invoices
        .where((i) => !knownPos.contains((i.poNumber ?? '').trim()))
        .toList();

    // Grouped by what the PO covers, with a subtotal each, so track booking
    // and manpower can be read off separately rather than as one blended
    // number.
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final p in pos) {
      final c = (p['category'] as String?) ?? 'other';
      byCategory.putIfAbsent(c, () => []).add(p);
    }
    const categoryOrder = [
      'track_booking',
      'manpower',
      'workshop',
      'instrumentation',
      'other'
    ];
    final orderedCategories = [
      ...categoryOrder.where(byCategory.containsKey),
      ...byCategory.keys.where((c) => !categoryOrder.contains(c)),
    ];

    String categoryBlock(String category) {
      final rows = byCategory[category]!;
      var funded = 0.0, fundedExcl = 0.0, drawn = 0.0, drawnExcl = 0.0;
      var days = 0.0;
      var anyPending = false;
      for (final p in rows) {
        final number = (p['po_number'] as String? ?? '').trim();
        final b = (p['total_po_value'] as num?)?.toDouble() ?? 0;
        final t = b + ((p['tax_amount'] as num?)?.toDouble() ?? 0);
        final status = (p['po_status'] as String? ?? '').toLowerCase();
        final spent = status == 'used' || status == 'closed';
        if (t <= 0) anyPending = true;
        if (!spent && t > 0) {
          funded += t;
          fundedExcl += b;
          drawn += byPo[number] ?? 0;
          drawnExcl += byPoExcl[number] ?? 0;
        }
        if (!spent) days += (p['manpower_days'] as num?)?.toDouble() ?? 0;
      }
      final label = _categoryLabel(category);
      return '<tr><td colspan="4" '
          'style="padding:9px 10px 4px;font-size:11px;font-weight:700;'
          'color:#0057e6;letter-spacing:.5px;border-bottom:1px solid #e6e9f0;">'
          '$label'
          '${funded > 0 ? ' — ${_inr(funded - drawn)} available incl. GST '
              '(${_inr(fundedExcl - drawnExcl)} ex-GST) of ${_inr(funded)}' : ''}'
          '${category == 'manpower' && days > 0 ? ' <span style="color:#3d4757;font-weight:600;">'
              '· ${_trimNum(days)} manpower days contracted</span>' : ''}'
          '${anyPending ? ' <span style="color:#b26a00;font-weight:600;">(some values not recorded)</span>' : ''}'
          '</td></tr>';
    }

    final poRows = orderedCategories.map((category) {
      final block = categoryBlock(category);
      final rows = byCategory[category]!.map((p) {
      final number = (p['po_number'] as String? ?? '').trim();
      final base = (p['total_po_value'] as num?)?.toDouble() ?? 0;
      final tax = (p['tax_amount'] as num?)?.toDouble() ?? 0;
      final total = base + tax;
      final drawn = byPo[number] ?? 0;
      final drawnExcl = byPoExcl[number] ?? 0;
      final left = total - drawn;
      final leftExcl = base - drawnExcl;
      final pct = total <= 0 ? 0 : (drawn / total * 100);
      final status = (p['po_status'] as String? ?? '').toLowerCase();
      final spent = status == 'used' || status == 'closed';
      final issuer = (p['issued_by'] as String? ?? '').trim();

      // Manpower is contracted in days, so a rupee balance on its own does not
      // say whether the PO is nearly out of days. Days invoiced are derived
      // from the invoices raised — deliberately not from days worked, which
      // nothing here records and which can run well ahead of billing.
      final days = (p['manpower_days'] as num?)?.toDouble() ?? 0;
      final dayRate = days > 0 ? base / days : 0.0;
      final daysBilled = dayRate > 0 ? drawnExcl / dayRate : 0.0;
      final usedDays =
          ((p['manpower_days_opening'] as num?)?.toDouble() ?? 0) +
              ((p['man_days_mustered'] as num?)?.toDouble() ?? 0);
      final unbilledDays = usedDays - daysBilled;
      final manpowerLine = category != 'manpower'
          ? ''
          : days <= 0
              ? '<br><span style="color:#b26a00;font-size:11px;">'
                  'Manpower days not recorded</span>'
              : '<br><span style="color:#3d4757;font-size:11px;font-weight:600;">'
                  '${_trimNum(usedDays)} of ${_trimNum(days)} manpower days '
                  'used${dayRate > 0 ? ' @ ${_inr(dayRate)}/day' : ''} · '
                  '${_trimNum(days - usedDays)} left'
                  '</span>'
                  '${unbilledDays >= 1 ? '<br><span style="color:#b26a00;font-size:11px;">'
                      '${_trimNum(unbilledDays)} days worked but not invoiced'
                      '${dayRate > 0 ? ' — ${_inr(unbilledDays * dayRate)} ex-GST' : ''}'
                      '</span>' : ''}';

      final head = '<td $td>PO $number'
          '${status == 'upcoming' ? ' <span style="color:#b26a00;font-size:10px;">upcoming</span>' : ''}'
          '${spent ? ' <span style="color:#6b7490;font-size:10px;">consumed</span>' : ''}'
          '${issuer.isEmpty ? '' : ' <span style="color:#3d4757;font-size:10px;font-weight:600;">via $issuer</span>'}'
          '$manpowerLine'
          '<br><span style="color:#6b7490;font-size:11px;">'
          '${_truncate(p['description'] as String? ?? '', 80)}</span></td>';

      // A spent PO offers nothing for future booking, whatever value is
      // recorded against it.
      if (spent) {
        return '<tr>$head<td $tdr colspan="3" '
            'style="padding:7px 10px;border-bottom:1px solid #e6e9f0;'
            'font-size:12px;text-align:right;color:#6b7490;">'
            'Fully consumed — no funding remaining'
            '${total > 0 ? ' (${_inr(total)})' : ''}</td></tr>';
      }

      // Recorded but unvalued: say so rather than printing ₹0 of funding.
      if (total <= 0) {
        return '<tr>$head<td $tdr colspan="3" '
            'style="padding:7px 10px;border-bottom:1px solid #e6e9f0;'
            'font-size:12px;text-align:right;color:#b26a00;">'
            'PO value not yet recorded — excluded from the totals above'
            '${drawn > 0 ? ', though ${_inr(drawn)} has been invoiced against it' : ''}'
            '</td></tr>';
      }

      return '<tr>$head'
          '<td $tdr>${_inr(total)}'
          '<br><span style="color:#6b7490;font-size:10px;">'
          '${_inr(base)} ex-GST</span></td>'
          '<td $tdr>${_inr(drawn)}'
          '<span style="color:#6b7490;font-size:10px;"> (${pct.toStringAsFixed(0)}%)</span></td>'
          '<td $tdr style="color:${left < 0 ? '#c62828' : '#1a7f37'};">'
          '<b>${_inr(left)}</b>'
          '<br><span style="color:#6b7490;font-size:10px;font-weight:400;">'
          '${_inr(leftExcl)} ex-GST</span></td></tr>';
      }).join();
      return '$block$rows';
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

    // Work that is done but unbilled was still booked against a PO — the first
    // track PO, which is what it will draw on when NATRAX raises the invoice.
    // Naming it matters: that PO is the one with the least headroom left.
    String firstTrackPo = '';
    for (final p in pos) {
      if ((p['category'] as String? ?? '').toLowerCase() != 'track_booking') {
        continue;
      }
      final n = (p['po_number'] as String? ?? '').trim();
      if (n.isNotEmpty) {
        firstTrackPo = n;
        break;
      }
    }

    final unbilledRows = unbilled.isEmpty
        ? '<tr><td $td colspan="2" style="color:#1a7f37;">Everything billed to date</td></tr>'
        : unbilled
            .map((m) => '<tr><td $td>${_monthLabel(m.month)} '
                '<span style="color:#6b7490;font-size:11px;">(computed, not invoiced'
                '${firstTrackPo.isEmpty ? '' : ' — will draw on PO $firstTrackPo'}'
                ')</span></td>'
                '<td $tdr>${_inr(m.inclGst)}</td></tr>')
            .join();

    // Manpower pends separately from track: worked ahead of billing, on its
    // own POs. Blending the two into one "not yet billed" figure hides which
    // invoice to chase — NATRAX and MOICARS are different conversations.
    final pending = _manpowerPending(pos, byPoExcl);
    final manpowerPending =
        pending.fold<double>(0, (s, e) => s + e.amountInclGst);
    final manpowerPendingRows = pending.isEmpty
        ? '<tr><td $td colspan="2" style="color:#1a7f37;">'
            'Nothing outstanding</td></tr>'
        : pending
            .map((e) => '<tr><td $td>PO ${e.poNumber} '
                '<span style="color:#6b7490;font-size:11px;">'
                '(${_trimNum(e.days)} man-days worked, not invoiced)</span></td>'
                '<td $tdr>${_inr(e.amountInclGst)}</td></tr>')
            .join();

    // Workshop is booked by the day and billed monthly, so the day count is
    // the number that says whether the bay is being held longer than it is
    // being used. Derived from the rental, never stored alongside it.
    final workshopMonths = baseline.where((m) => m.workshopRental > 0).toList();
    final workshopDays =
        workshopMonths.fold<double>(0, (s, m) => s + m.workshopDays);
    final workshopCost =
        workshopMonths.fold<double>(0, (s, m) => s + m.workshopRental);
    // The bay is currently held on an open period that has not been invoiced,
    // so it accrues rather than sitting in a closed month.
    final openDays = BillingBaseline.openWorkshopDays(asOn);
    final openRental = BillingBaseline.openWorkshopRental(asOn);
    final workshopDaysAll = workshopDays + openDays;
    final workshopCostAll = workshopCost + openRental;

    final workshopRows = (workshopMonths.isEmpty && openDays == 0)
        ? '<tr><td $td colspan="3">No workshop rental recorded</td></tr>'
        : workshopMonths
                .map((m) => '<tr><td $td>${_monthLabel(m.month)}</td>'
                    '<td $tdr>${_trimNum(m.workshopDays)}</td>'
                    '<td $tdr>${_inr(m.workshopRental)}</td></tr>')
                .join() +
            (openDays == 0
                ? ''
                : '<tr><td $td>Since '
                    '${_fmtDate(BillingBaseline.workshopResumedOn)} '
                    '<span style="color:#6b7490;font-size:11px;">'
                    '(open, not invoiced)</span></td>'
                    '<td $tdr>$openDays</td>'
                    '<td $tdr>${_inr(openRental)}</td></tr>');

    final trackRows = tracks.isEmpty
        ? '<tr><td $td colspan="3">No sessions logged</td></tr>'
        : tracks.map((t) {
            final pct = totalHours <= 0 ? 0.0 : t.value / totalHours * 100;
            return '<tr><td $td>${t.key}</td>'
                '<td $tdr>${t.value.toStringAsFixed(1)} h</td>'
                '<td $tdr>${pct.toStringAsFixed(0)}%</td></tr>';
          }).join();

    // The section appears only once resources are actually allocated to
    // something. Until then it is all zeros, and a table of zeros in a
    // management update is worse than no table — it invites the question
    // "so what?" and answers it with nothing. Hours logged against sessions
    // are already reported under track utilisation.
    final allocated =
        resources.where((r) => r.allocatedHours > 0).toList();

    // Numbered rows with an amber rule, rather than a bullet list — Outlook's
    // list indentation is unreliable and these are the lines most likely to be
    // read.
    final attentionItems = attention.isEmpty
        ? '<tr><td style="padding:8px 0;font-size:13px;color:#1a7f37;">'
            'Nothing outstanding.</td></tr>'
        : attention.asMap().entries.map((e) => '''
<tr><td style="padding:0 0 9px;">
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
         style="border-collapse:collapse;background:#fffaf2;
                border-left:3px solid #e8a33d;">
  <tr>
    <td width="26" valign="top" align="center"
        style="padding:10px 0 10px 8px;font-size:12px;font-weight:700;color:#b26a00;">
      ${e.key + 1}</td>
    <td style="padding:10px 12px 10px 4px;font-size:12.5px;color:#3d4757;
               line-height:1.55;">${e.value}</td>
  </tr></table>
</td></tr>''').join();

    // Utilisation bar, drawn with table cells rather than a div — Outlook
    // renders with Word's engine, which ignores width on styled divs.
    final barUsed = (utilisationPct * 100).clamp(0, 100).round();
    final barLeft = 100 - barUsed;
    final bar = '''
<table role="presentation" cellpadding="0" cellspacing="0" border="0"
       width="100%" style="border-collapse:collapse;height:8px;">
<tr>
${barUsed > 0 ? '<td width="$barUsed%" bgcolor="#0057e6" style="height:8px;line-height:8px;font-size:0;">&nbsp;</td>' : ''}
${barLeft > 0 ? '<td width="$barLeft%" bgcolor="#dbe2ec" style="height:8px;line-height:8px;font-size:0;">&nbsp;</td>' : ''}
</tr></table>''';

    String kpi(String label, String value, String sub, String colour) => '''
<td width="33%" valign="top" style="padding:0 6px;">
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
         style="border-collapse:collapse;background:#ffffff;border:1px solid #e2e7ef;">
  <tr><td style="padding:13px 14px;">
    <div style="font-size:10px;letter-spacing:.7px;text-transform:uppercase;
                color:#7a8699;font-weight:700;">$label</div>
    <div style="font-size:20px;font-weight:700;color:$colour;padding-top:5px;
                white-space:nowrap;">$value</div>
    <div style="font-size:11px;color:#7a8699;padding-top:3px;">$sub</div>
  </td></tr></table>
</td>''';

    String section(String title, String body, {String? note}) => '''
<tr><td style="padding:24px 26px 0;">
  <div style="font-size:13px;font-weight:700;color:#0a1f44;
              border-bottom:2px solid #0057e6;display:inline-block;
              padding-bottom:3px;margin-bottom:10px;">$title</div>
  $body
  ${note == null ? '' : '<div style="font-size:11px;color:#7a8699;padding-top:6px;line-height:1.5;">$note</div>'}
</td></tr>''';

    final resourceSection = allocated.isEmpty
        ? ''
        : section(
            'Testing resources',
            '''
<table cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;">
<tr><th $th>Resource</th><th $th>Role</th>
<th $th style="text-align:right">Available</th>
<th $th style="text-align:right">Allocated</th>
<th $th style="text-align:right">Utilised</th></tr>
${allocated.map((r) {
            final warn = r.isOverAllocated;
            return '<tr><td $td>${r.resource.name}'
                '${r.utilisationFromSessions ? '' : '<span style="color:#7a8699;font-size:11px;"> (manual)</span>'}</td>'
                '<td $td>${r.resource.roleTitle ?? r.resource.type}</td>'
                '<td $tdr>${r.availableHours.toStringAsFixed(0)} h</td>'
                '<td $tdr${warn ? ' bgcolor="#fff5e6"' : ''}>${r.allocatedHours.toStringAsFixed(0)} h</td>'
                '<td $tdr>${r.utilisedHours.toStringAsFixed(1)} h '
                '<span style="color:#7a8699;font-size:10px;">'
                '(${(r.utilisationRate * 100).toStringAsFixed(0)}%)</span></td></tr>';
          }).join()}
</table>''',
            note: 'Utilised comes from logged sessions for test engineers; '
                'rows marked (manual) use hours recorded against the allocation.',
          );

    return '''
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;background:#eef1f6;
              font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<tr><td align="center" style="padding:22px 12px;">

<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="720"
       style="border-collapse:collapse;max-width:720px;background:#ffffff;
              border:1px solid #dfe4ec;">

<!-- Header -->
<tr><td bgcolor="#0a1f44" style="padding:22px 26px;">
  <div style="font-size:18px;font-weight:700;color:#ffffff;letter-spacing:.2px;">
    NATRAX Proving Ground &mdash; SightLine Validation</div>
  <div style="font-size:12px;color:#9fb0cc;padding-top:4px;">
    Goodyear SightLine tire intelligence validation, Indore</div>
  <div style="font-size:12px;color:#ffffff;padding-top:10px;font-weight:600;">
    PO &amp; expense status as on ${_fmtDate(asOn)}</div>
</td></tr>

<!-- Greeting and lead. The report opened straight onto a wall of figures,
     which reads as a pasted dashboard rather than a mail to a person. -->
<tr><td style="padding:20px 26px 0;">
  <div style="font-size:14px;color:#1f2733;">Hi $recipientName,</div>
  <div style="font-size:13px;color:#3d4757;line-height:1.65;padding-top:9px;">
    Here is the PO and expense position for
    ${vehicleName == null || vehicleName.isEmpty ? projectName : '$projectName ($vehicleName)'}
    at NATRAX as on ${_fmtDate(asOn)}.
    ${_inr(invoicedTotal)} has been invoiced against ${_inr(poTotal)} of funded
    purchase orders, leaving <b>${_inr(balance)}</b> available to book.${unbilledTotal > 0 ? '''
    A further ${_inr(unbilledTotal)} of completed work is not yet invoiced and
    is shown separately — it does not reduce the balance until NATRAX raises
    it.''' : ''}${attention.isEmpty ? '' : '''
    ${attention.length == 1 ? 'One point needs' : '${attention.length} points need'}
    attention; these are set out at the end.'''}
  </div>
</td></tr>

<!-- Headline numbers -->
<tr><td style="padding:16px 20px 4px;">
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
         style="border-collapse:collapse;">
  <tr>
    ${kpi('Total PO value', _inr(poTotal), '${_inr(poTotalExcl)} ex-GST', '#0a1f44')}
    ${kpi('Invoiced to date', _inr(invoicedTotal), '${_inr(invoicedTotalExcl)} ex-GST', '#0a1f44')}
    ${kpi('Available to book', _inr(balance), '${_inr(balanceExcl)} ex-GST', balance < 0 ? '#c62828' : '#1a7f37')}
  </tr></table>
</td></tr>

<!-- Utilisation bar -->
<tr><td style="padding:12px 26px 0;">
  $bar
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
         style="border-collapse:collapse;padding-top:5px;">
  <tr>
    <td style="font-size:11px;color:#7a8699;padding-top:5px;">
      $barUsed% of funded POs invoiced</td>
    <td align="right" style="font-size:11px;color:#7a8699;padding-top:5px;">
      ${(projectedPct * 100).toStringAsFixed(0)}% once unbilled work is raised</td>
  </tr></table>
</td></tr>

${section('Purchase orders', '''
<table cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;">
<tr><th $th>PO / purpose</th><th $th style="text-align:right">PO value</th>
<th $th style="text-align:right">Invoiced</th>
<th $th style="text-align:right">Available</th></tr>
$poRows
$orphanRow
</table>''', note: "Each invoice is attributed to the PO it names (Buyer's Order "
        'No.), so track booking and manpower draw on their own POs.')}

${section('Invoices raised', '''
<table cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;">
<tr><th $th>Invoice</th><th $th>Dated</th><th $th>Billing period</th>
<th $th style="text-align:right">Amount</th></tr>
$invoiceRows
<tr><td $td colspan="3" style="padding:8px 10px;background:#f6f8fb;">
  <b>Total invoiced</b></td>
<td $tdr style="padding:8px 10px;background:#f6f8fb;">
  <b>${_inr(invoicedTotal)}</b></td></tr>
</table>''', note: 'Originals are on file and verified against our session records.')}

${section('Not yet billed', '''
<table cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;">
<tr><td colspan="2"
        style="padding:9px 10px 4px;font-size:11px;font-weight:700;
               color:#0057e6;letter-spacing:.5px;
               border-bottom:1px solid #e6e9f0;">
  TRACK &amp; WORKSHOP${firstTrackPo.isEmpty ? '' : ' — PO $firstTrackPo'}</td></tr>
$unbilledRows
<tr><td $td style="padding:7px 10px;"><i>Track subtotal</i></td>
<td $tdr style="padding:7px 10px;"><i>${_inr(unbilledTotal)}</i></td></tr>

<tr><td colspan="2"
        style="padding:12px 10px 4px;font-size:11px;font-weight:700;
               color:#0057e6;letter-spacing:.5px;
               border-bottom:1px solid #e6e9f0;">
  MANPOWER</td></tr>
$manpowerPendingRows
<tr><td $td style="padding:7px 10px;"><i>Manpower subtotal</i></td>
<td $tdr style="padding:7px 10px;"><i>${_inr(manpowerPending)}</i></td></tr>

<tr><td $td style="padding:8px 10px;background:#f6f8fb;">
  <b>Committed but not invoiced</b></td>
<td $tdr style="padding:8px 10px;background:#f6f8fb;">
  <b>${_inr(unbilledTotal + manpowerPending)}</b></td></tr>
</table>''', note: 'Split by stream because the two are chased separately — '
        'track and workshop from NATRAX, manpower from MOICARS. None of it is '
        'deducted from the available balance above: a PO is drawn down by '
        'invoices, so this becomes drawdown only when the invoice is raised.')}

${section('Workshop rental', '''
<table cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;">
<tr><th $th>Month</th><th $th style="text-align:right">Days</th>
<th $th style="text-align:right">Rental</th></tr>
$workshopRows
<tr><td $td style="padding:8px 10px;background:#f6f8fb;">
  <b>Total</b></td>
<td $tdr style="padding:8px 10px;background:#f6f8fb;">
  <b>${_trimNum(workshopDaysAll)} days</b></td>
<td $tdr style="padding:8px 10px;background:#f6f8fb;">
  <b>${_inr(workshopCostAll)}</b></td></tr>
</table>''', note: 'Charged at ${_inr(BillingBaseline.workshopDayRate)} per '
        'operational day on the Continuous Workshop Flat Rate. June and July '
        'carry no rental — the bay was released over the pause and re-occupied '
        'on ${_fmtDate(BillingBaseline.workshopResumedOn)}, so that period is '
        'still accruing and not yet invoiced.')}

${section('Track utilisation', '''
<div style="font-size:13px;color:#3d4757;padding-bottom:8px;">
  <b>${totalHours.toStringAsFixed(1)} hours</b> across
  <b>$sessionCount sessions</b></div>
<table cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;">
<tr><th $th>Track</th><th $th style="text-align:right">Hours</th>
<th $th style="text-align:right">Share</th></tr>
$trackRows
</table>''')}

$resourceSection

${section('Points needing attention', '''
<table cellpadding="0" cellspacing="0" border="0" width="100%"
       style="border-collapse:collapse;">
$attentionItems
</table>''')}

<!-- Close. No name or sign-off: Outlook adds the signature, and a second one
     inside the card reads as a duplicate. -->
<tr><td style="padding:4px 26px 0;">
  <div style="font-size:13px;color:#3d4757;line-height:1.65;">
    Every figure above is reconciled against the invoices on file; happy to walk
    through any part of it.
  </div>
</td></tr>

<!-- Footer -->
<tr><td style="padding:18px 26px 24px;">
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
         style="border-collapse:collapse;border-top:1px solid #e2e7ef;">
  <tr><td style="padding-top:14px;font-size:11px;color:#7a8699;line-height:1.6;">
    Live dashboard:
    <a href="https://sightlinevalidation.web.app"
       style="color:#0057e6;text-decoration:none;">sightlinevalidation.web.app</a><br>
    Generated by TrackLog on ${_fmtDate(asOn)}. Figures marked
    <i>computed</i> are derived from session records and rate cards; all other
    amounts come from invoices raised by NATRAX.
  </td></tr></table>
</td></tr>

</table>
</td></tr></table>''';
  }

  /// A compact readable version for the compose window, before the formatted
  /// report is pasted over it. Kept short — mailto bodies get truncated.
  static String _pad(String s) => s.padRight(15);

  String _plainText({
    required String projectName,
    required DateTime asOn,
    required List<Map<String, dynamic>> pos,
    required Map<String, double> byPo,
    required double poTotal,
    required double poTotalExcl,
    required double invoicedTotal,
    required double invoicedTotalExcl,
    required double balance,
    required double balanceExcl,
    required double unbilledTotal,
    required double manpowerPending,
    required double projected,
    required List<String> attention,
  }) {
    final b = StringBuffer()
      ..writeln('NATRAX Proving Ground — SightLine Validation')
      ..writeln('Status as on ${_fmtDate(asOn)}')
      ..writeln()
      ..writeln('PO POSITION                 ex-GST         incl. GST')
      ..writeln('  Total PO value      ${_pad(_inr(poTotalExcl))} '
          '${_inr(poTotal)}')
      ..writeln('  Invoiced to date    ${_pad(_inr(invoicedTotalExcl))} '
          '${_inr(invoicedTotal)}')
      ..writeln('  Available to book   ${_pad(_inr(balanceExcl))} '
          '${_inr(balance)}');

    if (unbilledTotal > 0 || manpowerPending > 0) {
      b
        ..writeln()
        ..writeln('NOT YET BILLED')
        ..writeln('  ${_pad('Track & workshop')}${_inr(unbilledTotal)} (computed)')
        ..writeln('  ${_pad('Manpower')}${_inr(manpowerPending)} (mustered, '
            'not invoiced)')
        ..writeln('  ${_pad('Total')}${_inr(unbilledTotal + manpowerPending)}')
        ..writeln('  Chased separately — track and workshop from NATRAX, '
            'manpower from MOICARS.')
        ..writeln('  None of it is deducted from the balance above; it draws '
            'down only when invoiced.');
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
        final category = (p['category'] as String? ?? 'other').toLowerCase();
        final cat = _categoryLabel(category).toLowerCase();
        final days = (p['manpower_days'] as num?)?.toDouble() ?? 0;
        final dayNote = category != 'manpower'
            ? ''
            : days > 0
                ? ', ${_trimNum(days)} manpower days'
                : ', manpower days not recorded';
        b.writeln(total <= 0
            ? '  PO $number ($cat$dayNote) — value not yet recorded, excluded '
                'from the totals above'
            : '  PO $number ($cat$dayNote) — invoiced ${_inr(drawn)} of '
                '${_inr(total)}, balance ${_inr(total - drawn)}');
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

  /// Day counts are whole in practice but stored as a number; drop the ".0"
  /// without losing a genuine half-day.
  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Manpower worked but not yet invoiced, per PO.
  ///
  /// One implementation, because three places report it — the HTML table, the
  /// plain-text fallback and the attention list — and a manpower figure that
  /// disagreed with itself between them would be worse than not showing it.
  ///
  /// Days billed are inferred from invoiced value at the PO's own day rate;
  /// days worked come from the muster. Only whole days of gap are reported, so
  /// rounding noise never surfaces as a spurious liability.
  static List<({String poNumber, double days, double amountInclGst})>
      _manpowerPending(
    List<Map<String, dynamic>> pos,
    Map<String, double> invoicedExclByPo,
  ) {
    final out = <({String poNumber, double days, double amountInclGst})>[];
    for (final p in pos) {
      if ((p['category'] as String? ?? '').toLowerCase() != 'manpower') continue;
      final number = (p['po_number'] as String? ?? '').trim();
      final base = (p['total_po_value'] as num?)?.toDouble() ?? 0;
      final contracted = (p['manpower_days'] as num?)?.toDouble() ?? 0;
      if (base <= 0 || contracted <= 0) continue;

      final rate = base / contracted;
      final billedDays = (invoicedExclByPo[number] ?? 0) / rate;
      // Days worked before the muster existed are carried on the PO, so
      // consumption is the two together.
      final used = ((p['manpower_days_opening'] as num?)?.toDouble() ?? 0) +
          ((p['man_days_mustered'] as num?)?.toDouble() ?? 0);
      final gap = used - billedDays;
      if (gap < 1) continue;

      // Grossed up on the PO's own tax, which need not match the track rate.
      final tax = (p['tax_amount'] as num?)?.toDouble() ?? 0;
      out.add((
        poNumber: number,
        days: gap,
        amountInclGst: gap * rate * (1 + tax / base),
      ));
    }
    return out;
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
