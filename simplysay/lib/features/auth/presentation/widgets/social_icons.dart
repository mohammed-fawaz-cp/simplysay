import 'package:flutter/material.dart';

/// 100% Accurate custom painters for Google, Microsoft, and Meta logos
/// derived directly from loginscreen.html SVGs.

class GoogleLogoWidget extends StatelessWidget {
  final double size;
  const GoogleLogoWidget({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    // Blue G Arc
    final pBlue = Paint()..color = const Color(0xFF4285F4);
    final pathBlue = Path()
      ..moveTo(22.56, 12.25)
      ..cubicTo(22.56, 11.47, 22.49, 10.72, 22.36, 10.0)
      ..lineTo(12.0, 10.0)
      ..lineTo(12.0, 14.26)
      ..lineTo(17.92, 14.26)
      ..cubicTo(17.66, 15.63, 16.88, 16.79, 15.71, 17.57)
      ..lineTo(15.71, 20.34)
      ..lineTo(19.28, 20.34)
      ..cubicTo(21.36, 18.42, 22.56, 15.6, 22.56, 12.25)
      ..close();
    canvas.drawPath(pathBlue, pBlue);

    // Green Arc
    final pGreen = Paint()..color = const Color(0xFF34A853);
    final pathGreen = Path()
      ..moveTo(12.0, 23.0)
      ..cubicTo(14.97, 23.0, 17.46, 22.02, 19.28, 20.34)
      ..lineTo(15.71, 17.57)
      ..cubicTo(14.73, 18.23, 13.48, 18.63, 12.0, 18.63)
      ..cubicTo(9.14, 18.63, 6.71, 16.7, 5.84, 14.1)
      ..lineTo(2.18, 14.1)
      ..lineTo(2.18, 16.94)
      ..cubicTo(3.99, 20.53, 7.7, 23.0, 12.0, 23.0)
      ..close();
    canvas.drawPath(pathGreen, pGreen);

    // Yellow Arc
    final pYellow = Paint()..color = const Color(0xFFFBBC05);
    final pathYellow = Path()
      ..moveTo(5.84, 14.09)
      ..cubicTo(5.62, 13.43, 5.49, 12.73, 5.49, 12.0)
      ..cubicTo(5.49, 11.27, 5.62, 10.57, 5.84, 9.91)
      ..lineTo(5.84, 7.07)
      ..lineTo(2.18, 7.07)
      ..cubicTo(1.43, 8.55, 1.0, 10.22, 1.0, 12.0)
      ..cubicTo(1.0, 13.78, 1.43, 15.45, 2.18, 16.93)
      ..lineTo(5.03, 14.71)
      ..lineTo(5.84, 14.09)
      ..close();
    canvas.drawPath(pathYellow, pYellow);

    // Red Arc
    final pRed = Paint()..color = const Color(0xFFEA4335);
    final pathRed = Path()
      ..moveTo(12.0, 5.38)
      ..cubicTo(13.62, 5.38, 15.06, 5.94, 16.21, 7.02)
      ..lineTo(19.36, 3.87)
      ..cubicTo(17.45, 2.09, 14.97, 1.0, 12.0, 1.0)
      ..cubicTo(7.7, 1.0, 3.99, 3.47, 2.18, 7.07)
      ..lineTo(5.84, 9.91)
      ..cubicTo(6.71, 7.31, 9.14, 5.38, 12.0, 5.38)
      ..close();
    canvas.drawPath(pathRed, pRed);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MicrosoftLogoWidget extends StatelessWidget {
  final double size;
  const MicrosoftLogoWidget({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MicrosoftLogoPainter(),
    );
  }
}

class _MicrosoftLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 23.0;
    canvas.scale(scale, scale);

    final pRed = Paint()..color = const Color(0xFFF25022);
    final pGreen = Paint()..color = const Color(0xFF7FBA00);
    final pBlue = Paint()..color = const Color(0xFF00A4EF);
    final pYellow = Paint()..color = const Color(0xFFFFB900);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 10.9, 10.9), pRed);
    canvas.drawRect(const Rect.fromLTWH(12.1, 0, 10.9, 10.9), pGreen);
    canvas.drawRect(const Rect.fromLTWH(0, 12.1, 10.9, 10.9), pBlue);
    canvas.drawRect(const Rect.fromLTWH(12.1, 12.1, 10.9, 10.9), pYellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MetaLogoWidget extends StatelessWidget {
  final double size;
  const MetaLogoWidget({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MetaLogoPainter(),
    );
  }
}

class _MetaLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    final paint = Paint()..color = const Color(0xFF0668E1);
    final path = Path()
      ..moveTo(12.0, 2.0)
      ..cubicTo(6.477, 2.0, 2.0, 6.477, 2.0, 12.0)
      ..cubicTo(2.0, 16.991, 5.657, 21.128, 10.438, 21.878)
      ..lineTo(10.438, 14.891)
      ..lineTo(7.898, 14.891)
      ..lineTo(7.898, 12.0)
      ..lineTo(10.438, 12.0)
      ..lineTo(10.438, 9.797)
      ..cubicTo(10.438, 7.291, 11.93, 5.907, 14.215, 5.907)
      ..cubicTo(15.309, 5.907, 16.453, 6.102, 16.453, 6.102)
      ..lineTo(16.453, 8.562)
      ..lineTo(15.193, 8.562)
      ..cubicTo(13.95, 8.562, 13.563, 9.333, 13.563, 10.124)
      ..lineTo(13.563, 12.0)
      ..lineTo(16.336, 12.0)
      ..lineTo(15.893, 14.89)
      ..lineTo(13.563, 14.89)
      ..lineTo(13.563, 21.878)
      ..cubicTo(18.343, 21.128, 22.0, 16.991, 22.0, 12.0)
      ..cubicTo(22.0, 6.477, 17.523, 2.0, 12.0, 2.0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
