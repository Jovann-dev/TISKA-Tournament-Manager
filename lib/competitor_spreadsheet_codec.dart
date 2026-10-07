import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'tournament_models.dart';

class CompetitorSpreadsheetCodec {
  static const List<String> columns = <String>[
    'id',
    'number',
    'name',
    'belt',
    'belt_rank',
    'gender',
    'birth_date',
    'birth_year',
    'age',
    'club',
    'kiddies_belt_color',
  ];

  static List<int> encode(List<Competitor> competitors) {
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Competitors') {
      workbook.rename(defaultSheet, 'Competitors');
    }
    final sheet = workbook['Competitors'];
    sheet.appendRow(columns.map(TextCellValue.new).toList());

    final referenceDate = DateTime.now();
    for (final competitor in competitors) {
      final birthDate =
          competitor.birthDate ??
          DateTime(referenceDate.year - competitor.age, 1, 1);
      sheet.appendRow(<CellValue?>[
        TextCellValue(competitor.id),
        TextCellValue(competitor.number),
        TextCellValue(competitor.name),
        TextCellValue(competitor.belt),
        IntCellValue(competitor.beltRank),
        TextCellValue(competitor.gender.storageValue),
        TextCellValue(birthDate.toIso8601String()),
        IntCellValue(birthDate.year),
        IntCellValue(competitor.age),
        TextCellValue(competitor.club),
        TextCellValue(competitor.belt.toLowerCase().startsWith('kiddies')
          ? kiddiesBeltColor(competitor.belt) : ''),
      ]);
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('Unable to generate competitors XLSX file.');
    }
    return bytes;
  }

  static List<Competitor> decode(Uint8List bytes, {DateTime? referenceDate}) {
    final workbook = Excel.decodeBytes(bytes);
    final sheets = workbook.tables.values.toList();
    if (sheets.isEmpty) {
      return const <Competitor>[];
    }
    final rows = sheets.first.rows
        .map((row) => row.map(_cellText).toList())
        .toList();
    return decodeRows(rows, referenceDate: referenceDate);
  }

  static List<Competitor> decodeRows(
    List<List<String>> rows, {
    DateTime? referenceDate,
  }) {
    if (rows.isEmpty) {
      return const <Competitor>[];
    }

    final header = <String, int>{};
    for (var index = 0; index < rows.first.length; index++) {
      var name = _normalizeHeader(rows.first[index]);
      if (name == '#' || name == 'competitor_number') {
        name = 'number';
      }
      if (name.isNotEmpty) {
        header.putIfAbsent(name, () => index);
      }
    }
    final hasHeader =
        header.containsKey('number') && header.containsKey('name');
    final firstDataRow = hasHeader ? 1 : 0;
    final now = referenceDate ?? DateTime.now();
    final imported = <Competitor>[];

    String valueAt(List<String> row, String column, int legacyIndex) {
      final index = hasHeader ? header[column] : legacyIndex;
      if (index == null || index < 0 || index >= row.length) {
        return '';
      }
      return row[index].trim();
    }

    for (var rowIndex = firstDataRow; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((cell) => cell.trim().isEmpty)) {
        continue;
      }

      final number = valueAt(row, 'number', 0);
      final name = valueAt(row, 'name', 1);
        final importedBelt = valueAt(row, 'belt', 2);
        final importedColor = valueAt(row, 'kiddies_belt_color', -1);
        final isKiddies = importedBelt.toLowerCase() == 'kiddies' ||
          importedBelt.toLowerCase().startsWith('kiddies - ');
        final belt = isKiddies
          ? 'Kiddies - ${importedColor.isEmpty ? kiddiesBeltColor(importedBelt) : normalizeKiddiesBeltColor(importedColor)}'
          : importedBelt;
      final birthDateRaw = valueAt(row, 'birth_date', -1);
      final birthYearRaw = valueAt(row, 'birth_year', 3);
      final birthYear = _parseBirthYear(birthYearRaw);
      final parsedBirthDate = DateTime.tryParse(birthDateRaw);
      final birthDate =
          parsedBirthDate ??
          (birthYear == null ? null : DateTime(birthYear, 1, 1));
      final ageFromBirthDate = birthDate == null
          ? null
          : now.year - birthDate.year;
      final age =
          ageFromBirthDate ??
          int.tryParse(valueAt(row, 'age', -1)) ??
          (birthYear == null ? null : now.year - birthYear);

      if (number.isEmpty ||
          name.isEmpty ||
          belt.isEmpty ||
          age == null ||
          age < 0 ||
          age > 120) {
        continue;
      }

      final id = valueAt(row, 'id', -1);
      final beltRank =
          int.tryParse(valueAt(row, 'belt_rank', -1)) ?? beltToRank(belt);
      final gender = parseGender(valueAt(row, 'gender', -1));
      final club = hasHeader
          ? valueAt(row, 'club', -1)
          : valueAt(row, 'club', 4);

      imported.add(
        Competitor(
          id: id.isEmpty ? '${now.microsecondsSinceEpoch}_$rowIndex' : id,
          number: number,
          name: name,
          belt: belt,
          beltRank: beltRank,
          gender: gender,
          age: age,
          birthDate: birthDate,
          club: club,
        ),
      );
    }
    return imported;
  }

  static List<Competitor> retainExistingIdsByNumber({
    required List<Competitor> imported,
    required List<Competitor> existing,
  }) {
    final existingIdByNumber = <String, String>{
      for (final competitor in existing) competitor.number: competitor.id,
    };
    return imported.map((competitor) {
      final existingId = existingIdByNumber[competitor.number];
      return existingId == null
          ? competitor
          : competitor.copyWith(id: existingId);
    }).toList();
  }

  static String _normalizeHeader(String value) {
    return value.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
  }

  static int? _parseBirthYear(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final year = int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
    return year ?? DateTime.tryParse(trimmed)?.year;
  }

  static String _cellText(Data? data) {
    final value = data?.value;
    if (value == null) {
      return '';
    }
    if (value is TextCellValue) {
      return value.value.text ?? value.value.toString();
    }
    if (value is IntCellValue) {
      return value.value.toString();
    }
    if (value is DoubleCellValue) {
      return value.value.toString();
    }
    if (value is BoolCellValue) {
      return value.value.toString();
    }
    return value.toString();
  }
}
