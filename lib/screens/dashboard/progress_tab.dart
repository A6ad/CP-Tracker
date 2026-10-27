import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../models/rating_bucket.dart';
import '../../models/rating_point.dart';
import '../../models/topic_stat.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exception.dart';
import '../../theme/app_theme.dart';

class ProgressTab extends ConsumerWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar(floating: true, title: Text('Progress')),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const _SectionTitle('Rating History'),
              const SizedBox(height: 12),
              _AsyncCard(
                value: ref.watch(ratingHistoryProvider),
                emptyMessage: 'No rating history yet.',
                builder: (points) => SizedBox(
                  height: 220,
                  child: _RatingLineChart(points: points),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Solved by Difficulty'),
              const SizedBox(height: 12),
              _AsyncCard(
                value: ref.watch(solvedByRatingProvider),
                emptyMessage: 'No solved problems yet.',
                builder: (buckets) => SizedBox(
                  height: 220,
                  child: _SolvedBarChart(buckets: buckets),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Topic-wise Analysis'),
              const SizedBox(height: 12),
              _AsyncCard(
                value: ref.watch(topicsProvider),
                emptyMessage: 'No topic data yet.',
                builder: (topics) => _TopicList(topics: topics),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      );
}

/// Renders [value]'s loading / error / empty / data states consistently.
class _AsyncCard<T> extends StatelessWidget {
  final AsyncValue<List<T>> value;
  final String emptyMessage;
  final Widget Function(List<T> data) builder;

  const _AsyncCard({
    required this.value,
    required this.emptyMessage,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: value.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorMessage(err),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          data: (data) => data.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    emptyMessage,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : builder(data),
        ),
      ),
    );
  }
}

class _RatingLineChart extends StatelessWidget {
  final List<RatingPoint> points;
  const _RatingLineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].rating.toDouble()),
    ];

    final ratings = points.map((p) => p.rating);
    final minY = (ratings.reduce((a, b) => a < b ? a : b) - 100).floorToDouble();
    final maxY = (ratings.reduce((a, b) => a > b ? a : b) + 100).ceilToDouble();

    final labelCount = points.length;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((spot) {
              final point = points[spot.x.toInt()];
              return LineTooltipItem(
                '${point.rating}',
                const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (labelCount / 3).clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM').format(points[i].date),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolvedBarChart extends StatelessWidget {
  final List<RatingBucket> buckets;
  const _SolvedBarChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final maxSolved =
        buckets.map((b) => b.solved).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: (maxSolved + (maxSolved * 0.2)).ceilToDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= buckets.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    buckets[i].bucket,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].solved.toDouble(),
                  color: AppColors.ratingColor(_bucketFloor(buckets[i].bucket)),
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Extracts the leading number from a bucket label like "1200-1400" or
  /// "2000+" so the bar takes the matching Codeforces tier color.
  static int _bucketFloor(String bucket) {
    final match = RegExp(r'\d+').firstMatch(bucket);
    return match == null ? 0 : int.parse(match.group(0)!);
  }
}

class _TopicList extends StatelessWidget {
  final List<TopicStat> topics;
  const _TopicList({required this.topics});

  @override
  Widget build(BuildContext context) {
    final sorted = [...topics]..sort((a, b) => b.solved.compareTo(a.solved));
    final maxSolved = sorted.first.solved;

    return Column(
      children: [
        for (final t in sorted) ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(t.topic, style: const TextStyle(fontSize: 13)),
              ),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: t.solved / maxSolved,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${t.solved}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
