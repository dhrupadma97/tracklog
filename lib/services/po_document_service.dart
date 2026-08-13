import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

import 'supabase_service.dart';

/// Stores the PO document alongside the figures typed from it, so a PO can be
/// checked against the paperwork it came from — the same thing the invoice
/// originals do on the billing side.
class PoDocumentService {
  static PoDocumentService? _instance;
  static PoDocumentService get instance => _instance ??= PoDocumentService._();
  PoDocumentService._();

  static const String bucket = 'po-documents';

  /// Uploads the document and records it against [poNumber].
  ///
  /// Returns the storage path, or throws. The row update is done by the
  /// caller's insert when adding a new PO, so this only writes the object and
  /// hands back where it went.
  Future<Map<String, dynamic>> upload({
    required String poNumber,
    required Uint8List bytes,
    required String fileName,
    String? uploadedBy,
  }) async {
    final client = SupabaseService.instance.client;
    final safe = poNumber.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final ext = fileName.contains('.') ? fileName.split('.').last : 'pdf';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${safe.isEmpty ? 'po' : safe}-$stamp.$ext';

    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mimeFor(ext), upsert: false),
        );

    return {
      'file_name': fileName,
      'storage_path': path,
      'file_size_bytes': bytes.length,
      'uploaded_by': uploadedBy,
    };
  }

  /// Attaches a document to a PO already on record.
  Future<void> attachToExisting({
    required String poNumber,
    required Uint8List bytes,
    required String fileName,
    String? uploadedBy,
  }) async {
    final meta = await upload(
      poNumber: poNumber,
      bytes: bytes,
      fileName: fileName,
      uploadedBy: uploadedBy,
    );
    await SupabaseService.instance.client
        .from('po_trackers')
        .update(meta)
        .eq('po_number', poNumber);
  }

  /// Opens a stored PO document. Returns null on success, or a message.
  Future<String?> open({
    required String storagePath,
    String? fileName,
  }) async {
    if (storagePath.isEmpty) return 'No document attached to this PO';
    final client = SupabaseService.instance.client;
    try {
      if (kIsWeb) {
        final url = await client.storage
            .from(bucket)
            .createSignedUrl(storagePath, 600);
        if (url.isEmpty) return 'Could not create a view link';
        html.window.open(url, '_blank');
        return null;
      }
      final bytes = await client.storage.from(bucket).download(storagePath);
      final dir = await getTemporaryDirectory();
      final name = (fileName ?? '').isNotEmpty
          ? fileName!
          : storagePath.split('/').last;
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      final result = await OpenFile.open(file.path);
      return result.type == ResultType.done ? null : result.message;
    } catch (e) {
      return '$e';
    }
  }

  /// Removes a stored document. Leaves the PO row itself alone.
  Future<void> remove(String poNumber, String storagePath) async {
    final client = SupabaseService.instance.client;
    await client.from('po_trackers').update({
      'file_name': null,
      'storage_path': null,
      'file_size_bytes': null,
    }).eq('po_number', poNumber);
    try {
      await client.storage.from(bucket).remove([storagePath]);
    } catch (_) {
      // Row is cleared; a stray object is not worth failing over.
    }
  }

  String _mimeFor(String ext) => switch (ext.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'application/pdf',
      };
}
