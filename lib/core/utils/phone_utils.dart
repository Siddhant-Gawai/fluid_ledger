/// Normalize any Indian phone number to 91XXXXXXXXXX format (no + prefix).
/// Matches Supabase auth format: "918766492541"
/// Handles: "9876543210", "09876543210", "+919876543210",
/// "+91 98765 43210", "91-9876543210", "(091) 98765-43210", etc.
/// Returns null if the input can't be normalized.
String? normalizePhone(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  // Strip everything except digits
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');

  // 10 digits → prefix 91
  if (digits.length == 10) return '91$digits';

  // 11 digits starting with 0 → strip 0, prefix 91
  if (digits.length == 11 && digits.startsWith('0')) return '91${digits.substring(1)}';

  // 12 digits starting with 91 → already correct
  if (digits.length == 12 && digits.startsWith('91')) return digits;

  // 13 digits starting with 091 → strip leading 0
  if (digits.length == 13 && digits.startsWith('091')) return digits.substring(1);

  // Can't normalize — return digits only
  return digits.isNotEmpty ? digits : null;
}
