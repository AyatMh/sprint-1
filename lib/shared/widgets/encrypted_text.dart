import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

// Flutter port of the "EncryptedText" effect: the text starts as scrambled
// random characters and is revealed left-to-right, one character per
// [revealDelay], while the not-yet-revealed tail keeps shuffling.
class EncryptedText extends StatefulWidget {
  final String text;
  final TextStyle? revealedStyle;
  final TextStyle? encryptedStyle;
  final Duration revealDelay;
  final Duration startDelay;

  const EncryptedText({
    super.key,
    required this.text,
    this.revealedStyle,
    this.encryptedStyle,
    this.revealDelay = const Duration(milliseconds: 50),
    this.startDelay = Duration.zero,
  });

  @override
  State<EncryptedText> createState() => _EncryptedTextState();
}

class _EncryptedTextState extends State<EncryptedText> {
  static const String _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%&*';

  final Random _rng = Random();
  Timer? _timer;
  int _revealed = 0;
  late String _scrambledTail;
  late DateTime _revealStartsAt;

  @override
  void initState() {
    super.initState();
    _revealStartsAt = DateTime.now().add(widget.startDelay);
    _scrambledTail = _scramble(widget.text);
    _timer = Timer.periodic(widget.revealDelay, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Random characters, but spaces stay spaces so word shapes are kept.
  String _scramble(String source) {
    return String.fromCharCodes(source.runes.map((r) {
      if (r == 0x20) return r;
      return _charset.codeUnitAt(_rng.nextInt(_charset.length));
    }));
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      if (DateTime.now().isAfter(_revealStartsAt)) {
        _revealed++;
      }
      if (_revealed >= widget.text.length) {
        _revealed = widget.text.length;
        _timer?.cancel();
      } else {
        _scrambledTail = _scramble(widget.text.substring(_revealed));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final revealedPart = widget.text.substring(0, _revealed);
    final encryptedPart =
        _revealed >= widget.text.length ? '' : _scrambledTail;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: revealedPart, style: widget.revealedStyle),
          TextSpan(text: encryptedPart, style: widget.encryptedStyle),
        ],
      ),
    );
  }
}
