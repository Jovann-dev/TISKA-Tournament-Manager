import 'dart:async';

import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'tournament_backend.dart';

class TournamentAccessScreen extends StatefulWidget {
  const TournamentAccessScreen({super.key});

  @override
  State<TournamentAccessScreen> createState() => _TournamentAccessScreenState();
}

class _TournamentAccessScreenState extends State<TournamentAccessScreen> {
  final TextEditingController _tournamentIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final Map<String, String> _savedTournaments = <String, String>{};
  bool _isSubmitting = false;
  bool _isLoadingSavedTournaments = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedTournaments());
  }

  Future<void> _loadSavedTournaments() async {
    try {
      final backend = TournamentBackend();
      final credentials = await backend.loadTournamentCredentials();

      if (!mounted) {
        return;
      }

      setState(() {
        _savedTournaments
          ..clear()
          ..addAll(credentials);
        _isLoadingSavedTournaments = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSavedTournaments = false;
        _errorMessage = 'Unable to load tournaments from the shared backend.';
      });
    }
  }

  Future<void> _openTournament({required bool createNewTournament}) async {
    final tournamentId = _tournamentIdController.text.trim();
    final password = _passwordController.text.trim();

    if (tournamentId.isEmpty) {
      setState(() {
        _errorMessage = 'Tournament ID is required.';
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Password is required.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final backend = TournamentBackend();
      final registrations = await backend.loadTournamentCredentials();

      if (createNewTournament) {
        if (registrations.containsKey(tournamentId)) {
          throw StateError(
            'A tournament with this ID already exists. Please choose another ID.',
          );
        }
        await backend.saveTournamentCredentials(tournamentId, password);
      } else {
        final savedPassword = registrations[tournamentId];
        if (savedPassword == null || savedPassword != password) {
          throw StateError(
            'The tournament ID or password is incorrect.',
          );
        }
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HomeScreen(
            tournamentId: tournamentId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tournamentIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 56,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tournament Access',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open an existing tournament or create a new one to continue.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_isLoadingSavedTournaments && _savedTournaments.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Saved tournaments',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _savedTournaments.keys
                          .map(
                            (tournamentId) => ActionChip(
                              label: Text(tournamentId),
                              avatar: const Icon(Icons.folder_open_rounded, size: 16),
                              onPressed: () {
                                _tournamentIdController.text = tournamentId;
                                _passwordController.clear();
                                setState(() {
                                  _errorMessage = null;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_tournamentIdController.text.isNotEmpty &&
                      _savedTournaments.containsKey(_tournamentIdController.text)) ...[
                    TextButton.icon(
                      onPressed: () {
                        _passwordController.clear();
                        setState(() {
                          _errorMessage = null;
                        });
                        _openTournament(createNewTournament: false);
                      },
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Continue last tournament'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextFormField(
                    controller: _tournamentIdController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Tournament ID',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_isSubmitting) {
                        _openTournament(createNewTournament: false);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _openTournament(createNewTournament: false),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Open Tournament'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _openTournament(createNewTournament: true),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create New Tournament'),
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
