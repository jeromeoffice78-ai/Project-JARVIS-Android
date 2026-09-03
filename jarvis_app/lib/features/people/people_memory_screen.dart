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

      if (!mounted) {
        return;
      }

      setState(() => _people = people);
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
          .read(jarvisApiServiceProvider)
          .deletePerson(person.personId);

      if (_confirmedPersonId == person.personId) {
        _confirmedPersonId = null;
      }

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
                  leading: CircleAvatar(
                    child: Text(
                      person.displayName.isEmpty
                          ? '?'
                          : person.displayName[0].toUpperCase(),
                    ),
                  ),
                  title: Text(person.displayName),
                  subtitle: Text(
                    <String>[
                      if (person.relationship.isNotEmpty)
                        person.relationship,
                      if (person.notes.isNotEmpty)
                        person.notes,
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
                'Privacy design: Camera Vision may detect that one or more '
                'faces are present, but Project Jarvis does not store face '
                'templates or automatically identify a person from facial '
                'biometrics. Identity is attached only after you confirm '
                'the saved profile.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
