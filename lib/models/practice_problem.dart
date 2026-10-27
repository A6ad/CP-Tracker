/// A single unsolved problem recommended for practice.
class PracticeProblem {
  final String problemId;
  final int? contestId;
  final String index;
  final String name;
  final int? rating;
  final List<String> tags;
  final String url;

  const PracticeProblem({
    required this.problemId,
    required this.contestId,
    required this.index,
    required this.name,
    required this.rating,
    required this.tags,
    required this.url,
  });

  factory PracticeProblem.fromJson(Map<String, dynamic> json) {
    return PracticeProblem(
      problemId: json['problem_id'] as String,
      contestId: json['contest_id'] as int?,
      index: json['index'] as String,
      name: json['name'] as String,
      rating: json['rating'] as int?,
      tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
      url: json['url'] as String,
    );
  }
}

/// Response from `GET /practice/problems`.
class PracticeResult {
  final String mode;
  final int? rating;
  final List<PracticeProblem> problems;

  const PracticeResult({
    required this.mode,
    required this.rating,
    required this.problems,
  });

  factory PracticeResult.fromJson(Map<String, dynamic> json) {
    return PracticeResult(
      mode: json['mode'] as String? ?? 'recommended',
      rating: json['rating'] as int?,
      problems: (json['problems'] as List<dynamic>)
          .map((e) => PracticeProblem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
