/// Personal goals and streak data for the Profile tab.
class UserGoals {
  final int? targetRating;
  final int currentRating;
  final int streakDays;

  const UserGoals({
    required this.targetRating,
    required this.currentRating,
    required this.streakDays,
  });

  factory UserGoals.fromJson(Map<String, dynamic> json) => UserGoals(
        targetRating: json['target_rating'] as int?,
        currentRating: json['current_rating'] as int? ?? 0,
        streakDays: json['streak_days'] as int? ?? 0,
      );

  bool get hasTarget => targetRating != null;

  /// Progress toward [targetRating] as 0.0–1.0, or null when no goal is set.
  double? get progress {
    final target = targetRating;
    if (target == null || target <= 0) return null;
    return (currentRating / target).clamp(0.0, 1.0);
  }
}
