import 'package:flutter/material.dart';

import 'tournament_models.dart';

class DivisionRegistrationScreen extends StatefulWidget {
  final List<Competitor> competitors;
  final List<Division> divisions;
  final List<String> tatamiNames;
  final Future<void> Function(Division division) onSave;
  final Future<void> Function(String divisionId) onDelete;

  const DivisionRegistrationScreen({
    super.key,
    required this.competitors,
    required this.divisions,
    required this.tatamiNames,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<DivisionRegistrationScreen> createState() =>
      _DivisionRegistrationScreenState();
}

class _DivisionRegistrationScreenState
    extends State<DivisionRegistrationScreen> {
  CompetitionType selectedCompetitionType = CompetitionType.kata;
  final competitorNumberController = TextEditingController();
  String? selectedTatamiName;
  String? editingDivisionId;
  final Set<String> selectedCompetitorIds = <String>{};
  bool isSubmitting = false;

  bool get isEditing => editingDivisionId != null;

  List<Division> get _sortedDivisions {
    final divisions = List<Division>.from(widget.divisions);
    divisions.sort((left, right) {
      final progressComparison = _progressOrder(left.progress)
          .compareTo(_progressOrder(right.progress));
      if (progressComparison != 0) {
        return progressComparison;
      }
      return left.createdAt.compareTo(right.createdAt);
    });
    return divisions;
  }

  int _progressOrder(DivisionProgress progress) {
    return switch (progress) {
      DivisionProgress.queued => 0,
      DivisionProgress.running => 1,
      DivisionProgress.completed => 2,
    };
  }

  ({IconData icon, Color color, String tooltip}) _progressIndicator(
    DivisionProgress progress,
  ) {
    return switch (progress) {
      DivisionProgress.queued => (
        icon: Icons.schedule_rounded,
        color: const Color(0xFF687386),
        tooltip: 'Not started',
      ),
      DivisionProgress.running => (
        icon: Icons.play_circle_fill_rounded,
        color: const Color(0xFFD9A62A),
        tooltip: 'In progress',
      ),
      DivisionProgress.completed => (
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF2E7D32),
        tooltip: 'Finished',
      ),
    };
  }

  @override
  void initState() {
    super.initState();
    selectedTatamiName = widget.tatamiNames.isEmpty
        ? null
        : widget.tatamiNames.first;
  }

  Division? get editingDivision {
    for (final division in widget.divisions) {
      if (division.id == editingDivisionId) {
        return division;
      }
    }
    return null;
  }

  List<Competitor> get selectedCompetitors {
    final selected = widget.competitors
        .where((competitor) => selectedCompetitorIds.contains(competitor.id))
        .toList();
    selected.sort((left, right) => left.number.compareTo(right.number));
    return selected;
  }

  _DivisionCriteria? get derivedCriteria {
    if (selectedCompetitors.isEmpty) {
      return null;
    }

    var minAge = selectedCompetitors.first.age;
    var maxAge = selectedCompetitors.first.age;
    var minBeltRank = selectedCompetitors.first.beltRank;
    var maxBeltRank = selectedCompetitors.first.beltRank;
    var hasMale = false;
    var hasFemale = false;

    for (final competitor in selectedCompetitors) {
      if (competitor.age < minAge) {
        minAge = competitor.age;
      }
      if (competitor.age > maxAge) {
        maxAge = competitor.age;
      }
      if (competitor.beltRank < minBeltRank) {
        minBeltRank = competitor.beltRank;
      }
      if (competitor.beltRank > maxBeltRank) {
        maxBeltRank = competitor.beltRank;
      }
      if (competitor.gender == Gender.male) {
        hasMale = true;
      } else {
        hasFemale = true;
      }
    }

    final gender = hasMale && hasFemale
        ? DivisionGender.mixed
        : hasMale
        ? DivisionGender.maleOnly
        : DivisionGender.femaleOnly;

    return _DivisionCriteria(
      minBeltRank: minBeltRank,
      maxBeltRank: maxBeltRank,
      minAge: minAge,
      maxAge: maxAge,
      gender: gender,
    );
  }

  Division? get previewDivision {
    final criteria = derivedCriteria;
    if (criteria == null || selectedTatamiName == null) {
      return null;
    }

    return Division(
      id: editingDivisionId ?? '',
      competitionType: selectedCompetitionType,
      minBeltRank: criteria.minBeltRank,
      maxBeltRank: criteria.maxBeltRank,
      minAge: criteria.minAge,
      maxAge: criteria.maxAge,
      gender: criteria.gender,
      assignedTatamiName: selectedTatamiName!,
      createdAt: editingDivision?.createdAt ?? 0,
      competitorIds: const <String>[],
    );
  }

  List<Competitor> get suggestedCompetitors {
    final criteria = derivedCriteria;
    if (criteria == null) {
      return const <Competitor>[];
    }

    return widget.competitors.where((competitor) {
      if (selectedCompetitorIds.contains(competitor.id)) {
        return false;
      }
      return criteria.matchesCompetitor(competitor);
    }).toList()..sort((left, right) => left.number.compareTo(right.number));
  }

  Future<void> saveDivision() async {
    if (widget.tatamiNames.isEmpty || selectedTatamiName == null) {
      _showMessage('Configure at least one tatami before creating divisions.');
      return;
    }

    final criteria = derivedCriteria;
    if (criteria == null) {
      _showMessage('Add competitors to construct a division range.');
      return;
    }
    if (selectedCompetitorIds.length < 2) {
      _showMessage('Add at least two competitors to create a division.');
      return;
    }

    final wasEditing = isEditing;
    final currentEditingDivision = editingDivision;
    setState(() {
      isSubmitting = true;
    });

    try {
      await widget.onSave(
        Division(
          id:
              editingDivisionId ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          competitionType: selectedCompetitionType,
          minBeltRank: criteria.minBeltRank,
          maxBeltRank: criteria.maxBeltRank,
          minAge: criteria.minAge,
          maxAge: criteria.maxAge,
          gender: criteria.gender,
          assignedTatamiName: selectedTatamiName!,
          createdAt:
              currentEditingDivision?.createdAt ??
              DateTime.now().millisecondsSinceEpoch,
          competitorIds: selectedCompetitorIds.toList()..sort(),
          progress: currentEditingDivision?.progress ?? DivisionProgress.queued,
          startedAt: currentEditingDivision?.startedAt,
          completedAt: currentEditingDivision?.completedAt,
          priorityBoostedAt: currentEditingDivision?.priorityBoostedAt,
          matchRecords:
              currentEditingDivision?.matchRecords ??
              const <DivisionMatchRecord>[],
          placements:
              currentEditingDivision?.placements ?? const <DivisionPlacement>[],
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _resetForm();
        isSubmitting = false;
      });
      _showMessage(wasEditing ? 'Division updated.' : 'Division registered.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSubmitting = false;
      });
      _showMessage('Unable to save division: $error');
    }
  }

