import 'package:flutter/material.dart';
import 'package:papyrus/opds/opds_browser.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:provider/provider.dart';

/// A retry may use corrected credentials, but never a different catalog URL or
/// a job removed by an account switch. Open format sheets retain stricter checks.
Future<void> retryOpdsDownload(BuildContext context, OpdsDownloadJob job) async {
  if (!context.mounted) return;
  final catalogs = context.read<OpdsCatalogs>();
  final downloads = context.read<OpdsDownloads>();
  final scope = catalogs.scope;
  final revision = catalogs.revision;
  if (!downloads.jobs.contains(job)) return;
  try {
    final catalog = catalogs.find(job.catalog.id);
    if (catalog == null || catalog.uri != job.catalog.uri) {
      throw const OpdsException('The catalog changed. Open the book again to choose a current download.');
    }
    final credentials = await catalogs.credentials(catalog.id);
    if (!context.mounted || catalogs.scope != scope || catalogs.revision != revision || !downloads.jobs.contains(job)) {
      return;
    }
    await downloads.start(catalog, job.publication, job.link, credentials: credentials);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(opdsErrorMessage(error))));
    }
  }
}
