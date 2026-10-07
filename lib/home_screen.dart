import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import 'browser_download.dart';
import 'competition_categories_screen.dart';
import 'competitor_registration_screen.dart';
import 'division_process_log_spreadsheet_codec.dart';
import 'draw_sheet_screen.dart';
import 'division_registration_screen.dart';
import 'live_match_state.dart';
import 'tatami_configuration_screen.dart';
import 'tatami_display_screen.dart';
import 'tatami_screen.dart';
import 'tournament_access_screen.dart';
import 'tournament_backup.dart';
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
  final bool isAdmin;

  const HomeScreen({super.key, this.tournamentId = '', this.isAdmin = false});

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
  StreamSubscription<TournamentSyncStatus>? _syncStatusSubscription;
  TournamentSyncStatus _syncStatus = const TournamentSyncStatus(
    TournamentSyncState.localOnly,
    'Saved locally',
  );
  bool _tatamiNamesLoaded = false;
  bool _competitorsLoaded = false;
  bool _divisionsLoaded = false;
  bool _tatamiLoaded = false;
  bool _repositoryReady = false;
  bool _subscriptionsAttached = false;
  bool _isSavingDrawSheets = false;
  bool _isRestoringBackup = false;
  bool _isDeletingTournament = false;
  String? _streamError;

  bool get _isLoading =>
      _isDeletingTournament ||
      _isRestoringBackup ||
      !_repositoryReady ||
      (!_tatamiNamesLoaded ||
          !_competitorsLoaded ||
          !_divisionsLoaded ||
          !_tatamiLoaded);

  @override
  void initState() {
    super.initState();
    _repository = TournamentRepository(tournamentId: widget.tournamentId, isAdmin: widget.isAdmin);
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
    _syncStatusSubscription = _repository.watchSyncStatus().listen((status) {
      if (!mounted) return;
      setState(() => _syncStatus = status);
    });
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
      _attachSubscriptions();
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
      final backup = _repository.captureBackup();

      if (kIsWeb) {
        await _saveDataForWeb(backup);
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
        backup,
      );
      await _exportDivisionLogsXlsxToFolder(selectedFolder, backup);
      await File('$selectedFolder${Platform.pathSeparator}tournament_backup.json')
          .writeAsBytes(backup.encode(), flush: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $exportedImages draw sheets, division logs, and tournament backup.',
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

  Future<void> _saveDataForWeb(TournamentBackup backup) async {
    final images = await _captureDrawSheetImages(backup);
    if (!mounted) return;

    final processLogBytes = _buildDivisionLogsXlsxBytes(backup);
    final filesForArchive = <String, Uint8List>{
      ...images,
      'division_logs.xlsx': processLogBytes,
      'tournament_backup.json': backup.encode(),
    };

    final zipBytes = await compute(
      encodeDrawSheetImageArchive,
      filesForArchive,
    );
    await downloadBytes(
      fileName: 'tiska_draw_sheets.zip',
      bytes: Uint8List.fromList(zipBytes),
      mimeType: 'application/zip',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draw sheets, division logs, and backup ZIP downloaded.'),
        ),
      );
    }
  }

  Uint8List _buildDivisionLogsXlsxBytes(TournamentBackup backup) {
    final bytes = encodeDivisionProcessLogWorkbook(
      divisions: backup.divisions,
      tatamiLogsByTatami: backup.tatamiLogs,
    );
    return Uint8List.fromList(bytes);
  }

  Future<void> _exportDivisionLogsXlsxToFolder(
    String folderPath, TournamentBackup backup,
  ) async {
    final file = File('$folderPath${Platform.pathSeparator}division_logs.xlsx');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_buildDivisionLogsXlsxBytes(backup), flush: true);
  }

  Future<void> _restoreBackup() async {
    if (_isLoading || _isSavingDrawSheets) return;
    setState(() => _isRestoringBackup = true);
    try {
      final file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'Tournament backup', extensions: ['json']),
      ]);
      if (file == null || !mounted) return;
      if (await file.length() > 50 * 1024 * 1024) {
        throw const FormatException('The backup exceeds the 50 MB size limit.');
      }
      final backup = TournamentBackup.decode(await file.readAsBytes());
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore tournament backup?'),
          content: Text(
            'Replace "${widget.tournamentId}" with the backup from '
            '${backup.capturedAt.toLocal()}? '
            'Started divisions cannot be changed by restore.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.restore), label: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _repository.restoreBackup(backup);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored locally; synchronization queued.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to restore backup: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoringBackup = false);
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

  Future<void> _changeUserPassword() async {
    final passwordController = TextEditingController();
    final confirmationController = TextEditingController();
    String? password;
    try {
      password = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Set user password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'User password'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmationController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm user password',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    if (_passwordFieldsMatch(
                      passwordController,
                      confirmationController,
                    )) {
                      Navigator.of(dialogContext)
                          .pop(passwordController.text.trim());
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    _passwordFieldsMatch(
                      passwordController,
                      confirmationController,
                    )
                    ? () =>
                          Navigator.of(dialogContext)
                              .pop(passwordController.text.trim())
                    : null,
                child: const Text('Save password'),
              ),
            ],
          ),
        ),
      );
    } finally {
      passwordController.dispose();
      confirmationController.dispose();
    }
    if (password == null || !mounted) return;

    try {
      await _repository.setTournamentUserPassword(password);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('User password saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save user password: $error')),
      );
    }
  }

  bool _passwordFieldsMatch(
    TextEditingController password,
    TextEditingController confirmation,
  ) {
    final value = password.text.trim();
    return value.isNotEmpty && value == confirmation.text.trim();
  }

  Future<void> _deleteTournament() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete tournament?'),
        content: Text(
          'This permanently deletes "${widget.tournamentId}" from the shared database and clears its local data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete tournament'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingTournament = true);
    try {
      await _repository.deleteTournament();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (context) => const TournamentAccessScreen(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete tournament: $error')),
      );
    } finally {
      if (mounted) setState(() => _isDeletingTournament = false);
    }
  }

  Future<int> _exportDrawSheetImagesToFolder(
    String folderPath, TournamentBackup backup,
  ) async {
    final images = await _captureDrawSheetImages(backup);
    for (final tatamiFolder in _tatamiFolderNames(backup)) {
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

  List<String> _tatamiFolderNames(TournamentBackup backup) {
    final folders = <String>{
      ...backup.tatamiDefinitions.map(
        (definition) => _safeTatamiFolderName(definition.name),
      ),
      ...backup.divisions.map(
        (division) => _safeTatamiFolderName(division.assignedTatamiName),
      ),
    };
    return folders.toList();
  }

  String _safeTatamiFolderName(String value) {
    final safeName = _safeFileName(value.trim());
    return safeName.isEmpty ? 'Unassigned Tatami' : safeName;
  }

  Future<Map<String, Uint8List>> _captureDrawSheetImages(TournamentBackup backup) async {
    final images = <String, Uint8List>{};
    final divisions = backup.divisions;
    final competitors = backup.competitors;
    if (divisions.isEmpty) {
      return images;
    }

    final screenshotController = ScreenshotController();
    for (final division in divisions) {
      if (!mounted) {
        throw StateError('Export cancelled.');
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
                  competitors: competitors,
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
    _syncStatusSubscription?.cancel();
    unawaited(_repository.dispose());
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
                          watchCompetitionCategories: _repository.watchCompetitionCategories,
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
                          tournamentId: widget.tournamentId,
                          onOpenExecution: _repository.openDivisionExecution,
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
                          onClearLiveState: (tatamiName, divisionId) =>
                              _repository.clearLiveMatchState(
                                tatamiName, divisionId: divisionId,
                              ),
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
                          tournamentId: widget.tournamentId,
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
          if (widget.isAdmin) ...[
            IconButton(
              tooltip: 'Competition Categories',
              onPressed: _isLoading ? null : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CompetitionCategoriesScreen(
                  watchCategories: _repository.watchCompetitionCategories,
                  onSave: _repository.saveCompetitionCategory,
                  onDelete: _repository.deleteCompetitionCategory,
                )),
              ),
              icon: const Icon(Icons.category_outlined),
            ),
            IconButton(
              tooltip: 'Restore tournament backup',
              onPressed: _isLoading || _isSavingDrawSheets ? null : _restoreBackup,
              icon: const Icon(Icons.restore),
            ),
            IconButton(
              tooltip: 'Set user password',
              onPressed: _isDeletingTournament ? null : _changeUserPassword,
              icon: const Icon(Icons.password_rounded),
            ),
            IconButton(
              tooltip: 'Delete tournament',
              onPressed: _isDeletingTournament ? null : _deleteTournament,
              icon: const Icon(Icons.delete_forever_outlined),
            ),
          ],
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(switch (_syncStatus.state) {
                      TournamentSyncState.synced => Icons.cloud_done_outlined,
                      TournamentSyncState.syncing => Icons.sync,
                      TournamentSyncState.conflict =>
                        Icons.warning_amber_rounded,
                      _ => Icons.cloud_off_outlined,
                    }),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_syncStatus.message)),
                    IconButton(
                      tooltip: 'Retry synchronization',
                      onPressed:
                          _syncStatus.state == TournamentSyncState.syncing
                          ? null
                          : () => _repository.synchronize(),
                      icon: const Icon(Icons.sync),
                    ),
                  ],
                ),
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
