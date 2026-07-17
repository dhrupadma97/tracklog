import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

class EmailReportSubscription {
  final String id;
  final String managerName;
  final String email;
  final String reportType; // 'monthly' | 'yearly' | 'both'
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastSentAt;

  EmailReportSubscription({
    required this.id,
    required this.managerName,
    required this.email,
    required this.reportType,
    required this.isActive,
    required this.createdAt,
    this.lastSentAt,
  });

  factory EmailReportSubscription.fromJson(Map<String, dynamic> json) {
    return EmailReportSubscription(
      id: json['id'] as String,
      managerName: json['manager_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      reportType: json['report_type'] as String? ?? 'both',
      isActive: json['is_active'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      lastSentAt: json['last_sent_at'] != null
          ? DateTime.tryParse(json['last_sent_at'] as String)
          : null,
    );
  }
}

class EmailSendLog {
  final String id;
  final String recipientEmail;
  final String reportType;
  final String status;
  final String? errorMessage;
  final DateTime sentAt;

  EmailSendLog({
    required this.id,
    required this.recipientEmail,
    required this.reportType,
    required this.status,
    this.errorMessage,
    required this.sentAt,
  });

  factory EmailSendLog.fromJson(Map<String, dynamic> json) {
    return EmailSendLog(
      id: json['id'] as String,
      recipientEmail: json['recipient_email'] as String? ?? '',
      reportType: json['report_type'] as String? ?? '',
      status: json['status'] as String? ?? 'sent',
      errorMessage: json['error_message'] as String?,
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class EmailReportService {
  static EmailReportService? _instance;
  static EmailReportService get instance =>
      _instance ??= EmailReportService._();
  EmailReportService._();

  SupabaseClient get _client => SupabaseService.instance.client;


  // ── Subscriptions ─────────────────────────────────────────────────────────

  Future<List<EmailReportSubscription>> getSubscriptions() async {
    final data = await _client
        .from('email_report_subscriptions')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => EmailReportSubscription.fromJson(e))
        .toList();
  }

  Future<void> addSubscription({
    required String managerName,
    required String email,
    required String reportType,
  }) async {
    final user = _client.auth.currentUser;
    await _client.from('email_report_subscriptions').insert({
      'manager_name': managerName,
      'email': email,
      'report_type': reportType,
      'is_active': true,
      'created_by': user?.id,
    });
  }

  Future<void> toggleSubscription(String id, bool isActive) async {
    await _client
        .from('email_report_subscriptions')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> deleteSubscription(String id) async {
    await _client.from('email_report_subscriptions').delete().eq('id', id);
  }

  // ── Send Report ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendReport({
    required String recipientEmail,
    required String recipientName,
    required String reportType,
    required Map<String, dynamic> poData,
    required Map<String, dynamic> spendBreakdown,
    required List<Map<String, dynamic>> sessionSummary,
    String? subscriptionId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'send-report-email',
        body: {
          'recipientEmail': recipientEmail,
          'recipientName': recipientName,
          'reportType': reportType,
          'poData': poData,
          'spendBreakdown': spendBreakdown,
          'sessionSummary': sessionSummary,
        },
      );

      final data = response.data as Map<String, dynamic>?;
      final success = data?['success'] == true;

      // Log the send attempt
      await _client.from('email_send_log').insert({
        'subscription_id': subscriptionId,
        'recipient_email': recipientEmail,
        'report_type': reportType,
        'status': success ? 'sent' : 'failed',
        'error_message': success ? null : (data?['error'] as String?),
      });

      // Update last_sent_at if subscription exists
      if (subscriptionId != null && success) {
        await _client
            .from('email_report_subscriptions')
            .update({'last_sent_at': DateTime.now().toIso8601String()})
            .eq('id', subscriptionId);
      }

      return {'success': success, 'error': data?['error']};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Send to all active subscribers ───────────────────────────────────────

  Future<Map<String, dynamic>> sendToAllActive({
    required String reportType,
    required Map<String, dynamic> poData,
    required Map<String, dynamic> spendBreakdown,
    required List<Map<String, dynamic>> sessionSummary,
  }) async {
    final subs = await getSubscriptions();
    final activeSubs = subs.where((s) {
      if (!s.isActive) return false;
      if (s.reportType == 'both') return true;
      return s.reportType == reportType;
    }).toList();

    if (activeSubs.isEmpty) {
      return {'sent': 0, 'failed': 0, 'total': 0};
    }

    int sent = 0;
    int failed = 0;

    for (final sub in activeSubs) {
      final result = await sendReport(
        recipientEmail: sub.email,
        recipientName: sub.managerName,
        reportType: reportType,
        poData: poData,
        spendBreakdown: spendBreakdown,
        sessionSummary: sessionSummary,
        subscriptionId: sub.id,
      );
      if (result['success'] == true) {
        sent++;
      } else {
        failed++;
      }
    }

    return {'sent': sent, 'failed': failed, 'total': activeSubs.length};
  }

  // ── NATRAX VBA-style Expense Report ─────────────────────────────────────

  /// Generate the HTML + computed data WITHOUT sending.
  /// Use this for preview. Call [sendNatraxExpenseReport] to actually send.
  Future<Map<String, dynamic>> generateNatraxReportData({
    required String reportType,
    required String vehicleName,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime overallStart,
    required DateTime overallEnd,
  }) async {
    final client = SupabaseService.instance.client;

    final sessionsRaw = await client
        .from('engineer_sessions')
        .select('id, track_code, track_name, started_at, duration_minutes, total_cost')
        .eq('session_status', 'completed')
        .order('started_at');

    final Map<String, double> svcMap = {};

    double pTrack = 0, pAcc = 0;
    final Map<String, double> periodTrackHrs = {};
    final int periodDays = periodEnd.difference(periodStart).inDays + 1;

    for (final s in sessionsRaw as List) {
      final dt = DateTime.tryParse(s['started_at'] as String? ?? '');
      if (dt == null) continue;
      final cost = (s['total_cost'] as num?)?.toDouble() ?? 0;
      final id = s['id'] as String? ?? '';
      final trackCode = s['track_code'] as String? ?? 'Unknown';
      final durationHrs = ((s['duration_minutes'] as int? ?? 0) / 60.0);

      if (!dt.isBefore(periodStart) && !dt.isAfter(periodEnd)) {
        pTrack += cost;
        pAcc += svcMap[id] ?? 0;
        periodTrackHrs[trackCode] = (periodTrackHrs[trackCode] ?? 0) + durationHrs;
      }
    }

    final double pWork = periodDays * 5000.0;
    final double pSub = pTrack + pAcc + pWork;
    final double pTotal = pSub * 1.18;

    double oTrack = 0, oAcc = 0;
    final Set<String> activeDaySet = {};
    final int overallDays = overallEnd.difference(overallStart).inDays + 1;

    for (final s in sessionsRaw) {
      final dt = DateTime.tryParse(s['started_at'] as String? ?? '');
      if (dt == null) continue;
      if (!dt.isBefore(overallStart) && !dt.isAfter(overallEnd)) {
        oTrack += (s['total_cost'] as num?)?.toDouble() ?? 0;
        activeDaySet.add('${dt.year}-${dt.month}-${dt.day}');
      }
    }
    final int activeDays = activeDaySet.length;
    final double oWork = overallDays * 5000.0;
    final double oSub = oTrack + oAcc + oWork;
    final double oTotal = oSub * 1.18;

    String trackRows = periodTrackHrs.isEmpty
        ? 'No track data logged for this period'
        : periodTrackHrs.entries.map((e) =>
            '• ${e.key}: <b>${e.value.toStringAsFixed(1)} Hrs</b><br>').join();

    String periodLabel = reportType == 'weekly'
        ? 'WEEKLY UPDATE (${_fmtDate(periodStart)} to ${_fmtDate(periodEnd)})'
        : 'MONTHLY UPDATE — ${_monthYear(periodStart)}';

    String subject = reportType == 'weekly'
        ? 'Weekly Test track costs - $vehicleName (${_fmtDate(periodStart)} to ${_fmtDate(periodEnd)})'
        : 'Monthly Test track costs - $vehicleName (${_monthYear(periodStart)})';

    final html = _buildNatraxHtml(
      periodLabel: periodLabel,
      vehicleName: vehicleName,
      trackRows: trackRows,
      pTrack: pTrack, pAcc: pAcc, pWork: pWork,
      periodDays: periodDays, pSub: pSub, pTotal: pTotal,
      overallStart: overallStart, overallEnd: overallEnd,
      activeDays: activeDays, oTrack: oTrack, oAcc: oAcc,
      oWork: oWork, overallDays: overallDays, oSub: oSub, oTotal: oTotal,
    );

    return {
      'html': html,
      'subject': subject,
      'periodLabel': periodLabel,
      'pTotal': pTotal, 'pSub': pSub, 'pTrack': pTrack, 'pAcc': pAcc,
      'pWork': pWork, 'periodDays': periodDays, 'trackRows': trackRows,
      'oTotal': oTotal, 'oSub': oSub, 'oTrack': oTrack, 'oAcc': oAcc,
      'oWork': oWork, 'overallDays': overallDays, 'activeDays': activeDays,
      'vehicleName': vehicleName, 'reportType': reportType,
    };
  }

  /// Mirrors the VBA SendExpenseUpdateEmail macro.
  /// Builds a dual-table HTML body and sends via the edge function.
  Future<Map<String, dynamic>> sendNatraxExpenseReport({
    required String reportType, // 'weekly' | 'monthly'
    required String vehicleName,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime overallStart,
    required DateTime overallEnd,
    String? customToEmail,
    List<String>? customCcEmails,
    String? customHtmlBody,
  }) async {
    try {
      final client = SupabaseService.instance.client;

      // --- Fetch all completed sessions ---
      final sessionsRaw = await client
          .from('engineer_sessions')
          .select('track_code, track_name, started_at, duration_minutes, total_cost')
          .eq('session_status', 'completed')
          .order('started_at');

      // --- Fetch additional services ---
      final sessionIds = (sessionsRaw as List).map((s) => s['id'] as String? ?? '').where((id) => id.isNotEmpty).toList();
      List svcRaw = [];
      if (sessionIds.isNotEmpty) {
        svcRaw = await client
            .from('session_additional_services')
            .select('session_id, total_cost');
      }
      final Map<String, double> svcMap = {};
      for (final s in svcRaw) {
        final sid = s['session_id'] as String;
        svcMap[sid] = (svcMap[sid] ?? 0) + ((s['total_cost'] as num?)?.toDouble() ?? 0);
      }

      // --- Period aggregation ---
      double pTrack = 0, pAcc = 0;
      final Map<String, double> periodTrackHrs = {};
      int periodDays = periodEnd.difference(periodStart).inDays + 1;

      for (final s in sessionsRaw) {
        final dt = DateTime.tryParse(s['started_at'] as String? ?? '');
        if (dt == null) continue;
        final cost = (s['total_cost'] as num?)?.toDouble() ?? 0;
        final id = s['id'] as String? ?? '';
        final accCost = svcMap[id] ?? 0;
        final trackCode = s['track_code'] as String? ?? 'Unknown';
        final durationHrs = ((s['duration_minutes'] as int? ?? 0) / 60.0);

        if (!dt.isBefore(periodStart) && !dt.isAfter(periodEnd)) {
          pTrack += cost;
          pAcc += accCost;
          periodTrackHrs[trackCode] = (periodTrackHrs[trackCode] ?? 0) + durationHrs;
        }
      }

      final double pWork = periodDays * 5000.0;
      final double pSub = pTrack + pAcc + pWork;
      final double pTotal = pSub * 1.18;

      // --- Overall aggregation ---
      double oTrack = 0, oAcc = 0;
      int activeDays = 0;
      int overallDays = overallEnd.difference(overallStart).inDays + 1;
      final Set<String> activeDaySet = {};

      for (final s in sessionsRaw) {
        final dt = DateTime.tryParse(s['started_at'] as String? ?? '');
        if (dt == null) continue;
        if (!dt.isBefore(overallStart) && !dt.isAfter(overallEnd)) {
          final cost = (s['total_cost'] as num?)?.toDouble() ?? 0;
          final id = s['id'] as String? ?? '';
          oTrack += cost;
          oAcc += svcMap[id] ?? 0;
          activeDaySet.add('${dt.year}-${dt.month}-${dt.day}');
        }
      }
      activeDays = activeDaySet.length;
      final double oWork = overallDays * 5000.0;
      final double oSub = oTrack + oAcc + oWork;
      final double oTotal = oSub * 1.18;

      // --- Build period label ---
      String periodLabel;
      if (reportType == 'weekly') {
        periodLabel = 'WEEKLY UPDATE (${_fmtDate(periodStart)} to ${_fmtDate(periodEnd)})';
      } else {
        periodLabel = 'MONTHLY UPDATE — ${_monthYear(periodStart)}';
      }

      // --- Track breakdown HTML ---
      String trackRows = '';
      if (periodTrackHrs.isEmpty) {
        trackRows = 'No track data logged';
      } else {
        periodTrackHrs.forEach((code, hrs) {
          trackRows += '• $code: <b>${hrs.toStringAsFixed(1)} Hrs</b><br>';
        });
      }

      // --- Build HTML matching VBA exactly ---
      final html = customHtmlBody ?? _buildNatraxHtml(
        periodLabel: periodLabel,
        vehicleName: vehicleName,
        trackRows: trackRows,
        pTrack: pTrack, pAcc: pAcc, pWork: pWork,
        periodDays: periodDays, pSub: pSub, pTotal: pTotal,
        overallStart: overallStart, overallEnd: overallEnd,
        activeDays: activeDays, oTrack: oTrack, oAcc: oAcc,
        oWork: oWork, overallDays: overallDays, oSub: oSub, oTotal: oTotal,
      );

      final toEmail = customToEmail ?? 'praharshithkumar_komaragiri@goodyear.com';
      final ccEmails = customCcEmails ?? ['v_vimal@goodyear.com', 'ashish_pandit@goodyear.com',
                   'yeswanth_golla@goodyear.com', 'niranjan_poloju@goodyear.com'];

      // --- Call edge function ---
      final response = await _client.functions.invoke(
        'send-report-email',
        body: {
          'recipientEmail': toEmail,
          'recipientName': 'Harsh',
          'ccEmails': ccEmails,
          'subject': reportType == 'weekly'
              ? 'Weekly Test track costs - $vehicleName (${_fmtDate(periodStart)} to ${_fmtDate(periodEnd)})'
              : 'Monthly Test track costs - $vehicleName (${_monthYear(periodStart)})',
          'htmlBody': html,
          'reportType': reportType,
          'poData': {},
          'spendBreakdown': {'trackSessions': pTrack, 'additionalServices': pAcc, 'workshopRent': pWork},
          'sessionSummary': [],
        },
      );

      final data = response.data as Map<String, dynamic>?;
      final success = data?['success'] == true;

      await _client.from('email_send_log').insert({
        'recipient_email': toEmail,
        'report_type': reportType,
        'status': success ? 'sent' : 'failed',
        'error_message': success ? null : (data?['error'] as String?),
      });

      return {'success': success, 'html': html, 'error': data?['error']};
    } catch (e) {
      return {'success': false, 'html': '', 'error': e.toString()};
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${_monthName3(d.month)}-${d.year.toString().substring(2)}';

  String _monthYear(DateTime d) => '${_monthNameFull(d.month)} ${d.year}'.toUpperCase();

  String _monthName3(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
  String _monthNameFull(int m) => ['January','February','March','April','May','June','July','August','September','October','November','December'][m - 1];

  String _inr(double v) {
    final formatted = v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{2})+(?!\d))'), (m) => '${m[1]},');
    return 'INR $formatted.00';
  }

  String _buildNatraxHtml({
    required String periodLabel, required String vehicleName,
    required String trackRows,
    required double pTrack, required double pAcc, required double pWork,
    required int periodDays, required double pSub, required double pTotal,
    required DateTime overallStart, required DateTime overallEnd,
    required int activeDays, required double oTrack, required double oAcc,
    required double oWork, required int overallDays,
    required double oSub, required double oTotal,
  }) {
    final ts = DateTime.now();
    final timeStamp = '${ts.day.toString().padLeft(2,'0')}-${_monthName3(ts.month)}-${ts.year} '
        '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}';

    return '''Dear Harsh,<br><br>
Please find the NATRAX expense update for <b>$vehicleName</b> below:<br><br>
<table width="100%" style="border:none;"><tr valign="top">
<td width="48%">
<b>1. $periodLabel</b><br>
<table border="1" cellpadding="8" style="border-collapse:collapse;font-family:Calibri;font-size:14px;text-align:left;width:100%;">
<tr style="background-color:#0070C0;color:white;"><th>Expense Category</th><th>Amount / Detail</th></tr>
<tr style="background-color:#F2F2F2;"><td><b>Detailed Track Breakdown</b></td><td>$trackRows</td></tr>
<tr><td>Track Billing Expenses</td><td>${_inr(pTrack)}</td></tr>
<tr><td>Other Services &amp; Accessories</td><td>${_inr(pAcc)}</td></tr>
<tr><td>Workshop Expense ($periodDays Operational Days)</td><td>${_inr(pWork)}</td></tr>
<tr style="background-color:#FCE4D6;font-weight:bold;"><td>Subtotal (Without GST)</td><td>${_inr(pSub)}</td></tr>
<tr style="background-color:#D9E1F2;font-weight:bold;font-size:15px;"><td>TOTAL (WITH 18% GST)</td><td>${_inr(pTotal)}</td></tr>
</table>
</td><td width="4%"></td><td width="48%">
<b>2. OVERALL EXPENSE (${_fmtDate(overallStart)} to ${_fmtDate(overallEnd)})</b><br>
<table border="1" cellpadding="8" style="border-collapse:collapse;font-family:Calibri;font-size:14px;text-align:left;width:100%;">
<tr style="background-color:#1F4E78;color:white;"><th>Expense Category</th><th>Accumulated Amount</th></tr>
<tr><td><b>Active Testing Days</b></td><td><b>$activeDays Days</b></td></tr>
<tr><td>Total Track Billing</td><td>${_inr(oTrack)}</td></tr>
<tr><td>Total Other Services</td><td>${_inr(oAcc)}</td></tr>
<tr><td>Total Workshop Cost ($overallDays Operational Days)</td><td>${_inr(oWork)}</td></tr>
<tr style="background-color:#FCE4D6;font-weight:bold;"><td>Overall Subtotal (Without GST)</td><td>${_inr(oSub)}</td></tr>
<tr style="background-color:#D9E1F2;font-weight:bold;font-size:15px;"><td>GRAND TOTAL (WITH 18% GST)</td><td>${_inr(oTotal)}</td></tr>
</table>
</td></tr></table><br><br>
Thanks and Regards,<br><b>Dhrupad Mullath Anilkumar</b><br><br>
<p style="color:#595959;font-size:12px;font-style:italic;">Autogenerated Report as on $timeStamp</p>''';
  }

  // ── Send Log ──────────────────────────────────────────────────────────────

  Future<List<EmailSendLog>> getRecentLogs({int limit = 20}) async {
    final data = await _client
        .from('email_send_log')
        .select()
        .order('sent_at', ascending: false)
        .limit(limit);
    return (data as List).map((e) => EmailSendLog.fromJson(e)).toList();
  }
}
