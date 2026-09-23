import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/expense/data/transaction_repository.dart';

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  Future<void> exportJson(List<TransactionData> transactions) async {
    final file = await _writeFile(
      fileName:
          'fluid_ledger_export_${DateTime.now().millisecondsSinceEpoch}.json',
      body: const JsonEncoder.withIndent('  ').convert(
        transactions
            .map(
              (tx) => {
                'id': tx.id,
                'amount': tx.amount,
                'category': tx.category,
                'date': tx.date,
                'notes': tx.notes,
                'brand': tx.brand,
              },
            )
            .toList(),
      ),
    );
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Fluid Ledger transactions export (JSON)',
    );
  }

  Future<void> exportCsv(List<TransactionData> transactions) async {
    final lines = <String>['id,amount,category,date,notes,brand'];
    for (final tx in transactions) {
      lines.add(
        [
          _csv(tx.id ?? ''),
          tx.amount.toStringAsFixed(2),
          _csv(tx.category),
          _csv(tx.date),
          _csv(tx.notes ?? ''),
          _csv(tx.brand ?? ''),
        ].join(','),
      );
    }
    final file = await _writeFile(
      fileName:
          'fluid_ledger_export_${DateTime.now().millisecondsSinceEpoch}.csv',
      body: lines.join('\n'),
    );
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Fluid Ledger transactions export (CSV)',
    );
  }

  Future<File> _writeFile({
    required String fileName,
    required String body,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(body, flush: true);
    return file;
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
