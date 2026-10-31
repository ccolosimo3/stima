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
    // Let the IME finish composition; only committed text reaches the caller.
    if (!newValue.composing.isCollapsed) {
      return newValue;
    }
    if (newValue.text.length > captureNotesMaxCodeUnits) {
      return _committed.copyWith(composing: TextRange.empty);
    }
    _committed = newValue;
    return newValue;
  }
}
