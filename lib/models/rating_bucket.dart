/// Solved-count for one rating bucket (`GET /stats/by-rating`).
///
/// [bucket] is the Codeforces-style label, e.g. "800-1000" or "2000+".
class RatingBucket {
  final String bucket;
  final int solved;

  const RatingBucket({required this.bucket, required this.solved});

  factory RatingBucket.fromJson(Map<String, dynamic> json) => RatingBucket(
        bucket: json['bucket'] as String,
        solved: json['solved'] as int,
      );
}
