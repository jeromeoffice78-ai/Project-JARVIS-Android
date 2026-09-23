import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'person_profile.dart';

class PeopleMemoryScreen extends ConsumerStatefulWidget {
  const PeopleMemoryScreen({super.key});

  @override
  ConsumerState<PeopleMemoryScreen> createState() =>
      _PeopleMemoryScreenState();
}

class _PeopleMemoryScreenState
    extends ConsumerState<PeopleMemoryScreen> {
  List<PersonProfile> _people = const <PersonProfile>[];
  bool _loading = false;
  String? _error;
  String? _confirmedPersonId;
  Set<String> _voiceProfileIds =
      const <String>{};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadPeople);
  }

  Future<void> _loadPeople() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final people =
          await ref.read(jarvisApiServiceProvider).listPeople();
      final Set<String> voiceProfileIds =
          await ref
              .read(jarvisVoiceIdentityServiceProvider)
              .listVoiceProfileIds();

      if (!mounted) {
        return;
      }

      setState(() {
        _people = people;
        _voiceProfileIds = voiceProfileIds;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _enrollVoice(
    PersonProfile person,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Voice enrollment for ${person.displayName}: speak naturally for about 3 seconds.',
        ),
      ),
    );

    try {
      await ref
          .read(jarvisVoiceIdentityServiceProvider)
          .enrollVoice(person.personId);

      if (!mounted) {
        return;
      }

      setState(() {
        _voiceProfileIds =
            <String>{
          ..._voiceProfileIds,
          person.personId,
        };
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Jarvis now has an encrypted voice profile for ${person.displayName}.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _forgetVoice(
    PersonProfile person,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(jarvisVoiceIdentityServiceProvider)
          .deleteVoiceProfile(person.personId);

      if (!mounted) {
        return;
      }

      setState(() {
        _voiceProfileIds =
            <String>{
          ..._voiceProfileIds,
        }..remove(person.personId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voice profile removed for ${person.displayName}.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _identifySpeaker() async {
    if (_voiceProfileIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enroll at least one voice profile first.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Speaker check: talk naturally for about 3 seconds.',
        ),
      ),
    );

    try {
      final match = await ref
          .read(jarvisVoiceIdentityServiceProvider)
          .identifySpeaker();

      if (!mounted) {
        return;
      }

      if (!match.matched ||
          match.personId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Jarvis could not identify the speaker confidently. '
              'Best similarity: ${match.similarity.toStringAsFixed(2)}.',
            ),
          ),
        );
        return;
      }

      PersonProfile? person;
      for (final PersonProfile candidate
          in _people) {
        if (candidate.personId ==
            match.personId) {
          person = candidate;
          break;
        }
      }

      if (person == null) {
        throw StateError(
          'The matched voice profile is no longer linked to a saved person.',
        );
      }

      await _confirm(person);

      await ref
          .read(jarvisRealtimeVoiceServiceProvider)
          .setActiveSpeaker(person);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Speaker identified as ${person.displayName} '
              '(similarity ${match.similarity.toStringAsFixed(2)}).',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _createPerson() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController relationship =
        TextEditingController();
    final TextEditingController notes = TextEditingController();

    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remember a Person'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: relationship,
                  decoration: const InputDecoration(
                    labelText: 'Relationship / context',
                    hintText: 'Friend, coworker, family, client...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Notes Jarvis should remember',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final String displayName = name.text.trim();
    final String relationshipText = relationship.text.trim();
    final String notesText = notes.text.trim();

    name.dispose();
    relationship.dispose();
    notes.dispose();

    if (save != true || displayName.isEmpty) {
      return;
    }

    setState(() => _loading = true);

    try {
      await ref.read(jarvisApiServiceProvider).createPerson(
            displayName: displayName,
            relationship: relationshipText,
            notes: notesText,
          );

      await _loadPeople();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirm(PersonProfile person) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(jarvisApiServiceProvider)
          .confirmPersonPresent(person.personId);

      if (!mounted) {
        return;
      }

      setState(() {
        _confirmedPersonId = person.personId;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${person.displayName} confirmed as present. '
            'Jarvis will use this profile for the current context.',
          ),
        ),
      );

      await _loadPeople();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _clearPresence() async {
    setState(() => _loading = true);

    try {
      await ref
          .read(jarvisApiServiceProvider)
          .clearPersonPresence();

      if (mounted) {
        setState(() => _confirmedPersonId = null);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _delete(PersonProfile person) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Forget Person'),
          content: Text(
            'Remove ${person.displayName} from Jarvis People Memory?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Forget'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(jarvisVoiceIdentityServiceProvider)
          .deleteVoiceProfile(person.personId);

      await ref
          .read(jarvisApiServiceProvider)
          .deletePerson(person.personId);

      if (_confirmedPersonId == person.personId) {
        _confirmedPersonId = null;
      }

      _voiceProfileIds =
          <String>{..._voiceProfileIds}
            ..remove(person.personId);

      await _loadPeople();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadPeople,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.people_alt_outlined),
                    title: Text('People Memory'),
                    subtitle: Text(
                      'Jarvis remembers profiles you create and '
                      'uses them after you confirm who is present.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _loading ? null : _createPerson,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add Person'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _loading ? null : _identifySpeaker,
                        icon: const Icon(
                          Icons.record_voice_over_outlined,
                        ),
                        label: const Text(
                          'Identify Speaker',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _clearPresence,
                        icon: const Icon(Icons.person_off_outlined),
                        label: const Text('Clear Present Person'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orangeAccent,
                ),
                title: const Text('People Memory Error'),
                subtitle: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_people.isEmpty && !_loading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Text(
                  'No people saved yet. Add a person, then when '
                  'Camera Vision detects someone you can confirm '
                  'which saved profile is present.',
                ),
              ),
            ),
          for (final PersonProfile person in _people)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      CircleAvatar(
                        child: Text(
                          person.displayName.isEmpty
                              ? '?'
                              : person.displayName[0].toUpperCase(),
                        ),
                      ),
                      if (_voiceProfileIds
                          .contains(person.personId))
                        const Positioned(
                          right: -5,
                          bottom: -4,
                          child: CircleAvatar(
                            radius: 9,
                            child: Icon(
                              Icons.mic,
                              size: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(person.displayName),
                  subtitle: Text(
                    <String>[
                      if (person.relationship.isNotEmpty)
                        person.relationship,
                      if (person.notes.isNotEmpty)
                        person.notes,
                      if (_voiceProfileIds.contains(
                        person.personId,
                      ))
                        'Voice profile enrolled',
                      if (person.lastSeenAt != null)
                        'Last confirmed: ${person.lastSeenAt}',
                    ].join('\n'),
                  ),
                  isThreeLine:
                      person.relationship.isNotEmpty ||
                          person.notes.isNotEmpty,
                  trailing: PopupMenuButton<String>(
                    onSelected: (String action) {
                      if (action == 'present') {
                        _confirm(person);
                      } else if (action == 'enroll_voice') {
                        _enrollVoice(person);
                      } else if (action == 'forget_voice') {
                        _forgetVoice(person);
                      } else if (action == 'delete') {
                        _delete(person);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'present',
                        child: Text('Confirm Present'),
                      ),
                      PopupMenuItem<String>(
                        value: _voiceProfileIds
                                .contains(person.personId)
                            ? 'forget_voice'
                            : 'enroll_voice',
                        child: Text(
                          _voiceProfileIds
                                  .contains(person.personId)
                              ? 'Forget Voice'
                              : 'Enroll Voice',
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Forget Person'),
                      ),
                    ],
                  ),
                  selected:
                      _confirmedPersonId == person.personId,
                  onTap: () => _confirm(person),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Privacy design: voice recognition is opt-in per saved person. '
                'Jarvis keeps an encrypted numeric speaker embedding on this '
                'Android device and discards the 3-second enrollment recording. '
                'A voice is named only when the match clears a confidence '
                'threshold and separation margin; uncertain matches remain unknown. '
                'Camera Vision still does not store face templates.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
