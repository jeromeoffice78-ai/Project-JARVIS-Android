import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'legal_core.dart';

const Color _stagePanel = Color(0xFF071219);
const Color _stagePanel2 = Color(0xFF0C1A22);
const Color _stageCyan = Color(0xFF38E8FF);
const Color _stageGold = Color(0xFFFFC857);
const Color _stageGreen = Color(0xFF62E6A7);
const Color _stageMuted = Color(0xFF91A6B2);
const Color _stageBorder = Color(0xFF183746);

final class LeadershipProfile {
  const LeadershipProfile({
    required this.name,
    required this.title,
    required this.focus,
    required this.icon,
    required this.accent,
    this.isChairman = false,
  });

  final String name;
  final String title;
  final String focus;
  final IconData icon;
  final Color accent;
  final bool isChairman;
}

List<LeadershipProfile> get _boardProfiles {
  const List<IconData> icons = <IconData>[
    Icons.workspace_premium_rounded,
    Icons.account_balance_rounded,
    Icons.gavel_rounded,
    Icons.fact_check_rounded,
    Icons.trending_up_rounded,
    Icons.security_rounded,
    Icons.payments_rounded,
  ];
  const List<Color> accents = <Color>[
    _stageGold,
    _stageCyan,
    _stageGold,
    _stageGreen,
    _stageCyan,
    _stageGold,
    _stageGreen,
  ];

  return enterpriseBoard.asMap().entries.map((MapEntry<int, BoardMember> entry) {
    final BoardMember member = entry.value;
    return LeadershipProfile(
      name: member.name,
      title: member.seat,
      focus: member.focus,
      icon: icons[entry.key % icons.length],
      accent: accents[entry.key % accents.length],
      isChairman: member.isHuman,
    );
  }).toList(growable: false);
}

List<LeadershipProfile> get _departmentProfiles {
  const Map<String, String> names = <String, String>{
    'LEGAL_CPO': 'Lex',
    'LEGAL_ARCH': 'Aegis',
    'LEGAL_COUNSEL': 'Titan',
    'LEGAL_INVESTIGATOR': 'Cipher',
    'LEGAL_QA': 'Sentinel',
  };
  const Map<String, IconData> icons = <String, IconData>{
    'LEGAL_CPO': Icons.psychology_alt_rounded,
    'LEGAL_ARCH': Icons.public_rounded,
    'LEGAL_COUNSEL': Icons.balance_rounded,
    'LEGAL_INVESTIGATOR': Icons.manage_search_rounded,
    'LEGAL_QA': Icons.verified_user_rounded,
  };
  const Map<String, Color> accents = <String, Color>{
    'LEGAL_CPO': _stageCyan,
    'LEGAL_ARCH': _stageGold,
    'LEGAL_COUNSEL': _stageGreen,
    'LEGAL_INVESTIGATOR': _stageCyan,
    'LEGAL_QA': _stageGold,
  };

  return legalDirectors.map((LegalDirector director) {
    return LeadershipProfile(
      name: names[director.code] ?? director.code,
      title: director.title,
      focus: director.mission,
      icon: icons[director.code] ?? Icons.account_balance_rounded,
      accent: accents[director.code] ?? _stageCyan,
    );
  }).toList(growable: false);
}

class AnimatedBoardLeadership extends StatelessWidget {
  const AnimatedBoardLeadership({super.key});

  @override
  Widget build(BuildContext context) {
    return _AnimatedLeadershipStage(
      title: 'BOARD OF DIRECTORS',
      subtitle: '7-member executive council • Chairman authority live',
      profiles: _boardProfiles,
      speakerInterval: const Duration(seconds: 4),
    );
  }
}

class AnimatedDepartmentHeads extends StatelessWidget {
  const AnimatedDepartmentHeads({super.key});

  @override
  Widget build(BuildContext context) {
    return _AnimatedLeadershipStage(
      title: 'LEGAL DEPARTMENT HEADS',
      subtitle: 'Managing legal directors • synchronized command layer',
      profiles: _departmentProfiles,
      speakerInterval: const Duration(seconds: 3),
    );
  }
}

class _AnimatedLeadershipStage extends StatefulWidget {
  const _AnimatedLeadershipStage({
    required this.title,
    required this.subtitle,
    required this.profiles,
    required this.speakerInterval,
  });

  final String title;
  final String subtitle;
  final List<LeadershipProfile> profiles;
  final Duration speakerInterval;

  @override
  State<_AnimatedLeadershipStage> createState() => _AnimatedLeadershipStageState();
}

