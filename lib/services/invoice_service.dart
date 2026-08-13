import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// One original invoice raised by NATRAX, plus the PDF stored alongside it.
///
/// The amounts here are what is *printed on the invoice* — they are the source
/// of truth the PO balance is reconciled against, as opposed to the costs the
/// app derives from session durations and rate cards.
class NatraxInvoice {
  final String id;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final String? periodMonth; // 'YYYY-MM'
  final String projectName;
  final String? poNumber;
  final double amountExclGst;
  final double gstAmount;
  final double totalAmount;
  final String? notes;
  final String? fileName;
  final String? storagePath;
  final int? fileSizeBytes;
  final String? uploadedBy;
  final DateTime? createdAt;

  const NatraxInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.projectName,
    this.invoiceDate,
    this.periodMonth,
    this.poNumber,
    this.amountExclGst = 0,
    this.gstAmount = 0,
    this.totalAmount = 0,
    this.notes,
    this.fileName,
    this.storagePath,
    this.fileSizeBytes,
    this.uploadedBy,
    this.createdAt,
  });

  bool get hasFile => (storagePath ?? '').isNotEmpty;

  /// True when excl + GST does not add up to the stated total — a typo guard
  /// so a mis-keyed invoice cannot silently distort the reconciliation.
  bool get isInternallyInconsistent =>
      (amountExclGst + gstAmount - totalAmount).abs() > 1.0;

  factory NatraxInvoice.fromJson(Map<String, dynamic> j) => NatraxInvoice(
        id: j['id'] as String,
        invoiceNumber: j['invoice_number'] as String? ?? '',
        invoiceDate: DateTime.tryParse(j['invoice_date'] as String? ?? ''),
        periodMonth: j['period_month'] as String?,
        projectName: j['project_name'] as String? ?? '',
        poNumber: j['po_number'] as String?,
        amountExclGst: (j['amount_excl_gst'] as num?)?.toDouble() ?? 0,
        gstAmount: (j['gst_amount'] as num?)?.toDouble() ?? 0,
        totalAmount: (j['total_amount'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String?,
        fileName: j['file_name'] as String?,
        storagePath: j['storage_path'] as String?,
        fileSizeBytes: (j['file_size_bytes'] as num?)?.toInt(),
        uploadedBy: j['uploaded_by'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );
}

class InvoiceService {
  static InvoiceService? _instance;
  static InvoiceService get instance => _instance ??= InvoiceService._();
  InvoiceService._();

  static const String bucket = 'natrax-invoices';

  SupabaseClient get _client => SupabaseService.instance.client;

  /// All invoices, newest period first. Pass [projectName] to scope to one PoC.
  Future<List<NatraxInvoice>> list({String? projectName}) async {
    var query = _client.from('natrax_invoices').select();
    if (projectName != null && projectName.isNotEmpty) {
      query = query.eq('project_name', projectName);
    }
    final rows = await query.order('invoice_date', ascending: false);
    return (rows as List)
        .map((r) => NatraxInvoice.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Uploads the original PDF and records the amounts printed on it.
  ///
  /// The file is stored under `<project-slug>/<invoice-no>-<timestamp>.<ext>`
  /// so re-uploading a corrected copy never overwrites the previous object.
  Future<NatraxInvoice> upload({
    required String invoiceNumber,
    required String projectName,
    required double amountExclGst,
    required double gstAmount,
    required double totalAmount,
    DateTime? invoiceDate,
    String? periodMonth,
    String? poNumber,
    String? notes,
    Uint8List? fileBytes,
    String? fileName,
    String? uploadedBy,
  }) async {
    String? storagePath;

    if (fileBytes != null && fileName != null && fileName.isNotEmpty) {
      final slug = projectName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final safeInvoice = invoiceNumber
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final ext = fileName.contains('.') ? fileName.split('.').last : 'pdf';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      storagePath = '$slug/${safeInvoice.isEmpty ? 'invoice' : safeInvoice}'
          '-$stamp.$ext';

      await _client.storage.from(bucket).uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: FileOptions(
              contentType: _mimeFor(ext),
              upsert: false,
            ),
          );
    }

    try {
      final inserted = await _client
          .from('natrax_invoices')
          .insert({
            'invoice_number': invoiceNumber,
            'invoice_date': invoiceDate?.toIso8601String().split('T').first,
            'period_month': periodMonth,
            'project_name': projectName,
            'po_number': poNumber,
            'amount_excl_gst': amountExclGst,
            'gst_amount': gstAmount,
            'total_amount': totalAmount,
            'notes': notes,
            'file_name': fileName,
            'storage_path': storagePath,
            'file_size_bytes': fileBytes?.length,
            'uploaded_by': uploadedBy,
          })
          .select()
          .single();
      return NatraxInvoice.fromJson(inserted);
    } catch (e) {
      // Do not leave an orphan object behind if the metadata insert is
      // rejected (duplicate invoice number, RLS, …).
      if (storagePath != null) {
        try {
          await _client.storage.from(bucket).remove([storagePath]);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Short-lived link for viewing an original in the browser / PDF viewer.
  Future<String?> signedUrl(NatraxInvoice invoice,
      {Duration validFor = const Duration(minutes: 10)}) async {
    if (!invoice.hasFile) return null;
    return _client.storage
        .from(bucket)
        .createSignedUrl(invoice.storagePath!, validFor.inSeconds);
  }

  Future<Uint8List?> download(NatraxInvoice invoice) async {
    if (!invoice.hasFile) return null;
    return _client.storage.from(bucket).download(invoice.storagePath!);
  }

  Future<void> updateAmounts({
    required String id,
    required double amountExclGst,
    required double gstAmount,
    required double totalAmount,
    String? poNumber,
    String? periodMonth,
    String? notes,
  }) async {
    await _client.from('natrax_invoices').update({
      'amount_excl_gst': amountExclGst,
      'gst_amount': gstAmount,
      'total_amount': totalAmount,
      if (poNumber != null) 'po_number': poNumber,
      if (periodMonth != null) 'period_month': periodMonth,
      if (notes != null) 'notes': notes,
    }).eq('id', id);
  }

  /// Removes the row and its stored PDF.
  Future<void> delete(NatraxInvoice invoice) async {
    await _client.from('natrax_invoices').delete().eq('id', invoice.id);
    if (invoice.hasFile) {
      try {
        await _client.storage.from(bucket).remove([invoice.storagePath!]);
      } catch (_) {
        // Row is gone; a stray object is not worth failing the delete over.
      }
    }
  }

  String _mimeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/pdf';
    }
  }
}

/// Rolled-up invoice totals used by the PO Tracker reconciliation card.
class InvoiceTotals {
  final double exclGst;
  final double gst;
  final double total;
  final int count;
  final Set<String> periods;

  const InvoiceTotals({
    this.exclGst = 0,
    this.gst = 0,
    this.total = 0,
    this.count = 0,
    this.periods = const {},
  });

  factory InvoiceTotals.from(Iterable<NatraxInvoice> invoices) {
    double excl = 0, gst = 0, total = 0;
    final periods = <String>{};
    var count = 0;
    for (final i in invoices) {
      excl += i.amountExclGst;
      gst += i.gstAmount;
      total += i.totalAmount;
      count++;
      final p = i.periodMonth;
      if (p != null && p.isNotEmpty) periods.add(p);
    }
    return InvoiceTotals(
      exclGst: excl,
      gst: gst,
      total: total,
      count: count,
      periods: periods,
    );
  }

  bool get isEmpty => count == 0;
}
