/// A Codeforces contest with its current phase.
class CfContest {
  final int id;
  final String name;
  final String phase;
  final DateTime startTime;
  final int durationSeconds;
  final String url;

  const CfContest({
    required this.id,
    required this.name,
    required this.phase,
    required this.startTime,
    required this.durationSeconds,
    required this.url,
  });

  bool get isRunning => phase == 'CODING';

  factory CfContest.fromJson(Map<String, dynamic> json) {
    return CfContest(
      id: json['id'] as int,
      name: json['name'] as String,
      phase: json['phase'] as String,
      startTime: DateTime.parse(json['start_time'] as String).toLocal(),
      durationSeconds: json['duration_seconds'] as int,
      url: json['url'] as String,
    );
  }
}

/// Response from `GET /contests`.
class ContestsResult {
  final List<CfContest> upcoming;
  final List<CfContest> finished;

  const ContestsResult({required this.upcoming, required this.finished});

  factory ContestsResult.fromJson(Map<String, dynamic> json) {
    List<CfContest> parse(String key) =>
        (json[key] as List<dynamic>)
            .map((e) => CfContest.fromJson(e as Map<String, dynamic>))
            .toList();

    return ContestsResult(
      upcoming: parse('upcoming'),
      finished: parse('finished'),
    );
  }
}
