import 'package:flutter/services.dart';

const captureNotesMaxCodeUnits = 50000;

/// Retains the web field's UTF-16 ceiling without truncating Unicode input.
class CaptureNotesFormatter extends TextInputFormatter {
  CaptureNotesFormatter(String initialNotes) {
    reset(initialNotes);
  }

  late TextEditingValue _committed;

  void reset(String notes) {
    _committed = TextEditingValue(
      text: notes,
      selection: TextSelection.collapsed(offset: notes.length),
    );
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.composing.isCollapsed &&
        oldValue.text.length <= captureNotesMaxCodeUnits) {
      _committed = oldValue;
    }
    return acceptCommittedValue(newValue);
  }

  /// Shares committed-value validation with controller events such as focus loss.
  /// Oversized commits return the previous accepted editing value.
  TextEditingValue acceptCommittedValue(TextEditingValue value) {
    if (!value.composing.isCollapsed) {
      return value;
    }
    if (value.text.length > captureNotesMaxCodeUnits) {
      return _committed.copyWith(composing: TextRange.empty);
    }
    _committed = value;
    return value;
  }
}
