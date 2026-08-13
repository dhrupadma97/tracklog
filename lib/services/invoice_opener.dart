import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

import 'invoice_service.dart';

/// Opens a stored original invoice.
///
/// Web opens a short-lived signed URL in a new tab (same approach as the Tyre
/// Trends screen); mobile downloads the bytes to the cache and hands them to
/// the platform viewer, matching the PO attachment flow.
///
/// Returns `null` on success, or a message describing why it could not open.
Future<String?> openInvoice(NatraxInvoice invoice) async {
  if (!invoice.hasFile) return 'No file attached to this invoice';

  try {
    if (kIsWeb) {
      final url = await InvoiceService.instance.signedUrl(invoice);
      if (url == null || url.isEmpty) return 'Could not create a view link';
      html.window.open(url, '_blank');
      return null;
    }

    final bytes = await InvoiceService.instance.download(invoice);
    if (bytes == null) return 'Could not download the invoice';

    final cacheDir = await getTemporaryDirectory();
    final name = (invoice.fileName ?? '').isNotEmpty
        ? invoice.fileName!
        : '${invoice.invoiceNumber}.pdf';
    final file = File('${cacheDir.path}/$name');
    await file.writeAsBytes(bytes);

    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) return result.message;
    return null;
  } catch (e) {
    return '$e';
  }
}
