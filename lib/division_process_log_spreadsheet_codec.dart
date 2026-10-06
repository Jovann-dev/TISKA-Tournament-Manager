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
    TextCellValue('Tatami'),
    TextCellValue('Division Description'),
  ]);

  final divisionById = <String, Division>{
    for (final division in divisions) division.id: division,
  };

  final allEntries = <TatamiLogEntry>[
    for (final entry in tatamiLogsByTatami.values.expand((entries) => entries))
      if (entry.lifecycleEntry(division: divisionById[entry.divisionId]) case final normalized?)
        normalized,
  ]..sort((left, right) {
    final timestamp = left.timestamp.compareTo(right.timestamp);
    return timestamp != 0 ? timestamp : left.id.compareTo(right.id);
  });

  for (final entry in allEntries) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      entry.timestamp,
      isUtc: true,
    ).toIso8601String();

    sheet.appendRow(<CellValue?>[
      TextCellValue(entry.divisionId!),
      TextCellValue(entry.activity!),
      TextCellValue(timestamp),
      entry.competitorCount == null ? null : IntCellValue(entry.competitorCount!),
      TextCellValue(entry.tatamiName),
      TextCellValue(entry.divisionTitle ?? ''),
    ]);
  }

  final bytes = workbook.save();
  if (bytes == null) {
    throw StateError('Unable to generate division process log XLSX file.');
  }
  return bytes;
}