  void editDivision(Division division) {
    setState(() {
      editingDivisionId = division.id;
      selectedCompetitionType = division.competitionType;
      selectedTatamiName = division.assignedTatamiName;
      selectedCompetitorIds
        ..clear()
        ..addAll(
          division.competitorIds.where(
            (id) => widget.competitors.any((competitor) => competitor.id == id),
          ),
        );
      competitorNumberController.clear();
    });
  }

  void _resetForm() {
    editingDivisionId = null;
    selectedCompetitionType = CompetitionType.kata;
    selectedTatamiName = widget.tatamiNames.isEmpty
        ? null
        : widget.tatamiNames.first;
    selectedCompetitorIds.clear();
    competitorNumberController.clear();
  }

  void _addCompetitorByNumber() {
    final number = competitorNumberController.text.trim();
    if (number.isEmpty) {
      return;
    }

    final match = widget.competitors.cast<Competitor?>().firstWhere(
      (competitor) => competitor?.number == number,
      orElse: () => null,
    );

    if (match == null) {
      _showMessage('No competitor found for number $number.');
      return;
    }

    if (selectedCompetitorIds.contains(match.id)) {
      _showMessage('Competitor $number is already selected.');
      return;
    }

    setState(() {
      selectedCompetitorIds.add(match.id);
      competitorNumberController.clear();
    });
  }

  void _removeCompetitor(String competitorId) {
    setState(() {
      selectedCompetitorIds.remove(competitorId);
    });
  }

