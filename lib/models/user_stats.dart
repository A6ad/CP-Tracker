/// Aggregate Codeforces statistics returned by `GET /user/stats`.
class UserStats {
  final int currentRating;
  final int maxRating;
  final int problemsSolved;
  final int currentStreak;

  const UserStats({
    required this.currentRating,
    required this.maxRating,
    required this.problemsSolved,
    required this.currentStreak,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        currentRating: json['current_rating'] as int? ?? 0,
        maxRating: json['max_rating'] as int? ?? 0,
        problemsSolved: json['problems_solved'] as int? ?? 0,
        currentStreak: json['current_streak'] as int? ?? 0,
      );
}
