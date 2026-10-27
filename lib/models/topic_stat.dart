/// Solved-count for one topic/tag (`GET /stats/topics`).
class TopicStat {
  final String topic;
  final int solved;

  const TopicStat({required this.topic, required this.solved});

  factory TopicStat.fromJson(Map<String, dynamic> json) => TopicStat(
        topic: json['topic'] as String,
        solved: json['solved'] as int,
      );
}
