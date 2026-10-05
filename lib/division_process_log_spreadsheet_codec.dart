import 'package:excel/excel.dart';

import 'tournament_models.dart';

List<int> encodeDivisionProcessLogWorkbook({
  required List<Division> divisions,
  required Map<String, List<TatamiLogEntry>> tatamiLogsByTatami,
}) {
  final workbook = Excel.createExcel();
  final defaultSheet = workbook.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != 'Process Mining Logs') {
    workbook.rename(defaultSheet, 'Process Mining Logs');
  }
  final sheet = workbook['Process Mining Logs'];

  sheet.appendRow(<CellValue?>[
    TextCellValue('Division'),
    TextCellValue('What Happened'),
    TextCellValue('When it Happened'),
    TextCellValue('Number of Competitors'),
  ]);

  final divisionById = <String, Division>{
    for (final division in divisions) division.id: division,
  };

  final allEntries = tatamiLogsByTatami.values
      .expand((entries) => entries)
      .toList()
    ..sort((left, right) => left.timestamp.compareTo(right.timestamp));

  for (final entry in allEntries) {
    final division = entry.divisionId == null
        ? null
        : divisionById[entry.divisionId!];
    final divisionLabel =
        entry.divisionTitle ?? division?.title ?? entry.divisionId ?? 'Unknown';
    final activity = entry.activity ?? entry.message;
    final competitorCount =
        entry.competitorCount ?? division?.competitorIds.length ?? 0;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      entry.timestamp,
      isUtc: true,
    ).toIso8601String();

    sheet.appendRow(<CellValue?>[
      TextCellValue(divisionLabel),
      TextCellValue(activity),
      TextCellValue(timestamp),
      IntCellValue(competitorCount),
    ]);
  }

  final bytes = workbook.save();
  if (bytes == null) {
    throw StateError('Unable to generate division process log XLSX file.');
  }
  return bytes;
}
