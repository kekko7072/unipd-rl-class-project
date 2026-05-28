import 'dart:math';

class ContextualBanditArm<T> {
  const ContextualBanditArm({
    required this.item,
    required this.features,
  });

  final T item;
  final Map<String, double> features;
}

class ContextualBanditRanking<T> {
  const ContextualBanditRanking({
    required this.item,
    required this.features,
    required this.score,
    required this.expectedReward,
    required this.explorationBonus,
  });

  final T item;
  final Map<String, double> features;
  final double score;
  final double expectedReward;
  final double explorationBonus;
}

class LinearThompsonSampling<T> {
  LinearThompsonSampling({
    required Map<String, double> weights,
    required Map<String, double> standardDeviations,
    Random? random,
  })  : _weights = Map.unmodifiable(weights),
        _standardDeviations = Map.unmodifiable(standardDeviations),
        _random = random ?? Random();

  final Map<String, double> _weights;
  final Map<String, double> _standardDeviations;
  final Random _random;

  Map<String, double> get weights => _weights;
  Map<String, double> get standardDeviations => _standardDeviations;

  List<ContextualBanditRanking<T>> rank(List<ContextualBanditArm<T>> arms) {
    final rankings = arms.map((arm) {
      final expectedReward = _dot(arm.features, _weights);
      final sampledWeights = <String, double>{
        for (final entry in _weights.entries)
          entry.key: entry.value +
              (_sampleStandardNormal() *
                  (_standardDeviations[entry.key] ?? 0.0)),
      };
      final score = _dot(arm.features, sampledWeights);

      return ContextualBanditRanking<T>(
        item: arm.item,
        features: arm.features,
        score: score,
        expectedReward: expectedReward,
        explorationBonus: score - expectedReward,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return rankings;
  }

  double _dot(Map<String, double> features, Map<String, double> weights) {
    return features.entries.fold<double>(
      0.0,
      (total, entry) => total + (entry.value * (weights[entry.key] ?? 0.0)),
    );
  }

  double _sampleStandardNormal() {
    final u1 = max(_random.nextDouble(), 1e-12);
    final u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }
}
