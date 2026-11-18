/// Business rules ported from the web app's services/rulesEngine.ts.
/// (The server still validates payloads; these give instant feedback on device.)
class RuleResult {
  final bool allowed;
  final String message;
  const RuleResult(this.allowed, [this.message = '']);
  static const ok = RuleResult(true);
}

/// R3.2 no check-in on approved leave, R3.3 no second check-in until >= 8h logged.
RuleResult canCheckIn({
  required String shiftDate,
  required Set<String> approvedLeaveDates,
  required double hoursLoggedToday,
}) {
  if (approvedLeaveDates.contains(shiftDate)) {
    return const RuleResult(false, 'You are on approved leave on this date and cannot be marked present.');
  }
  if (hoursLoggedToday > 0 && hoursLoggedToday < 8) {
    return const RuleResult(false, 'Cannot check in again today until at least 8 hours have been logged.');
  }
  return RuleResult.ok;
}

/// R3.5 attendance older than 1 day is locked.
RuleResult canEditAttendance(String shiftDate) {
  final d = DateTime.tryParse(shiftDate);
  if (d == null) return RuleResult.ok;
  final age = DateTime.now().difference(d).inHours / 24.0;
  if (age > 1) return const RuleResult(false, 'Attendance more than 1 day old is locked and cannot be edited.');
  return RuleResult.ok;
}

/// R4.2 overlapping leave and end-before-start are not allowed.
RuleResult canApplyLeave(String from, String to, List<List<String>> existing) {
  final nf = DateTime.tryParse(from);
  final nt = DateTime.tryParse(to);
  if (nf == null || nt == null) return const RuleResult(false, 'Enter valid dates.');
  if (nt.isBefore(nf)) return const RuleResult(false, 'Leave end date cannot be before the start date.');
  for (final e in existing) {
    final ef = DateTime.tryParse(e[0]);
    final et = DateTime.tryParse(e[1]);
    if (ef == null || et == null) continue;
    if (!nf.isAfter(et) && !ef.isAfter(nt)) {
      return const RuleResult(false, 'Overlapping or duplicate leave already exists for this nurse.');
    }
  }
  return RuleResult.ok;
}
