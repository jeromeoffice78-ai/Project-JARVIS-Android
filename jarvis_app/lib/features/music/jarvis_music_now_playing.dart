import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/network/providers.dart';
import 'jarvis_music_service.dart';

class JarvisMusicNowPlaying
    extends ConsumerWidget {
  const JarvisMusicNowPlaying({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final JarvisMusicService service =
        ref.watch(jarvisMusicServiceProvider);

    final AsyncValue<JarvisMusicState>
        asyncState =
        ref.watch(jarvisMusicStateProvider);

    final JarvisMusicState state =
        asyncState.valueOrNull ??
            service.state;

    if (state.status ==
            JarvisMusicStatus.idle &&
        !state.hasTrack) {
      return const SizedBox.shrink();
    }

    if (state.status ==
            JarvisMusicStatus.searching &&
        !state.hasTrack) {
      return Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHigh,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Jarvis is searching the internet for that song...',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final track = state.track;
    if (track == null) {
      return const SizedBox.shrink();
    }

    return Material(
      elevation: 4,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YoutubePlayer(
            controller: service.controller,
            aspectRatio: 16 / 9,
          ),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              12,
              8,
              8,
              8,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight:
                                      FontWeight
                                          .w700,
                                ),
                      ),
                      if (track.author
                          .trim()
                          .isNotEmpty)
                        Text(
                          track.author,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Play',
                  onPressed: service.play,
                  icon: const Icon(
                    Icons.play_arrow,
                  ),
                ),
                IconButton(
                  tooltip: 'Pause',
                  onPressed: service.pause,
                  icon: const Icon(
                    Icons.pause,
                  ),
                ),
                IconButton(
                  tooltip:
                      'Close player',
                  onPressed: service.clear,
                  icon: const Icon(
                    Icons.close,
                  ),
                ),
              ],
            ),
          ),
          if (state.status ==
              JarvisMusicStatus.error)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                12,
                0,
                12,
                10,
              ),
              child: Text(
                state.errorMessage ??
                    'Music playback error.',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
