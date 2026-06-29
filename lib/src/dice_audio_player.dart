import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:dice_audio/src/dice_audio_type.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';

class DiceAudioPlayer {
  bool _initialized = false;
  final SoLoud _soloud;
  final Logger _logger = Logger("DiceAudioPlayer");

  final Map<String, AudioSource> _loaded = {};
  final Random _random;
  final int minMillisecondsBetweenRolls;
  final int maxMillisecondsBetweenRolls;

  DiceAudioPlayer({
    Random? random,
    SoLoud? soloud,
    this.minMillisecondsBetweenRolls = 25,
    this.maxMillisecondsBetweenRolls = 50,
  }) : _random = random ?? Random(),
       _soloud = soloud ?? SoLoud.instance;

  Future<void> initialize({Set<DiceAudioType> preloadTypes = const {}}) async {
    if (_initialized) return;
    _logger.info("Initializing...");
    try {
      if (!kIsWeb) {
        final session = await AudioSession.instance;
        await session.configure(
          const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.ambient,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.mixWithOthers,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.sonification,
              usage: AndroidAudioUsage.game,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType
                .gainTransientMayDuck, // Tells Android to lower or mix other apps instead of killing them
          ),
        );
      }

      await _soloud.init();

      for (final preloadType in preloadTypes) {
        for (final asset in preloadType.clips) {
          await _loadAsset(asset);
        }
      }

      _initialized = true;
    } catch (ex) {
      _logger.severe("Failed to initialize.", ex);
      rethrow;
    }
  }

  Future<AudioSource> _loadAsset(String asset) async {
    if (_loaded[asset] == null) {
      _loaded[asset] = await _soloud.loadAsset(
        "packages/dice_audio/assets/$asset",
      );
    }

    return _loaded[asset]!;
  }

  Future<void> _playSound(String asset, double volume) async {
    _logger.fine("Playing sound $asset");
    try {
      if (!_initialized) {
        await initialize();
      }

      final source = await _loadAsset(asset);

      _soloud.play(source, volume: volume);
    } catch (ex) {
      _logger.severe("Failed to play sound $asset", ex);
    }
  }

  Future<void> playMixed(Map<DiceAudioType, int> counts, double volume) async {
    final List<DiceAudioType> remainingToRoll = [
      for (final type in counts.entries)
        for (int i = 0; i < type.value; i++) type.key,
    ];

    final rollCount = remainingToRoll.length;

    Map<DiceAudioType, List<String>> availableClips = {
      for (final type in DiceAudioType.values) type: [...type.clips],
    };

    for (int i = 0; i < rollCount; i++) {
      final die = remainingToRoll[_random.nextInt(remainingToRoll.length)];
      final msDelay = i == 0
          ? 0
          : _random.nextInt(
                  maxMillisecondsBetweenRolls - minMillisecondsBetweenRolls,
                ) +
                minMillisecondsBetweenRolls;

      final clipOptions = availableClips[die]!;
      if (clipOptions.isEmpty) continue;

      final clip = clipOptions[_random.nextInt(clipOptions.length)];
      clipOptions.remove(clip);

      if (msDelay <= 0) {
        await _playSound(clip, volume);
      } else {
        await Future.delayed(Duration(milliseconds: msDelay));
        await _playSound(clip, volume);
      }
    }
  }

  Future<void> play(DiceAudioType dice, int count, double volume) async {
    return playMixed({dice: count}, volume);
  }
}
