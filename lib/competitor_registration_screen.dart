import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'browser_download.dart';
import 'competitor_spreadsheet_codec.dart';
import 'tournament_models.dart';

class CompetitorRegistrationScreen extends StatefulWidget {
  final List<Competitor> competitors;
  final Future<void> Function(Competitor competitor) onSave;
  final Future<void> Function(String competitorId) onDelete;
  final Future<void> Function(List<Competitor> competitors)
  onReplaceCompetitors;

  const CompetitorRegistrationScreen({
    super.key,
    required this.competitors,
    required this.onSave,
    required this.onDelete,
    required this.onReplaceCompetitors,
  });

  @override
  State<CompetitorRegistrationScreen> createState() =>
      _CompetitorRegistrationScreenState();
}

class _CompetitorRegistrationScreenState
    extends State<CompetitorRegistrationScreen> {
  static const List<String> _kiddiesBelts = <String>[
    'White',
    'Yellow',
    'Orange',
    'Green',
    'Blue',
    'Purple',
    'Red',
    'Black',
  ];

  final numberController = TextEditingController();
  final nameController = TextEditingController();
  final birthYearController = TextEditingController();
  final clubController = TextEditingController();
  final searchController = TextEditingController();

  Gender selectedGender = Gender.male;
  String selectedBelt = beltOrder.first;
  String selectedKiddiesBelt = 'White';
  String? editingCompetitorId;
  int? selectedBirthYear;
  String? _activeSpreadsheetPath;
  bool isSubmitting = false;

  bool get isEditing => editingCompetitorId != null;

  List<Competitor> get _filteredCompetitors {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.competitors;
    }
    return widget.competitors
        .where(
          (competitor) =>
              competitor.name.toLowerCase().contains(query) ||
              competitor.number.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> saveCompetitor() async {
    final number = numberController.text.trim();
    final name = nameController.text.trim();
    final club = clubController.text.trim();
    final birthYear = int.tryParse(birthYearController.text.trim());
    final age = _calculateAgeFromBirthYear(birthYear);
    final belt = selectedBelt == 'Kiddies'
        ? 'Kiddies - $selectedKiddiesBelt'
        : selectedBelt;

    if (number.isEmpty || name.isEmpty || age == null) {
      _showMessage('Enter a competitor number, name, and valid birth year.');
      return;
    }

    final duplicate = widget.competitors.any(
      (competitor) =>
          competitor.number == number && competitor.id != editingCompetitorId,
    );

    if (duplicate) {
      _showMessage('Competitor number already exists.');
      return;
    }

    final savedCompetitor = Competitor(
      id:
          editingCompetitorId ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      number: number,
      name: name,
      belt: belt,
      beltRank: beltToRank(belt),
      gender: selectedGender,
      age: age,
      birthDate: DateTime(birthYear!, 1, 1),
      club: club,
    );
    final wasEditing = isEditing;
    final updatedList = _upsertCompetitor(widget.competitors, savedCompetitor);
    setState(() {
      isSubmitting = true;
    });

    try {
      await widget.onSave(savedCompetitor);
      await _syncSpreadsheetIfLoaded(updatedList);
      if (!mounted) {
        return;
      }
      setState(() {
        _resetForm();
      });
      _showMessage(
        wasEditing ? 'Competitor updated.' : 'Competitor registered.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Unable to save competitor: $error');
    } finally {
      if (mounted && isSubmitting) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  void editCompetitor(Competitor competitor) {
    setState(() {
      editingCompetitorId = competitor.id;
      numberController.text = competitor.number;
      nameController.text = competitor.name;
      selectedBirthYear =
          competitor.birthDate?.year ?? (DateTime.now().year - competitor.age);
      birthYearController.text = selectedBirthYear.toString();
      clubController.text = competitor.club;
      selectedGender = competitor.gender;
      final normalizedBelt = competitor.belt.trim();
      if (normalizedBelt.toLowerCase().startsWith('kiddies - ')) {
        selectedBelt = 'Kiddies';
        final kiddiesBelt = normalizedBelt.substring('Kiddies - '.length);
        selectedKiddiesBelt = _kiddiesBelts.contains(kiddiesBelt)
            ? kiddiesBelt
            : 'White';
      } else {
        selectedBelt = beltOrder.contains(normalizedBelt)
            ? normalizedBelt
            : 'White';
        selectedKiddiesBelt = 'White';
      }
    });
  }

  void _resetForm() {
    editingCompetitorId = null;
    numberController.clear();
    nameController.clear();
    birthYearController.clear();
    clubController.clear();
    selectedBirthYear = null;
    selectedGender = Gender.male;
    selectedBelt = beltOrder.first;
    selectedKiddiesBelt = 'White';
  }

  int? _calculateAgeFromBirthYear(int? birthYear) {
    if (birthYear == null) {
      return null;
    }
    final currentYear = DateTime.now().year;
    final earliestAllowedYear = currentYear - 120;
    if (birthYear > currentYear || birthYear < earliestAllowedYear) {
      return null;
    }
    return currentYear - birthYear;
  }

  List<Competitor> _upsertCompetitor(
    List<Competitor> source,
    Competitor competitor,
  ) {
    final updated = List<Competitor>.from(source);
    final index = updated.indexWhere((item) => item.id == competitor.id);
    if (index == -1) {
      updated.add(competitor);
    } else {
      updated[index] = competitor;
    }
    return updated;
  }

  Future<void> _syncSpreadsheetIfLoaded(List<Competitor> competitors) async {
    final path = _activeSpreadsheetPath;
    if (path == null || path.isEmpty) {
      return;
    }
    await _writeXlsx(path, competitors);
  }

  Future<void> _writeXlsx(String path, List<Competitor> competitors) async {
    final bytes = await compute(CompetitorSpreadsheetCodec.encode, competitors);
    if (kIsWeb) {
      await downloadBytes(
        fileName: path,
        bytes: Uint8List.fromList(bytes),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      return;
    }
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> _importXlsx() async {
    if (!mounted) {
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Excel', extensions: <String>['xlsx']),
        ],
      );
      if (file == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          isSubmitting = false;
        });
        return;
      }

      final fileName = file.name.toLowerCase();
      if (!fileName.endsWith('.xlsx')) {
        if (!mounted) {
          return;
        }
        setState(() {
          isSubmitting = false;
        });
        _showMessage('Please choose a valid XLSX file.');
        return;
      }

      final fileBytes = await file.readAsBytes();
      final decodedCompetitors = await compute(
        CompetitorSpreadsheetCodec.decode,
        fileBytes,
      );
      final imported = CompetitorSpreadsheetCodec.retainExistingIdsByNumber(
        imported: decodedCompetitors,
        existing: widget.competitors,
      );

      if (imported.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          isSubmitting = false;
        });
        _showMessage('No valid competitors found in XLSX.');
        return;
      }

      final dedupedByNumber = <String, Competitor>{
        for (final competitor in imported) competitor.number: competitor,
      };

      if (!mounted) return;
      final replacementIds = dedupedByNumber.values
          .map((item) => item.id)
          .toSet();
      final removedCount = widget.competitors
          .where((item) => !replacementIds.contains(item.id))
          .length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace competitor registrations?'),
          content: Text(
            '${dedupedByNumber.length} registrations will be imported; '
            '$removedCount existing registrations will be removed. '
            'Changes affecting started divisions will be rejected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.onReplaceCompetitors(dedupedByNumber.values.toList());
      if (!kIsWeb) {
        _activeSpreadsheetPath = file.path;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        isSubmitting = false;
        _resetForm();
      });
      _showMessage('Imported ${dedupedByNumber.length} competitors from XLSX.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Unable to import XLSX: $error');
    } finally {
      if (mounted && isSubmitting) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  Future<void> _createXlsxForRegistrations() async {
    setState(() {
      isSubmitting = true;
    });
    try {
      if (kIsWeb) {
        await _writeXlsx('competitors.xlsx', widget.competitors);
        if (!mounted) {
          return;
        }
        _showMessage('Competitors XLSX downloaded.');
        return;
      }
      final location = await getSaveLocation(
        suggestedName: 'competitors.xlsx',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Excel', extensions: <String>['xlsx']),
        ],
      );
      if (location == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          isSubmitting = false;
        });
        return;
      }

      final targetPath = location.path.toLowerCase().endsWith('.xlsx')
          ? location.path
          : '${location.path}.xlsx';
      await _writeXlsx(targetPath, widget.competitors);
      _activeSpreadsheetPath = targetPath;
      if (!mounted) {
        return;
      }
      setState(() {
        isSubmitting = false;
      });
      _showMessage('XLSX file created for registrations.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Unable to create XLSX: $error');
    } finally {
      if (mounted && isSubmitting) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    numberController.dispose();
    nameController.dispose();
    birthYearController.dispose();
    clubController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Competitor Registrations')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.badge_outlined, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Competitor Registry',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Total competitors: ${widget.competitors.length}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: isSubmitting ? null : _importXlsx,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Import XLSX'),
                            ),
                            OutlinedButton.icon(
                              onPressed: isSubmitting
                                  ? null
                                  : _createXlsxForRegistrations,
                              icon: const Icon(Icons.description),
                              label: const Text('Create XLSX'),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        if (isSubmitting)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit competitor' : 'Register competitor',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: numberController,
                          enabled: !isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'Competitor Number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameController,
                          enabled: !isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'Competitor Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedBelt,
                          decoration: const InputDecoration(
                            labelText: 'Belt',
                            border: OutlineInputBorder(),
                          ),
                          items: beltOrder
                              .map(
                                (belt) => DropdownMenuItem<String>(
                                  value: belt,
                                  child: Text(belt),
                                ),
                              )
                              .toList(),
                          onChanged: isSubmitting
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() {
                                      selectedBelt = value;
                                      if (value != 'Kiddies') {
                                        selectedKiddiesBelt = 'White';
                                      }
                                    });
                                  }
                                },
                        ),
                        if (selectedBelt == 'Kiddies') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: selectedKiddiesBelt,
                            decoration: const InputDecoration(
                              labelText: 'Kiddies Belt Color',
                              helperText: 'Select the competitor’s belt color.',
                              border: OutlineInputBorder(),
                            ),
                            items: _kiddiesBelts
                                .map(
                                  (belt) => DropdownMenuItem<String>(
                                    value: belt,
                                    child: Text(belt),
                                  ),
                                )
                                .toList(),
                            onChanged: isSubmitting
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        selectedKiddiesBelt = value;
                                      });
                                    }
                                  },
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Gender>(
                          initialValue: selectedGender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            border: OutlineInputBorder(),
                          ),
                          items: Gender.values
                              .map(
                                (gender) => DropdownMenuItem<Gender>(
                                  value: gender,
                                  child: Text(gender.label),
                                ),
                              )
                              .toList(),
                          onChanged: isSubmitting
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() {
                                      selectedGender = value;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: birthYearController,
                          enabled: !isSubmitting,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Birth Year',
                            hintText: 'e.g. 2009',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: clubController,
                          enabled: !isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'Club (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: isSubmitting ? null : saveCompetitor,
                              child: Text(
                                isEditing
                                    ? 'Update Competitor'
                                    : 'Add Competitor',
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: isEditing && !isSubmitting
                                  ? () => setState(_resetForm)
                                  : null,
                              child: const Text('Cancel Edit'),
                            ),
                          ],
                        ),
                        if (_activeSpreadsheetPath != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Active file: ${_activeSpreadsheetPath!.split(Platform.pathSeparator).last}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Search registered competitors',
                    hintText: 'Name or competitor number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.competitors.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No competitors registered yet.'),
                    ),
                  )
                else if (_filteredCompetitors.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No competitors match this search.'),
                    ),
                  )
                else
                  ..._filteredCompetitors.map((competitor) {
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${competitor.number} - ${competitor.name}',
                        ),
                        subtitle: Text(
                          '${competitor.belt} belt, ${competitor.gender.label}, age ${competitor.age}${competitor.club.isEmpty ? '' : ', club ${competitor.club}'}',
                        ),
                        onTap: isSubmitting
                            ? null
                            : () => editCompetitor(competitor),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: isSubmitting
                                  ? null
                                  : () => editCompetitor(competitor),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      setState(() {
                                        isSubmitting = true;
                                      });
                                      try {
                                        await widget.onDelete(competitor.id);
                                        await _syncSpreadsheetIfLoaded(
                                          widget.competitors
                                              .where(
                                                (item) =>
                                                    item.id != competitor.id,
                                              )
                                              .toList(),
                                        );
                                        if (!mounted) {
                                          return;
                                        }
                                        setState(() {
                                          if (editingCompetitorId ==
                                              competitor.id) {
                                            _resetForm();
                                          }
                                          isSubmitting = false;
                                        });
                                      } catch (error) {
                                        if (!mounted) {
                                          return;
                                        }
                                        setState(() {
                                          isSubmitting = false;
                                        });
                                        _showMessage(
                                          'Unable to delete competitor: $error',
                                        );
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
