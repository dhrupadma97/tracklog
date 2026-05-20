import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

class EmailReportSubscription {
  final String id;
  final String managerName;
  final String email;
  final String reportType; // 'daily' | 'weekly' | 'both'
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

  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

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
