/// One point on the rating-over-time chart (`GET /stats/rating-history`).
class RatingPoint {
  final DateTime date;
  final int rating;

  const RatingPoint({required this.date, required this.rating});

  factory RatingPoint.fromJson(Map<String, dynamic> json) => RatingPoint(
        date: DateTime.parse(json['date'] as String),
        rating: json['rating'] as int,
      );
}
