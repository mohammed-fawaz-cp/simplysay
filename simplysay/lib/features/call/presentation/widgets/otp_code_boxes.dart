import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpCodeBoxesDisplay extends StatelessWidget {
  final String code; // Expected format "XXX-YYY-ZZZ" or 9 chars

  const OtpCodeBoxesDisplay({
    super.key,
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanCode = code.replaceAll('-', '');
    final chars = List.generate(9, (index) {
      if (index < cleanCode.length) return cleanCode[index];
      return '';
    });

    Widget buildBox(String char) {
      return Container(
        width: 34,
        height: 46,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          char.toUpperCase(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    Widget buildHyphen() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          '-',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return FittedBox(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Block 1
          buildBox(chars[0]),
          const SizedBox(width: 5),
          buildBox(chars[1]),
          const SizedBox(width: 5),
          buildBox(chars[2]),

          buildHyphen(),

          // Block 2
          buildBox(chars[3]),
          const SizedBox(width: 5),
          buildBox(chars[4]),
          const SizedBox(width: 5),
          buildBox(chars[5]),

          buildHyphen(),

          // Block 3
          buildBox(chars[6]),
          const SizedBox(width: 5),
          buildBox(chars[7]),
          const SizedBox(width: 5),
          buildBox(chars[8]),
        ],
      ),
    );
  }
}

class OtpCodeBoxesInput extends StatefulWidget {
  final ValueChanged<String> onChanged;

  const OtpCodeBoxesInput({
    super.key,
    required this.onChanged,
  });

  @override
  State<OtpCodeBoxesInput> createState() => _OtpCodeBoxesInputState();
}

class _OtpCodeBoxesInputState extends State<OtpCodeBoxesInput> {
  final List<TextEditingController> _controllers =
      List.generate(9, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(9, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _notifyChange() {
    final raw = _controllers.map((c) => c.text).join();
    widget.onChanged(raw);
  }

  void _onTextChanged(int index, String value) {
    if (value.length > 1) {
      // Paste detected (e.g. "K7P9W2M4X" or "K7P-9W2-M4X")
      final clean = value.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
      for (int i = 0; i < 9; i++) {
        if (i < clean.length) {
          _controllers[i].text = clean[i];
        } else {
          _controllers[i].clear();
        }
      }
      _notifyChange();
      FocusScope.of(context).unfocus();
      return;
    }

    if (value.isNotEmpty) {
      _controllers[index].text = value.toUpperCase();
      _notifyChange();
      if (index < 8) {
        FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
      } else {
        FocusScope.of(context).unfocus();
      }
    } else {
      _notifyChange();
    }
  }

  Widget _buildBox(int index) {
    final theme = Theme.of(context);
    return Container(
      width: 34,
      height: 46,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _focusNodes[index].hasFocus
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.3),
          width: _focusNodes[index].hasFocus ? 2.0 : 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _controllers[index].text.isEmpty &&
              index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
        },
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          keyboardType: TextInputType.text,
          maxLength: 1,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (val) => _onTextChanged(index, val),
        ),
      ),
    );
  }

  Widget _buildHyphen() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '-',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Block 1
          _buildBox(0),
          const SizedBox(width: 5),
          _buildBox(1),
          const SizedBox(width: 5),
          _buildBox(2),

          _buildHyphen(),

          // Block 3
          _buildBox(3),
          const SizedBox(width: 5),
          _buildBox(4),
          const SizedBox(width: 5),
          _buildBox(5),

          _buildHyphen(),

          // Block 3
          _buildBox(6),
          const SizedBox(width: 5),
          _buildBox(7),
          const SizedBox(width: 5),
          _buildBox(8),
        ],
      ),
    );
  }
}
