import 'dart:async';

import 'package:flutter/material.dart';

import 'tournament_models.dart';
import 'tournament_snapshot_merge.dart';

class DivisionRegistrationScreen extends StatefulWidget {
  final List<Competitor> competitors;
  final List<Division> divisions;
  final List<String> tatamiNames;
  final Stream<List<CompetitionCategory>> Function()? watchCompetitionCategories;
  final Future<void> Function(Division division) onSave;
  final Future<void> Function(String divisionId) onDelete;

  const DivisionRegistrationScreen({
    super.key,
    required this.competitors,
    required this.divisions,
    required this.tatamiNames,
    this.watchCompetitionCategories,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<DivisionRegistrationScreen> createState() =>
      _DivisionRegistrationScreenState();
}

class _DivisionRegistrationScreenState
    extends State<DivisionRegistrationScreen> {
  List<CompetitionCategory> _categories = defaultCompetitionCategories();
  StreamSubscription<List<CompetitionCategory>>? _categoriesSubscription;
  String? selectedCategoryId = CompetitionType.kata.name;

  CompetitionCategory? get selectedCategory =>
      _categories.where((item) => item.id == selectedCategoryId).firstOrNull;

  List<CompetitionCategory> get availableCategories => _categories.where(
    (item) => item.enabled || item.id == editingDivision?.categoryId,
  ).toList();
  final competitorNumberController = TextEditingController();
  String? selectedTatamiName;
  String? editingDivisionId;
  final List<String> selectedCompetitorIds = <String>[];
  final List<DivisionTeam> _teams = [];
  final Map<String, String> _teamQueries = {};
  bool get _isTeamCategory => selectedCategory?.template == CompetitionTemplate.flagTeams;
  bool get _rosterLocked => editingDivision != null && divisionHasResults(editingDivision!);
  TeamRules get _teamRules => editingDivision?.categoryId == selectedCategoryId
      ? editingDivision!.teamRules : selectedCategory?.teamRules ?? const TeamRules();
  List<String> get _teamMemberIds => _teams.expand((team) => team.memberIds).toSet().toList();
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
    _categoriesSubscription = widget.watchCompetitionCategories?.call().listen((categories) {
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (!availableCategories.any((item) => item.id == selectedCategoryId)) {
          selectedCategoryId = availableCategories.firstOrNull?.id;
        }
      });
    });
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
    final competitorById = <String, Competitor>{
      for (final competitor in widget.competitors) competitor.id: competitor,
    };
    return (_isTeamCategory ? _teamMemberIds : selectedCompetitorIds)
        .map((id) => competitorById[id])
        .whereType<Competitor>()
        .toList();
  }

  Competitor? get competitorMatchingEntry {
    final number = competitorNumberController.text.trim();
    if (number.isEmpty) {
      return null;
    }
    for (final competitor in widget.competitors) {
      if (competitor.number == number) {
        return competitor;
      }
    }
    return null;
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
    var hasNotSpecified = false;

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
      } else if (competitor.gender == Gender.female) {
        hasFemale = true;
      } else {
        hasNotSpecified = true;
      }
    }

    final gender = (hasMale && hasFemale) || (hasNotSpecified && (hasMale || hasFemale))
        ? DivisionGender.mixed
        : hasMale
        ? DivisionGender.maleOnly
      : hasFemale
      ? DivisionGender.femaleOnly
      : DivisionGender.notSpecifiedOnly;

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
    final category = selectedCategory;
    if (criteria == null || selectedTatamiName == null || category == null) {
      return null;
    }

    return Division(
      id: editingDivisionId ?? '',
      competitionType: category.legacyType,
      competitionCategoryId: category.id,
      competitionCategoryName: category.name,
      competitionTemplate: category.template,
      teams: _isTeamCategory ? List.of(_teams) : [],
      teamRules: _teamRules,
      minBeltRank: criteria.minBeltRank,
      maxBeltRank: criteria.maxBeltRank,
      minAge: criteria.minAge,
      maxAge: criteria.maxAge,
      gender: criteria.gender,
      assignedTatamiName: selectedTatamiName!,
      createdAt: editingDivision?.createdAt ?? 0,
      competitorIds: _isTeamCategory ? _teamMemberIds : const <String>[],
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
    final category = selectedCategory;
    if (category == null || (!category.enabled && editingDivision?.categoryId != category.id)) {
      _showMessage('Select an available competition category.');
      return;
    }
    if (widget.tatamiNames.isEmpty || selectedTatamiName == null) {
      _showMessage('Configure at least one tatami before creating divisions.');
      return;
    }

    final criteria = derivedCriteria;
    if (criteria == null) {
      _showMessage('Add competitors to construct a division range.');
      return;
    }
    final entrantCount = _isTeamCategory ? _teams.length : selectedCompetitorIds.length;
    if (entrantCount < 2) {
      _showMessage(_isTeamCategory ? 'Add at least two teams to create a division.'
          : 'Add at least two competitors to create a division.');
      return;
    }
    if (entrantCount > 16) {
      _showMessage(_isTeamCategory ? 'A division can contain at most 16 teams.'
          : 'A division can contain at most 16 competitors.');
      return;
    }

    final wasEditing = isEditing;
    final currentEditingDivision = editingDivision;
    setState(() {
      isSubmitting = true;
    });

    try {
      if (_isTeamCategory) {
        validateTeamRosters(previewDivision!, widget.competitors.map((item) => item.id).toSet());
      }
      await widget.onSave(
        Division(
          id:
              editingDivisionId ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          competitionType: category.legacyType,
          competitionCategoryId: category.id,
          competitionCategoryName: category.name,
          competitionTemplate: category.template,
          teams: _isTeamCategory ? List.of(_teams) : [],
          teamRules: _isTeamCategory ? _teamRules : const TeamRules(),
          minBeltRank: criteria.minBeltRank,
          maxBeltRank: criteria.maxBeltRank,
          minAge: criteria.minAge,
          maxAge: criteria.maxAge,
          gender: criteria.gender,
          assignedTatamiName: selectedTatamiName!,
          createdAt:
              currentEditingDivision?.createdAt ??
              DateTime.now().millisecondsSinceEpoch,
          competitorIds: _isTeamCategory ? _teamMemberIds : selectedCompetitorIds.toList(),
          progress: currentEditingDivision?.progress ?? DivisionProgress.queued,
          startedAt: currentEditingDivision?.startedAt,
          completedAt: currentEditingDivision?.completedAt,
          priorityBoostedAt: currentEditingDivision?.priorityBoostedAt,
          matchRecords:
              currentEditingDivision?.matchRecords ??
              const <DivisionMatchRecord>[],
          placements:
              currentEditingDivision?.placements ?? const <DivisionPlacement>[],
          inProgressMatch: currentEditingDivision?.inProgressMatch,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _resetForm();
      });
      _showMessage(wasEditing ? 'Division updated.' : 'Division registered.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Unable to save division: $error');
    } finally {
      if (mounted && isSubmitting) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  void editDivision(Division division) {
    setState(() {
      editingDivisionId = division.id;
      selectedCategoryId = division.categoryId;
      selectedTatamiName = division.assignedTatamiName;
      _teams..clear()..addAll(division.teams);
      _teamQueries.clear();
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
    selectedCategoryId = _categories.where((item) => item.enabled).firstOrNull?.id;
    selectedTatamiName = widget.tatamiNames.isEmpty
        ? null
        : widget.tatamiNames.first;
    selectedCompetitorIds.clear();
    _teams.clear();
    _teamQueries.clear();
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

  void _addTeam() {
    if (_rosterLocked || _teams.length >= 16) return;
    var number = 1;
    for (final team in _teams) {
      if (team.number >= number) number = team.number + 1;
    }
    setState(() => _teams.add(DivisionTeam(
      id: 'team-${DateTime.now().microsecondsSinceEpoch}', number: number, memberIds: [],
    )));
  }

  void _updateTeam(DivisionTeam updated) {
    if (_rosterLocked || isSubmitting) return;
    setState(() {
      final index = _teams.indexWhere((team) => team.id == updated.id);
      if (index != -1) {
        if (_teams[index].memberIds.length != updated.memberIds.length) _teamQueries[updated.id] = '';
        _teams[index] = updated;
      }
    });
  }

  void _addMember(DivisionTeam team, Competitor competitor) {
    if (team.memberIds.contains(competitor.id)) return;
    if (_teamRules.maximumMembers != null && team.memberIds.length >= _teamRules.maximumMembers!) {
      _showMessage('Team ${team.number} has reached its member limit.');
      return;
    }
    if (!_teamRules.allowSharedMembers && _teams.any((other) =>
        other.id != team.id && other.memberIds.contains(competitor.id))) {
      _showMessage('This competitor already belongs to another team.');
      return;
    }
    _teamQueries[team.id] = '';
    _updateTeam(team.copyWith(memberIds: [...team.memberIds, competitor.id]));
  }

  void _moveTeam(int index, int offset) {
    if (_rosterLocked || isSubmitting) return;
    setState(() {
      final team = _teams.removeAt(index);
      _teams.insert(index + offset, team);
    });
  }

  Widget _buildTeams() {
    final byId = {for (final competitor in widget.competitors) competitor.id: competitor};
    final disabled = isSubmitting || _rosterLocked;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Teams (${_teams.length})', style: Theme.of(context).textTheme.titleMedium),
      Text('Members per team: ${_teamRules.minimumMembers}-${_teamRules.maximumMembers ?? 'None'}'),
      if (_rosterLocked) const Text('Redo the division before changing team rosters.'),
      const SizedBox(height: 8),
      OutlinedButton.icon(key: const ValueKey('add-division-team'),
        onPressed: disabled || _teams.length >= 16 ? null : _addTeam,
        icon: const Icon(Icons.group_add_outlined), label: const Text('Add Team')),
      for (var index = 0; index < _teams.length; index++)
        Builder(builder: (context) {
          final team = _teams[index];
          final query = (_teamQueries[team.id] ?? '').trim().toLowerCase();
          final choices = widget.competitors.where((competitor) =>
            !team.memberIds.contains(competitor.id) &&
            (competitor.number.toLowerCase().contains(query) || competitor.name.toLowerCase().contains(query)) &&
            (_teamRules.allowSharedMembers || !_teamMemberIds.contains(competitor.id))).take(8).toList();
          final invalidSize = team.memberIds.length < _teamRules.minimumMembers ||
              (_teamRules.maximumMembers != null && team.memberIds.length > _teamRules.maximumMembers!);
          return ExpansionTile(
            key: ValueKey('team-editor-${team.id}'), initiallyExpanded: true,
            tilePadding: EdgeInsets.zero, childrenPadding: const EdgeInsets.only(bottom: 16),
            title: Text('Team ${team.number}${team.name?.isNotEmpty ?? false ? ' - ${team.name}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${team.memberIds.length} members'),
            children: [
              Row(children: [
                IconButton(tooltip: 'Move Team ${team.number} Up', icon: const Icon(Icons.arrow_upward),
                  onPressed: disabled || index == 0 ? null : () => _moveTeam(index, -1)),
                IconButton(tooltip: 'Move Team ${team.number} Down', icon: const Icon(Icons.arrow_downward),
                  onPressed: disabled || index == _teams.length - 1 ? null : () => _moveTeam(index, 1)),
                const Spacer(),
                IconButton(tooltip: 'Remove Team ${team.number}', icon: const Icon(Icons.delete_outline),
                  onPressed: disabled ? null : () => setState(() => _teams.removeAt(index))),
              ]),
              if (_teamRules.allowNames) TextFormField(
                key: ValueKey('team-name-${team.id}'), initialValue: team.name,
                enabled: !disabled, maxLength: 80, decoration: const InputDecoration(labelText: 'Team Name (Optional)'),
                onChanged: (name) => _updateTeam(team.copyWith(name: name.trim())),
              ),
              if (!_teamRules.allowNames && (team.name?.isNotEmpty ?? false))
                InputChip(label: Text('Name: ${team.name}'),
                  onDeleted: disabled ? null : () => _updateTeam(team.copyWith(name: ''))),
              Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final id in team.memberIds) InputChip(
                  label: Text(byId[id] == null ? 'Missing competitor: $id' : '${byId[id]!.number} - ${byId[id]!.name}'),
                  onDeleted: disabled ? null : () => _updateTeam(team.copyWith(
                    memberIds: team.memberIds.where((member) => member != id).toList())),
                ),
              ])),
              if (invalidSize) Align(alignment: Alignment.centerLeft, child: Text(
                'Roster must contain ${_teamRules.minimumMembers}-${_teamRules.maximumMembers ?? 'any number of'} members.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )),
              const SizedBox(height: 8),
              TextFormField(key: ValueKey('team-search-${team.number}-${team.memberIds.length}'),
                enabled: !disabled, initialValue: '',
                decoration: const InputDecoration(labelText: 'Member Number or Name', prefixIcon: Icon(Icons.person_search_outlined)),
                onChanged: (value) => setState(() => _teamQueries[team.id] = value),
                onFieldSubmitted: (_) {
                  final exact = choices.where((item) => item.number.toLowerCase() == query).firstOrNull;
                  if (exact != null) {
                    _addMember(team, exact);
                  } else if (choices.length == 1) {
                    _addMember(team, choices.single);
                  }
                },
              ),
              if (query.isNotEmpty && !disabled) ...[
                if (choices.isEmpty) const Text('No available competitors match.'),
                for (final competitor in choices) ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${competitor.number} - ${competitor.name}'),
                  subtitle: competitor.club.isEmpty ? null : Text(competitor.club),
                  trailing: IconButton(tooltip: 'Add ${competitor.number} to Team ${team.number}',
                    icon: const Icon(Icons.person_add_outlined), onPressed: () => _addMember(team, competitor)),
                ),
              ],
            ],
          );
        }),
    ]);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _categoriesSubscription?.cancel();
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
                                DropdownButtonFormField<String>(
                                  key: ValueKey('competition-category-$selectedCategoryId-${availableCategories.map((item) => item.id).join(',')}'),
                                  initialValue: selectedCategoryId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Competition Category',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: availableCategories
                                      .map(
                                        (type) =>
                                            DropdownMenuItem<String>(
                                              value: type.id,
                                              child: Text(type.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ),
                                      )
                                      .toList(),
                                  onChanged: isSubmitting
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() {
                                              final wasTeam = _isTeamCategory;
                                              selectedCategoryId = value;
                                              if (wasTeam && !_isTeamCategory) {
                                                selectedCompetitorIds..clear()..addAll(_teamMemberIds);
                                              } else if (!wasTeam && _isTeamCategory && _teams.isEmpty && selectedCompetitorIds.isNotEmpty) {
                                                _teams.add(DivisionTeam(id: 'team-${DateTime.now().microsecondsSinceEpoch}',
                                                  number: 1, memberIds: List.of(selectedCompetitorIds)));
                                              }
                                            });
                                          }
                                        },
                                ),
                                const SizedBox(height: 12),
                                if (_isTeamCategory) _buildTeams(),
                                if (!_isTeamCategory) ...[
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
                                        onChanged: (_) => setState(() {}),
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
                                if (competitorNumberController.text
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    competitorMatchingEntry == null
                                        ? 'No competitor found for this number.'
                                        : '${competitorMatchingEntry!.number} - ${competitorMatchingEntry!.name}',
                                    style: TextStyle(
                                      color: competitorMatchingEntry == null
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                    ),
                                  ),
                                ],
                                ],
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
                                if (!_isTeamCategory) ...[
                                Text(
                                  'Draw sheet order (${selected.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                if (selected.isEmpty)
                                  const Text('No competitors selected yet.')
                                else
                                  ReorderableListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    buildDefaultDragHandles: false,
                                    itemCount: selected.length,
                                    onReorderItem: (oldIndex, newIndex) {
                                      if (isSubmitting) {
                                        return;
                                      }
                                      setState(() {
                                        final competitorId =
                                            selectedCompetitorIds.removeAt(
                                              oldIndex,
                                            );
                                        selectedCompetitorIds.insert(
                                          newIndex,
                                          competitorId,
                                        );
                                      });
                                    },
                                    itemBuilder: (context, index) {
                                      final competitor = selected[index];
                                      return ListTile(
                                        key: ValueKey(competitor.id),
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          child: Text('${index + 1}'),
                                        ),
                                        title: Text(
                                          '${competitor.number} - ${competitor.name}',
                                        ),
                                        subtitle: Text(
                                          '${competitor.belt} belt, ${competitor.gender.label}, age ${competitor.age}',
                                        ),
                                        trailing: Wrap(
                                          spacing: 0,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            IconButton(
                                              tooltip: 'Remove competitor',
                                              icon: const Icon(Icons.close),
                                              onPressed: isSubmitting
                                                  ? null
                                                  : () => _removeCompetitor(
                                                      competitor.id,
                                                    ),
                                            ),
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: Tooltip(
                                                message: 'Reorder draw sheet position',
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Icon(
                                                    Icons.drag_handle,
                                                    color: isSubmitting
                                                        ? Theme.of(context)
                                                              .disabledColor
                                                        : Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
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
                        if (!_isTeamCategory)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Suggested competitors in range',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    TextButton(
                                      onPressed:
                                          suggestions.isEmpty || isSubmitting
                                          ? null
                                          : _addSuggestedCompetitors,
                                      child: const Text('Add All Suggestions'),
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
                                  '${division.ageRangeLabel} | ${division.isTeamDivision ? 'Teams ${division.teams.length}' : 'Competitors ${division.competitorIds.length}'}',
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
      DivisionGender.notSpecifiedOnly => competitor.gender == Gender.notSpecified,
    };
    return beltMatches && ageMatches && genderMatches;
  }
}
