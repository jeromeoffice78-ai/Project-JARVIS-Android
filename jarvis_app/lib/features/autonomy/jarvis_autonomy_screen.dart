import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_autonomy_controller.dart';

class JarvisAutonomyScreen
    extends ConsumerStatefulWidget {
  const JarvisAutonomyScreen({super.key});

  @override
  ConsumerState<JarvisAutonomyScreen>
      createState() => _JarvisAutonomyScreenState();
}

class _JarvisAutonomyScreenState
    extends ConsumerState<JarvisAutonomyScreen> {
  final TextEditingController _goalController =
      TextEditingController();

  double _maxSteps = 8;

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<JarvisAutonomyState> value =
        ref.watch(jarvisAutonomyStateProvider);

    final JarvisAutonomyController controller =
        ref.read(jarvisAutonomyControllerProvider);

    final JarvisAutonomyState state =
        value.valueOrNull ?? controller.state;

    if (_goalController.text.isEmpty &&
        state.goal.isNotEmpty) {
      _goalController.text = state.goal;
      _maxSteps = state.maxSteps.toDouble();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('JARVIS Autonomy'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _StatusCard(state: state),
          const SizedBox(height: 16),
          TextField(
            controller: _goalController,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Autonomous goal',
              hintText:
                  'Tell Jarvis the outcome to accomplish.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Maximum execution steps: ${_maxSteps.round()}',
            style: Theme.of(context)
                .textTheme
                .titleSmall,
          ),
          Slider(
            value: _maxSteps,
            min: 1,
            max: 20,
            divisions: 19,
            label: _maxSteps.round().toString(),
            onChanged: state.isActive
                ? null
                : (double value) {
                    setState(() {
                      _maxSteps = value;
                    });
                  },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: state.isActive
                    ? null
                    : () async {
                        final String goal =
                            _goalController.text.trim();

                        if (goal.isEmpty) {
                          return;
                        }

                        await controller.startGoal(
                          goal,
                          maxSteps:
                              _maxSteps.round(),
                        );
                      },
                icon: const Icon(
                  Icons.play_arrow,
                ),
                label: const Text('Start'),
              ),
              OutlinedButton.icon(
                onPressed: state.isActive
                    ? controller.pause
                    : null,
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
              OutlinedButton.icon(
                onPressed:
                    state.status ==
                            JarvisAutonomyStatus.paused
                        ? controller.resume
                        : null,
                icon: const Icon(
                  Icons.play_circle_outline,
                ),
                label: const Text('Resume'),
              ),
              TextButton.icon(
                onPressed:
                    state.status ==
                            JarvisAutonomyStatus.idle
                        ? null
                        : controller.stop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Last execution result',
            style: Theme.of(context)
                .textTheme
                .titleMedium,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant,
              ),
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: SelectableText(
              state.lastResponse.isEmpty
                  ? 'No autonomous step has completed yet.'
                  : state.lastResponse,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Jarvis may continue through multiple steps automatically. Existing device permissions and approval prompts still apply to consequential actions.',
            style: Theme.of(context)
                .textTheme
                .bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
  });

  final JarvisAutonomyState state;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state.status) {
      JarvisAutonomyStatus.running ||
      JarvisAutonomyStatus.waitingForResponse =>
        Colors.green,
      JarvisAutonomyStatus.paused => Colors.orange,
      JarvisAutonomyStatus.completed => Colors.blue,
      JarvisAutonomyStatus.error => Colors.red,
      JarvisAutonomyStatus.idle => Colors.grey,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.smart_toy_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  state.status.name.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  'Step ${state.step}/${state.maxSteps}',
                ),
              ],
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(state.errorMessage!),
            ],
          ],
        ),
      ),
    );
  }
}
