/// Amount rules shared by both apps: integer rupees from 100 to 10000.
class AmountValidator {
  AmountValidator._();

  static const int minAmount = 100;
  static const int maxAmount = 10000;
  static const List<int> predefinedAmounts = [
    100,
    500,
    1000,
    2000,
    5000,
    10000
  ];

  static bool isValid(int? amount) =>
      amount != null && amount >= minAmount && amount <= maxAmount;

  /// Parses user input such as "1,000" or " 500 ".
  /// Returns `null` when the input is not a whole-number amount in range.
  static int? tryParse(String raw) {
    final cleaned = raw.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return null;
    final value = int.tryParse(cleaned);
    if (value == null) return null;
    return isValid(value) ? value : null;
  }

  /// Same as [tryParse] but throws with a user-facing message.
  static int parse(String raw) {
    final value = tryParse(raw);
    if (value == null) {
      throw FormatException(
        'Enter an amount between ₹$minAmount and ₹$maxAmount',
        raw,
      );
    }
    return value;
  }

  /// Formats integer rupees for display: 1000 -> "1,000".
  static String format(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
