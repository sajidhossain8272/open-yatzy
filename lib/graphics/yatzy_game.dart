import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/yatzy_engine.dart';
import 'dice_component.dart';

/// The Flame game engine implementation coordinating the canvas layout and dice rendering.
class YatzyGame extends FlameGame with HasTapCallbacks {
  final YatzyEngine engine;
  final VoidCallback onStateChanged;

  final List<DiceComponent> _diceComponents = [];

  YatzyGame({
    required this.engine,
    required this.onStateChanged,
  });

  @override
  Color backgroundColor() => const Color(0xFF323846); // Matching outer card container color

  @override
  Future<void> onLoad() async {
    super.onLoad();

    // Size of individual dice on canvas (e.g. 70x70)
    final double dieSize = size.x > 500 ? 80.0 : 65.0;
    final Vector2 diceSizeVector = Vector2(dieSize, dieSize);

    // Initial spacing calculations
    final double spacing = size.x / 6;
    final double centerY = size.y / 2;

    for (int i = 0; i < 5; i++) {
      final die = DiceComponent(
        index: i,
        onTap: () {
          // Toggle hold in domain engine
          final succeeded = engine.toggleHold(i);
          if (succeeded) {
            _diceComponents[i].held = engine.heldDice[i];
            _diceComponents[i].triggerTapBounce();
            HapticFeedback.lightImpact();
            SystemSound.play(SystemSoundType.click);
            onStateChanged();
          }
        },
        size: diceSizeVector,
        position: Vector2(spacing * (i + 1), centerY),
      );
      
      die.visualValue = engine.diceValues[i];
      die.held = engine.heldDice[i];
      die.unrolled = engine.rollsRemaining == 3;
      _diceComponents.add(die);
      add(die);
    }
  }

  /// Triggers roll animation for all active (unheld) dice using new engine values.
  void triggerRollAnimation() {
    final values = engine.diceValues;
    final held = engine.heldDice;

    for (int i = 0; i < 5; i++) {
      // Sync hold state first
      _diceComponents[i].held = held[i];
      _diceComponents[i].unrolled = false;
      
      if (!held[i] || engine.rollsRemaining == 2) {
        // Roll animation with target value
        _diceComponents[i].roll(values[i]);
      }
    }
  }

  /// Reset visual holds and values to match engine reset.
  void resetVisuals() {
    for (int i = 0; i < 5; i++) {
      _diceComponents[i].held = false;
      _diceComponents[i].visualValue = 1;
      _diceComponents[i].targetValue = 1;
      _diceComponents[i].angle = 0;
      _diceComponents[i].scaleFactor = 1.0;
      _diceComponents[i].unrolled = true;
    }
  }

  /// Sync visual dice state to match current engine values and holds.
  void syncVisualsToEngine() {
    if (_diceComponents.length == 5) {
      final bool unrolledState = engine.rollsRemaining == 3;
      for (int i = 0; i < 5; i++) {
        _diceComponents[i].held = engine.heldDice[i];
        _diceComponents[i].visualValue = engine.diceValues[i];
        _diceComponents[i].targetValue = engine.diceValues[i];
        _diceComponents[i].angle = 0;
        _diceComponents[i].scaleFactor = 1.0;
        _diceComponents[i].unrolled = unrolledState;
      }
    }
  }

  /// Check if any die is currently rolling.
  bool isAnyDieRolling() {
    if (_diceComponents.isEmpty) return false;
    return _diceComponents.any((die) => die.rollTimer > 0);
  }

  bool _wasRolling = false;

  @override
  void update(double dt) {
    super.update(dt);
    final currentlyRolling = isAnyDieRolling();
    if (_wasRolling && !currentlyRolling) {
      onStateChanged(); // Re-render UI to show points preview and enable scoring
    }
    _wasRolling = currentlyRolling;
  }

  @override
  void onGameResize(Vector2 canvasSize) {
    super.onGameResize(canvasSize);

    if (_diceComponents.length == 5) {
      final double dieSize = canvasSize.x > 500 ? 80.0 : 65.0;
      final Vector2 diceSizeVector = Vector2(dieSize, dieSize);

      final double spacing = canvasSize.x / 6;
      final double centerY = canvasSize.y / 2;

      for (int i = 0; i < 5; i++) {
        _diceComponents[i].size = diceSizeVector;
        _diceComponents[i].position = Vector2(spacing * (i + 1), centerY);
      }
    }
  }
}