  void _addSuggestedCompetitors() {
    final suggestions = suggestedCompetitors;
    if (suggestions.isEmpty) {
      return;
    }

    setState(() {
      selectedCompetitorIds.addAll(
        suggestions.map((competitor) => competitor.id),
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    competitorNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = previewDivision;
    final selected = selectedCompetitors;
    final suggestions = suggestedCompetitors;
    final tatamiDropdownValue =
        selectedTatamiName != null &&
            widget.tatamiNames.contains(selectedTatamiName)
        ? selectedTatamiName
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Division Registrations')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.groups_rounded, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Division Builder',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Registered divisions: ${widget.divisions.length} | Competitors in pool: ${widget.competitors.length}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ],
                                  ),
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
                                  isEditing
                                      ? 'Edit division'
                                      : 'Register division',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  preview == null
                                      ? 'Preview: Add competitor numbers to build division range.'
                                      : 'Preview: ${preview.title}',
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<CompetitionType>(
                                  initialValue: selectedCompetitionType,
                                  decoration: const InputDecoration(
                                    labelText: 'Competition Type',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: CompetitionType.values
                                      .map(
                                        (type) =>
                                            DropdownMenuItem<CompetitionType>(
                                              value: type,
                                              child: Text(type.label),
                                            ),
                                      )
                                      .toList(),
                                  onChanged: isSubmitting
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() {
                                              selectedCompetitionType = value;
                                            });
                                          }
                                        },
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: competitorNumberController,
                                        enabled: !isSubmitting,
                                        decoration: const InputDecoration(
                                          labelText: 'Competitor Number',
                                          border: OutlineInputBorder(),
                                        ),
                                        onSubmitted: (_) =>
                                            _addCompetitorByNumber(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : _addCompetitorByNumber,
                                      child: const Text('Add'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: tatamiDropdownValue,
                                  decoration: const InputDecoration(
                                    labelText: 'Assigned Tatami',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: widget.tatamiNames
                                      .map(
                                        (tatamiName) =>
                                            DropdownMenuItem<String>(
                                              value: tatamiName,
                                              child: Text(tatamiName),
                                            ),
                                      )
                                      .toList(),
                                  onChanged:
                                      isSubmitting || widget.tatamiNames.isEmpty
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() {
                                              selectedTatamiName = value;
                                            });
                                          }
                                        },
                                ),
                                if (widget.tatamiNames.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Text(
                                    'No tatamis configured yet. Configure tatamis first.',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Text(
                                  'Selected competitors (${selected.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                if (selected.isEmpty)
                                  const Text('No competitors selected yet.')
                                else
                                  ...selected.map(
                                    (competitor) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        '${competitor.number} - ${competitor.name}',
                                      ),
                                      subtitle: Text(
                                        '${competitor.belt} belt, ${competitor.gender.label}, age ${competitor.age}',
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: isSubmitting
                                            ? null
                                            : () => _removeCompetitor(
                                                competitor.id,
                                              ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : saveDivision,
                                      child: Text(
                                        isEditing
                                            ? 'Update Division'
                                            : 'Add Division',
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
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Suggested competitors in range',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed:
                                              suggestions.isEmpty ||
                                                  isSubmitting
                                              ? null
                                              : _addSuggestedCompetitors,
                                          child: const Text(
                                            'Add All Suggestions',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (widget.competitors.isEmpty)
                                  const Text(
                                    'Register competitors before creating divisions.',
                                  )
                                else if (selectedCompetitors.isEmpty)
                                  const Text(
                                    'Add at least one competitor number to get range suggestions.',
                                  )
                                else if (suggestions.isEmpty)
                                  const Text(
                                    'No additional competitors match the current derived range.',
                                  )
                                else
                                  ...suggestions.map(
                                    (competitor) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        '${competitor.number} - ${competitor.name}',
                                      ),
                                      subtitle: Text(
                                        '${competitor.belt} belt, ${competitor.gender.label}, age ${competitor.age}',
                                      ),
                                      trailing: TextButton(
                                        onPressed: isSubmitting
                                            ? null
                                            : () {
                                                setState(() {
                                                  selectedCompetitorIds.add(
                                                    competitor.id,
                                                  );
                                                });
                                              },
                                        child: const Text('Add'),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Registered divisions',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        if (widget.divisions.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No divisions registered yet.'),
                            ),
                          )
                        else
                          ..._sortedDivisions.map((division) {
                            final indicator = _progressIndicator(
                              division.progress,
                            );
                            return Card(
                              child: ListTile(
                                title: Text(division.title),
                                subtitle: Text(
                                  'Assigned Tatami: ${division.assignedTatamiName}\n'
                                  '${division.ageRangeLabel} | Competitors ${division.competitorIds.length}',
                                ),
                                onTap: isSubmitting
                                    ? null
                                    : () => editDivision(division),
                                trailing: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Tooltip(
                                      message: indicator.tooltip,
                                      child: Icon(
                                        indicator.icon,
                                        color: indicator.color,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit division',
                                      icon: const Icon(Icons.edit),
                                      onPressed: isSubmitting
                                          ? null
                                          : () => editDivision(division),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              setState(() {
                                                isSubmitting = true;
                                              });
                                              try {
                                                await widget.onDelete(
                                                  division.id,
                                                );
                                                if (!mounted) {
                                                  return;
                                                }
                                                setState(() {
                                                  if (editingDivisionId ==
                                                      division.id) {
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
                                                  'Unable to delete division: $error',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DivisionCriteria {
  final int minBeltRank;
  final int maxBeltRank;
  final int minAge;
  final int maxAge;
  final DivisionGender gender;

  const _DivisionCriteria({
    required this.minBeltRank,
    required this.maxBeltRank,
    required this.minAge,
    required this.maxAge,
    required this.gender,
  });

  bool matchesCompetitor(Competitor competitor) {
    final beltMatches =
        competitor.beltRank >= minBeltRank &&
        competitor.beltRank <= maxBeltRank;
    final ageMatches = competitor.age >= minAge && competitor.age <= maxAge;
    final genderMatches = switch (gender) {
      DivisionGender.mixed => true,
      DivisionGender.maleOnly => competitor.gender == Gender.male,
      DivisionGender.femaleOnly => competitor.gender == Gender.female,
    };
    return beltMatches && ageMatches && genderMatches;
  }
}
