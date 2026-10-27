class AppUser {
  final String id;
  final String email;
  final bool emailVerified;
  final String? codeforcesHandle;
  final int? currentRating;
  final int? maxRating;

  const AppUser({
    required this.id,
    required this.email,
    this.emailVerified = true,
    this.codeforcesHandle,
    this.currentRating,
    this.maxRating,
  });

  bool get hasLinkedCodeforces => codeforcesHandle != null;

  /// Matches the JSON shape returned by `/user/me`, so the same payload can be
  /// saved to the offline cache.
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'email_verified': emailVerified,
        'codeforces_handle': codeforcesHandle,
        'current_rating': currentRating,
        'max_rating': maxRating,
      };

  AppUser copyWith({
    bool? emailVerified,
    String? codeforcesHandle,
    int? currentRating,
    int? maxRating,
  }) {
    return AppUser(
      id: id,
      email: email,
      emailVerified: emailVerified ?? this.emailVerified,
      codeforcesHandle: codeforcesHandle ?? this.codeforcesHandle,
      currentRating: currentRating ?? this.currentRating,
      maxRating: maxRating ?? this.maxRating,
    );
  }
}