class _AnimatedLeadershipStageState extends State<_AnimatedLeadershipStage>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  Timer? _speakerTimer;
  int _activeSpeaker = 0;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _speakerTimer = Timer.periodic(widget.speakerInterval, (_) {
      if (!mounted || widget.profiles.isEmpty) return;
      setState(() {
        _activeSpeaker = (_activeSpeaker + 1) % widget.profiles.length;
      });
    });
  }

  @override
  void dispose() {
    _speakerTimer?.cancel();
    _ambientController.dispose();
    super.dispose();
  }

  void _showProfile(LeadershipProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF081219),
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _LeadershipAvatar(
                      profile: profile,
                      animation: _ambientController,
                      active: true,
                      compact: true,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            profile.name,
                            style: TextStyle(
                              color: profile.accent,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            profile.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'AUTHORITY / MISSION',
                  style: TextStyle(
                    color: _stageMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  profile.focus,
                  style: const TextStyle(
                    color: Color(0xFFD9E5EA),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    const Icon(Icons.circle, color: _stageGreen, size: 9),
                    const SizedBox(width: 7),
                    Text(
                      profile.isChairman
                          ? 'CHAIRMAN • FINAL AUTHORITY'
                          : 'AI EXECUTIVE • ONLINE',
                      style: const TextStyle(
                        color: _stageGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_stagePanel, _stagePanel2],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x5538E8FF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2238E8FF),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.hub_rounded, color: _stageCyan, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: _stageMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const _LivePulseBadge(),
            ],
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.profiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (BuildContext context, int index) {
                final LeadershipProfile profile = widget.profiles[index];
                return _AnimatedLeadershipCard(
                  profile: profile,
                  active: index == _activeSpeaker,
                  animation: _ambientController,
                  reduceMotion: reduceMotion,
                  onTap: () => _showProfile(profile),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: widget.profiles.isEmpty
                ? const SizedBox.shrink()
                : Row(
                    key: ValueKey<int>(_activeSpeaker),
                    children: <Widget>[
                      const Icon(Icons.graphic_eq_rounded, color: _stageGreen, size: 16),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${widget.profiles[_activeSpeaker].name.toUpperCase()} IS ACTIVE • ${widget.profiles[_activeSpeaker].title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _stageGreen,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedLeadershipCard extends StatelessWidget {
  const _AnimatedLeadershipCard({
    required this.profile,
    required this.active,
    required this.animation,
    required this.reduceMotion,
    required this.onTap,
  });

  final LeadershipProfile profile;
  final bool active;
  final Animation<double> animation;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double wave = reduceMotion ? 0 : math.sin(animation.value * math.pi);
        final double lift = active ? -3.5 * wave : -1.2 * wave;
        final double glow = active ? .34 + (.22 * wave) : .12 + (.05 * wave);
        return Transform.translate(
          offset: Offset(0, lift),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: 132,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF102631) : const Color(0xFF0B171E),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: active ? profile.accent : _stageBorder,
                  width: active ? 1.4 : 1,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: profile.accent.withValues(alpha: glow),
                    blurRadius: active ? 18 : 8,
                    spreadRadius: active ? 1 : 0,
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  _LeadershipAvatar(
                    profile: profile,
                    animation: animation,
                    active: active,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: profile.isChairman ? _stageGold : profile.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Expanded(
                    child: Text(
                      profile.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFC7D4DA),
                        fontSize: 9,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: active ? 7 : 5,
                        height: active ? 7 : 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? _stageGreen : _stageMuted,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        active ? 'SPEAKING' : 'ONLINE',
                        style: TextStyle(
                          color: active ? _stageGreen : _stageMuted,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LeadershipAvatar extends StatelessWidget {
  const _LeadershipAvatar({
    required this.profile,
    required this.animation,
    required this.active,
    this.compact = false,
  });

  final LeadershipProfile profile;
  final Animation<double> animation;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 58 : 64;
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double pulse = active ? .96 + (.08 * animation.value) : 1;
        return Transform.scale(
          scale: pulse,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      profile.accent.withValues(alpha: .28),
                      const Color(0xFF0A151C),
                    ],
                  ),
                  border: Border.all(color: profile.accent, width: active ? 2 : 1),
                  boxShadow: <BoxShadow>[
                    if (active)
                      BoxShadow(
                        color: profile.accent.withValues(alpha: .35),
                        blurRadius: 16,
                      ),
                  ],
                ),
                child: Icon(
                  profile.icon,
                  color: profile.isChairman ? _stageGold : profile.accent,
                  size: compact ? 28 : 31,
                ),
              ),
              if (active)
                SizedBox(
                  width: size + 12,
                  height: size + 12,
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 1.2,
                    color: profile.accent.withValues(alpha: .65),
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LivePulseBadge extends StatefulWidget {
  const _LivePulseBadge();

  @override
  State<_LivePulseBadge> createState() => _LivePulseBadgeState();
}

class _LivePulseBadgeState extends State<_LivePulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: .58, end: 1).animate(_controller),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x1462E6A7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x5562E6A7)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.circle, color: _stageGreen, size: 7),
            SizedBox(width: 5),
            Text(
              'LIVE',
              style: TextStyle(
                color: _stageGreen,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
