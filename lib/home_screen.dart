import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import 'browser_download.dart';
import 'competitor_registration_screen.dart';
import 'division_process_log_spreadsheet_codec.dart';
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

List<int> encodeDrawSheetImageArchive(Map<String, Uint8List> images) {
  final archive = Archive();
  for (final entry in images.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final bytes = ZipEncoder().encode(archive);
  if (bytes == null) {
    throw StateError('Unable to create the draw-sheet image ZIP file.');
  }
  return bytes;
}

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
  StreamSubscription<Map<String, List<TatamiLogEntry>>>?
  _tatamiLogsSubscription;
  Map<String, List<TatamiLogEntry>> _tatamiLogsByTatami =
      const <String, List<TatamiLogEntry>>{};
  bool _tatamiNamesLoaded = false;
  bool _competitorsLoaded = false;
  bool _divisionsLoaded = false;
  bool _tatamiLoaded = false;
  bool _repositoryReady = false;
  bool _subscriptionsAttached = false;
  bool _isSavingDrawSheets = false;
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
    _tatamiLogsSubscription = _repository.watchTatamiLogs().listen((logs) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tatamiLogsByTatami = logs;
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
    if (_isSavingDrawSheets) {
      return;
    }

    setState(() {
      _isSavingDrawSheets = true;
    });
    try {
      if (_divisions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No divisions are available to export.'),
            ),
          );
        }
        return;
      }

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

      final exportedImages = await _exportDrawSheetImagesToFolder(
        selectedFolder,
      );
      await _exportDivisionLogsXlsxToFolder(selectedFolder);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $exportedImages draw-sheet images and division_logs.xlsx.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save draw sheets: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDrawSheets = false;
        });
      }
    }
  }

  Future<void> _saveDataForWeb() async {
    final images = await _captureDrawSheetImages();
    if (images.isEmpty) {
      return;
    }

    final processLogBytes = _buildDivisionLogsXlsxBytes();
    final filesForArchive = <String, Uint8List>{
      ...images,
      'division_logs.xlsx': processLogBytes,
    };

    final zipBytes = await compute(encodeDrawSheetImageArchive, filesForArchive);
    await downloadBytes(
      fileName: 'tiska_draw_sheets.zip',
      bytes: Uint8List.fromList(zipBytes),
      mimeType: 'application/zip',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draw-sheet images + division logs ZIP downloaded.'),
        ),
      );
    }
  }

  Uint8List _buildDivisionLogsXlsxBytes() {
    final bytes = encodeDivisionProcessLogWorkbook(
      divisions: _divisions,
      tatamiLogsByTatami: _tatamiLogsByTatami,
    );
    return Uint8List.fromList(bytes);
  }

  Future<void> _exportDivisionLogsXlsxToFolder(String folderPath) async {
    final file = File(
      '$folderPath${Platform.pathSeparator}division_logs.xlsx',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_buildDivisionLogsXlsxBytes(), flush: true);
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
    for (final tatamiFolder in _tatamiFolderNames) {
      await Directory('$folderPath${Platform.pathSeparator}$tatamiFolder')
          .create(recursive: true);
    }
    for (final entry in images.entries) {
      final relativePath = entry.key.replaceAll('/', Platform.pathSeparator);
      final file = File('$folderPath${Platform.pathSeparator}$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value, flush: true);
    }
    return images.length;
  }

  List<String> get _tatamiFolderNames {
    final folders = <String>{
      ..._tatamiDefinitions.map(
        (definition) => _safeTatamiFolderName(definition.name),
      ),
      ..._divisions.map(
        (division) => _safeTatamiFolderName(division.assignedTatamiName),
      ),
    };
    return folders.toList();
  }

  String _safeTatamiFolderName(String value) {
    final safeName = _safeFileName(value.trim());
    return safeName.isEmpty ? 'Unassigned Tatami' : safeName;
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

      final tatamiFolder = _safeTatamiFolderName(division.assignedTatamiName);
      final safeName = _safeFileName('${division.title}_${division.id}.png');
      images['$tatamiFolder/$safeName'] = imageBytes;
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
    _tatamiLogsSubscription?.cancel();
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
            tooltip: _isSavingDrawSheets ? 'Saving draw sheets' : 'Save Data',
            onPressed: _isLoading || _isSavingDrawSheets
                ? null
                : _saveDrawSheetsToFolder,
            icon: _isSavingDrawSheets
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
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
