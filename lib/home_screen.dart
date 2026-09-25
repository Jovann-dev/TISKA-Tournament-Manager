import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import 'browser_download.dart';
import 'competitor_registration_screen.dart';
import 'draw_sheet_screen.dart';
import 'division_registration_screen.dart';
import 'live_match_state.dart';
import 'tatami_configuration_screen.dart';
import 'tatami_display_screen.dart';
import 'tatami_screen.dart';
import 'tournament_access_screen.dart';
import 'tournament_results_screen.dart';
import 'tournament_models.dart';
import 'tournament_repository.dart';

class HomeScreen extends StatefulWidget {
  final String tournamentId;

  const HomeScreen({super.key, this.tournamentId = ''});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<TatamiDefinition> _defaultTatamis = <TatamiDefinition>[
    TatamiDefinition(name: 'Tatami 1', judgesCount: 5),
    TatamiDefinition(name: 'Tatami 2', judgesCount: 5),
    TatamiDefinition(name: 'Tatami 3', judgesCount: 5),
  ];

  late final TournamentRepository _repository;
  final List<Competitor> _competitors = <Competitor>[];
  final List<Division> _divisions = <Division>[];
  List<TatamiDefinition> _tatamiDefinitions = const <TatamiDefinition>[];
  List<String> _tatamiNames = <String>[];
  StreamSubscription<List<TatamiDefinition>>? _tatamiDefinitionsSubscription;
  StreamSubscription<List<Competitor>>? _competitorsSubscription;
  StreamSubscription<List<Division>>? _divisionsSubscription;
  StreamSubscription<List<TatamiAssignment>>? _tatamiSubscription;
  bool _tatamiNamesLoaded = false;
  bool _competitorsLoaded = false;
  bool _divisionsLoaded = false;
  bool _tatamiLoaded = false;
  bool _repositoryReady = false;
  bool _subscriptionsAttached = false;
  String? _streamError;

  bool get _isLoading =>
      !_repositoryReady ||
      (!_tatamiNamesLoaded ||
          !_competitorsLoaded ||
          !_divisionsLoaded ||
          !_tatamiLoaded);

  @override
  void initState() {
    super.initState();
    _repository = TournamentRepository(tournamentId: widget.tournamentId);
    unawaited(_initializeRepository());
  }

