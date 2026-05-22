import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

/// Flame component rendering a single 3D-like physics-animated die.
class DiceComponent extends PositionComponent with TapCallbacks {
  final int index;
  final VoidCallback onTap;

  // Visual/Physics state
  int visualValue = 1;
  int targetValue = 1;
  bool held = false;
  bool unrolled = false;
  
  double rollTimer = 0.0;
  double rotationTorque = 0.0;
  double scaleFactor = 1.0;
  
  double _rollTickTimer = 0.0;
  double _springVelocity = 0.0;
  
  // Spring constant definitions for elastic feel
  final double _springK = 220.0;     // stiffness
  final double _springDamping = 14.0; // damping friction

  DiceComponent({
    required this.index,
    required this.onTap,
    required Vector2 size,
    required Vector2 position,
  }) : super(size: size, position: position, anchor: Anchor.center);

  /// Triggers a roll animation with random starting torque and duration.
  void roll(int resultValue) {
    targetValue = resultValue;
    // Set rolling physics parameters
    rollTimer = 0.8 + Random().nextDouble() * 0.4; // roll duration: 0.8s to 1.2s
    rotationTorque = (Random().nextBool() ? 1.0 : -1.0) * (15.0 + Random().nextDouble() * 10.0); // rotational torque speed
    
    // Initial squash factor
    scaleFactor = 0.7;
    _springVelocity = 0.0;
    _rollTickTimer = 0.0;
  }

  /// Triggers a bounce scale when the die is toggled.
  void triggerTapBounce() {
    scaleFactor = held ? 1.15 : 0.85;
    _springVelocity = held ? 4.0 : -4.0;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (rollTimer > 0) {
      rollTimer -= dt;
      // Rotational torque simulation
      angle += rotationTorque * dt;
      // Damping torque (simulating drag)
      rotationTorque *= exp(-1.5 * dt);

      // Flash numbers rapidly during rolling for visual juice
      _rollTickTimer += dt;
      if (_rollTickTimer > 0.06) {
        _rollTickTimer = 0.0;
        visualValue = Random().nextInt(6) + 1;
      }

      // Finish rolling landing
      if (rollTimer <= 0) {
        visualValue = targetValue;
        angle = 0; // Snap upright
        // Elastic rebound bounce
        scaleFactor = 1.25;
        _springVelocity = 5.0;
      }
    } else {
      // Spring elastic bounce back to scale 1.0
      double displacement = scaleFactor - 1.0;
      double springForce = -_springK * displacement - _springDamping * _springVelocity;
      _springVelocity += springForce * dt;
      scaleFactor += _springVelocity * dt;
    }
  }

  @override
  void render(ui.Canvas canvas) {
    // Save state to perform scale and rotate around center
    canvas.save();
    
    // Scale transformation
    canvas.scale(scaleFactor, scaleFactor);

    final rect = Rect.fromLTWH(-size.x / 2, -size.y / 2, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    // 1. High-end drop shadow (Ludo King visual feel)
    final shadowPaint = Paint()
      ..color = const Color(0x88020617)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(rrect.shift(const Offset(4, 8)), shadowPaint);

    // 2. Gold Glow outline when held
    if (held && !unrolled) {
      final glowPaint = Paint()
        ..color = const Color(0xFFFBBC05).withOpacity(0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12);
      canvas.drawRRect(rrect, glowPaint);
    }

    if (unrolled) {
      // 3. Unrolled Die Body (Dark Slate Grey)
      final bodyPaint = Paint()..color = const Color(0xFF202430);
      canvas.drawRRect(rrect, bodyPaint);

      // 4. Border stroke
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withOpacity(0.1);
      canvas.drawRRect(rrect, borderPaint);

      // 5. Draw Center 4-Pointed Star
      _drawStar(canvas, size.x);
    } else {
      // 3. Die Body (Ivory / Soft Cream gradient for a premium board game look)
      final bodyPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(-size.x / 2, -size.y / 2),
          Offset(size.x / 2, size.y / 2),
          const [
            Color(0xFFFCF9F2), // Premium Ivory start
            Color(0xFFEADFC9), // Soft cream/bone end
          ],
        );
      canvas.drawRRect(rrect, bodyPaint);

      // 4. Border stroke
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = held ? 3.0 : 1.5
        ..color = held ? const Color(0xFFFBBC05) : const Color(0xFF1F2430).withOpacity(0.45);
      canvas.drawRRect(rrect, borderPaint);

      // 5. Draw Pips (Slate dark grey/blue)
      final pipPaint = Paint()
        ..color = const Color(0xFF2C3E50)
        ..style = PaintingStyle.fill;
        
      final pipDepthPaint = Paint()
        ..color = const Color(0x1A000000)
        ..style = PaintingStyle.fill;

      _drawPips(canvas, visualValue, size.x, pipPaint, pipDepthPaint);
    }

    canvas.restore();
  }

  void _drawStar(ui.Canvas canvas, double size) {
    final double outerRadius = size * 0.22;
    final double innerRadius = size * 0.08;
    const double cx = 0;
    const double cy = 0;
    const int spikes = 4;
    
    final Path path = Path();
    double rot = (pi / 2) * 3;
    const double step = pi / spikes;

    path.moveTo(cx, cy - outerRadius);
    for (int i = 0; i < spikes; i++) {
      double x = cx + cos(rot) * outerRadius;
      double y = cy + sin(rot) * outerRadius;
      path.lineTo(x, y);
      rot += step;

      x = cx + cos(rot) * innerRadius;
      y = cy + sin(rot) * innerRadius;
      path.lineTo(x, y);
      rot += step;
    }
    path.close();

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(path, paint);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (rollTimer > 0) return; // Ignore input while rolling
    onTap();
  }

  /// Draws die pips helper.
  void _drawPips(ui.Canvas canvas, int value, double size, Paint pipPaint, Paint depthPaint) {
    final double radius = size * 0.085;
    final double offset = size * 0.25;

    void drawPip(double x, double y) {
      // Small 3D depth shadow under pip
      canvas.drawCircle(Offset(x, y + 1), radius, depthPaint);
      canvas.drawCircle(Offset(x, y), radius, pipPaint);
    }

    switch (value) {
      case 1:
        drawPip(0, 0);
        break;
      case 2:
        drawPip(-offset, -offset);
        drawPip(offset, offset);
        break;
      case 3:
        drawPip(-offset, -offset);
        drawPip(0, 0);
        drawPip(offset, offset);
        break;
      case 4:
        drawPip(-offset, -offset);
        drawPip(offset, -offset);
        drawPip(-offset, offset);
        drawPip(offset, offset);
        break;
      case 5:
        drawPip(-offset, -offset);
        drawPip(offset, -offset);
        drawPip(0, 0);
        drawPip(-offset, offset);
        drawPip(offset, offset);
        break;
      case 6:
        drawPip(-offset, -offset);
        drawPip(offset, -offset);
        drawPip(-offset, 0);
        drawPip(offset, 0);
        drawPip(-offset, offset);
        drawPip(offset, offset);
        break;
    }
  }
}
