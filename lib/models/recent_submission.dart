/// A single Codeforces submission shown in the dashboard "Recent Activity" list.
class RecentSubmission {
  final String problemName;
  final String problemId;
  final bool solved;
  final DateTime submittedAt;

  const RecentSubmission({
    required this.problemName,
    required this.problemId,
    required this.solved,
    required this.submittedAt,
  });

  factory RecentSubmission.fromJson(Map<String, dynamic> json) =>
      RecentSubmission(
        problemName: json['problem_name'] as String,
        problemId: json['problem_id'] as String,
        solved: json['solved'] as bool? ?? true,
        submittedAt: DateTime.parse(json['submitted_at'] as String),
      );

  /// Human-readable relative age, e.g. "2 hours ago".
  String relativeTime({DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(submittedAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays} days ago';
  }
}