  void _attachSubscriptions() {
    if (_subscriptionsAttached) {
      return;
    }
    _subscriptionsAttached = true;

    _tatamiDefinitionsSubscription = _repository
        .watchTatamiDefinitions()
        .listen((definitions) {
          if (!mounted) {
            return;
          }
          setState(() {
            _tatamiDefinitions = definitions;
            _tatamiNames = definitions
                .map((definition) => definition.name)
                .toList();
            _tatamiNamesLoaded = true;
          });
        }, onError: _handleStreamError);
    _competitorsSubscription = _repository.watchCompetitors().listen((
      competitors,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _competitors
          ..clear()
          ..addAll(competitors);
        _competitorsLoaded = true;
      });
    }, onError: _handleStreamError);
    _divisionsSubscription = _repository.watchDivisions().listen((divisions) {
      if (!mounted) {
        return;
      }
      setState(() {
        _divisions
          ..clear()
          ..addAll(divisions);
        _divisionsLoaded = true;
      });
    }, onError: _handleStreamError);
    _tatamiSubscription = _repository.watchTatamiAssignments().listen((
      assignments,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tatamiLoaded = true;
      });
    }, onError: _handleStreamError);
  }

  Future<void> _initializeRepository() async {
    try {
      await _repository.initialize(defaultTatamis: _defaultTatamis);
      _attachSubscriptions();
      if (!mounted) {
        return;
      }
      setState(() {
        _repositoryReady = true;
      });
    } catch (error) {
      _handleStreamError(error);
    }
  }

  void _handleStreamError(Object error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _streamError = error.toString();
      _repositoryReady = true;
      _tatamiNamesLoaded = true;
      _competitorsLoaded = true;
      _divisionsLoaded = true;
      _tatamiLoaded = true;
    });
  }

  Future<void> _saveCompetitor(Competitor competitor) {
    return _repository.saveCompetitor(competitor);
  }

  Future<void> _replaceCompetitors(List<Competitor> competitors) {
    return _repository.replaceCompetitors(competitors);
  }

  Future<void> _deleteCompetitor(String competitorId) {
    return _repository.deleteCompetitor(competitorId);
  }

  Future<void> _saveDivision(Division division) {
    return _repository.saveDivision(division);
  }

  Future<void> _deleteDivision(String divisionId) {
    return _repository.deleteDivision(divisionId);
  }

  Future<void> _assignDivisionToTatami(String tatamiName, String? divisionId) {
    return _repository.assignDivisionToTatami(tatamiName, divisionId);
  }

  Future<void> _configureTatamis(List<TatamiDefinition> definitions) {
    return _repository.configureTatamiDefinitions(definitions);
  }

  Future<void> _updateTatamiJudgeCount(String tatamiName, int judgesCount) {
    return _repository.updateTatamiJudgeCount(tatamiName, judgesCount);
  }

  Future<void> _startDivisionOnTatami(String tatamiName, String divisionId) {
    return _repository.startDivisionOnTatami(tatamiName, divisionId);
  }

  Future<void> _completeDivisionOnTatami(String tatamiName, String divisionId) {
    return _repository.completeDivisionOnTatami(tatamiName, divisionId);
  }

  Future<void> _redoDivisionOnTatami(String tatamiName, String divisionId) {
    return _repository.redoDivisionOnTatami(tatamiName, divisionId);
  }

  void _publishLiveMatchState(LiveMatchState state) {
    _repository.publishLiveMatchState(state);
  }

  Future<void> _saveDivisionExecutionState(
    String tatamiName,
    String divisionId, {
    required List<DivisionMatchRecord> matchRecords,
    required List<DivisionPlacement> placements,
    String? logMessage,
  }) {
    return _repository.saveDivisionExecutionState(
      tatamiName,
      divisionId,
      matchRecords: matchRecords,
      placements: placements,
      logMessage: logMessage,
    );
  }

  Future<void> _saveDrawSheetsToFolder() async {
    if (kIsWeb) {
      await _saveDataForWeb();
      return;
    }
    final selectedFolder = await getDirectoryPath(
      confirmButtonText: 'Save Draw Sheets Here',
    );
    if (selectedFolder == null || selectedFolder.isEmpty) {
      return;
    }

    try {
      final summaryPath = await _repository.exportDrawSheetsToFolder(
        selectedFolder,
      );
      final exportedImages = await _exportDrawSheetImagesToFolder(
        selectedFolder,
      );
      if (!mounted) {
        return;
      }

      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Data Saved'),
            content: Text(
              'Draw sheets exported successfully.\nSummary file: $summaryPath\nImages exported: $exportedImages\nCompetitors XLSX: competitors.xlsx\n\nClear current tournament data and logs for a new tournament?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep Data'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear Now'),
              ),
            ],
          );
        },
      );

      if (shouldClear == true) {
        await _repository.clearTournamentData();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tournament data and logs cleared.')),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save draw sheets: $error')),
      );
    }
  }

  Future<void> _saveDataForWeb() async {
    try {
      final files = _repository.buildTournamentExportFiles();
      files.addAll(await _captureDrawSheetImages());

      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw StateError('Unable to create tournament ZIP file.');
      }
      await downloadBytes(
        fileName: 'tiska_tournament_data.zip',
        bytes: Uint8List.fromList(zipBytes),
        mimeType: 'application/zip',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tournament data ZIP downloaded.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save tournament data: $error')),
      );
    }
  }

  Future<void> _closeApp() async {
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const TournamentAccessScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  Future<int> _exportDrawSheetImagesToFolder(String folderPath) async {
    final images = await _captureDrawSheetImages();
    for (final entry in images.entries) {
      final file = File('$folderPath${Platform.pathSeparator}${entry.key}');
      await file.writeAsBytes(entry.value, flush: true);
    }
    return images.length;
  }

  Future<Map<String, Uint8List>> _captureDrawSheetImages() async {
    final images = <String, Uint8List>{};
    if (_divisions.isEmpty) {
      return images;
    }

    final screenshotController = ScreenshotController();
    for (final division in _divisions) {
      if (!mounted) {
        return images;
      }
      if (division.matchRecords.isEmpty && division.placements.isEmpty) {
        continue;
      }

      final imageBytes = await screenshotController.captureFromWidget(
        Theme(
          data: Theme.of(context),
          child: InheritedTheme.captureAll(
            context,
            Material(
              color: Colors.white,
              child: SizedBox(
                width: 1320,
                child: DrawSheetContent(
                  division: division,
                  competitors: _competitors,
                  printFriendly: true,
                ),
              ),
            ),
          ),
        ),
        context: context,
        delay: const Duration(milliseconds: 80),
        pixelRatio: 2,
      );

      final safeName = _safeFileName(
        '${division.assignedTatamiName}_${division.title}_${division.id}.png',
      );
      images[safeName] = imageBytes;
    }

    return images;
  }

  String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  @override
  void dispose() {
    _tatamiDefinitionsSubscription?.cancel();
    _competitorsSubscription?.cancel();
    _divisionsSubscription?.cancel();
    _tatamiSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final actions =
        <({String title, String subtitle, IconData icon, VoidCallback? onTap})>[
          (
            title: 'Competitors',
            subtitle: 'Register, edit, import, and export competitor data.',
            icon: Icons.badge_outlined,
            onTap: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CompetitorRegistrationScreen(
                          competitors: _competitors,
                          onSave: _saveCompetitor,
                          onDelete: _deleteCompetitor,
                          onReplaceCompetitors: _replaceCompetitors,
                        ),
                      ),
                    );
                  },
          ),
          (
            title: 'Tatamis',
            subtitle: 'Configure tatami names and judge counts.',
            icon: Icons.grid_view_rounded,
            onTap: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TatamiConfigurationScreen(
                          tatamiDefinitions: _tatamiDefinitions,
                          onSave: _configureTatamis,
                        ),
                      ),
                    );
                  },
          ),
          (
            title: 'Divisions',
            subtitle: 'Build and manage divisions with balanced ranges.',
            icon: Icons.groups_rounded,
            onTap: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DivisionRegistrationScreen(
                          competitors: _competitors,
                          divisions: _divisions,
                          tatamiNames: _tatamiNames,
                          onSave: _saveDivision,
                          onDelete: _deleteDivision,
                        ),
                      ),
                    );
                  },
          ),
          (
            title: 'Competition Floor',
            subtitle: 'Assign divisions, run matches, and control tatamis.',
            icon: Icons.sports_kabaddi_rounded,
            onTap: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TatamiScreen(
                          watchTatamiDefinitions:
                              _repository.watchTatamiDefinitions,
                          watchDivisions: _repository.watchDivisions,
                          watchCompetitors: _repository.watchCompetitors,
                          watchTatamiLogs: _repository.watchTatamiLogs,
                          onAssign: _assignDivisionToTatami,
                          onDeleteDivision: _deleteDivision,
                          onStartDivision: _startDivisionOnTatami,
                          onCompleteDivision: _completeDivisionOnTatami,
                          onRedoDivision: _redoDivisionOnTatami,
                          onUpdateJudgeCount: _updateTatamiJudgeCount,
                          onSaveExecutionState: _saveDivisionExecutionState,
                          onPublishLiveState: _publishLiveMatchState,
                          onSaveInProgressMatch:
                              _repository.saveDivisionInProgressMatch,
                        ),
                      ),
                    );
                  },
          ),
          (
            title: 'Tatami Display',
            subtitle: 'Show live match progress on a screen or projector.',
            icon: Icons.live_tv_rounded,
            onTap: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TatamiDisplayScreen(
                          watchTatamiDefinitions:
                              _repository.watchTatamiDefinitions,
                          watchDivisions: _repository.watchDivisions,
                          watchCompetitors: _repository.watchCompetitors,
                          watchLiveMatchState: _repository.watchLiveMatchState,
                        ),
                      ),
                    );
                  },
          ),
          (
            title: 'Tournament Results',
            subtitle: 'Review completed divisions and draw sheets.',
            icon: Icons.emoji_events_outlined,
            onTap: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TournamentResultsScreen(
                          divisions: _divisions,
                          competitors: _competitors,
                          tatamiDefinitions: _tatamiDefinitions,
                        ),
                      ),
                    );
                  },
          ),
        ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('TISKA Tournament Manager'),
        actions: [
          IconButton(
            tooltip: 'Save Data',
            onPressed: _isLoading ? null : _saveDrawSheetsToFolder,
            icon: const Icon(Icons.save_alt),
          ),
          IconButton(
            tooltip: 'Close App',
            onPressed: _closeApp,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.secondary,
                        const Color(0xFF6C0D0E),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tournament Command Center',
                        style: textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Plan divisions, run tatamis, and archive complete results from one professional workflow.',
                        style: textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFFF4EDEE),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatChip(
                            label: 'Tatamis',
                            value: _tatamiNames.length.toString(),
                            icon: Icons.grid_view_rounded,
                          ),
                          _StatChip(
                            label: 'Competitors',
                            value: _competitors.length.toString(),
                            icon: Icons.badge_outlined,
                          ),
                          _StatChip(
                            label: 'Divisions',
                            value: _divisions.length.toString(),
                            icon: Icons.groups,
                          ),
                        ],
                      ),
                      if (_isLoading) ...[
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(minHeight: 4),
                      ],
                    ],
                  ),
                ),
                if (_streamError != null) ...[
                  const SizedBox(height: 14),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Data sync error: $_streamError'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text('Operations', style: textTheme.titleLarge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: actions
                      .map(
                        (action) => _MenuActionCard(
                          title: action.title,
                          subtitle: action.subtitle,
                          icon: action.icon,
                          onTap: action.onTap,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _MenuActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return SizedBox(
      width: 360,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: disabled
                        ? const Color(0xFFE7E9EF)
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: disabled
                        ? const Color(0xFF8C96A8)
                        : colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: disabled
                      ? const Color(0xFF8C96A8)
                      : const Color(0xFF5A6579),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x4DFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
