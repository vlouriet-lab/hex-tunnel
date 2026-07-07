class RelayReputation {
  static const int defaultScore = 50;
  static const int minScore = 0;
  static const int maxScore = 100;

  static const int successBonus = 3;
  static const int failurePenalty = 8;
  static const int decayStepSecs = 6 * 60 * 60;

  static int clampScore(int score) {
    if (score < minScore) return minScore;
    if (score > maxScore) return maxScore;
    return score;
  }

  static int applyDecay(int score, int elapsedSecs) {
    if (elapsedSecs <= 0) {
      return clampScore(score);
    }
    final steps = elapsedSecs ~/ decayStepSecs;
    if (steps <= 0) {
      return clampScore(score);
    }
    if (score > defaultScore) {
      final next = score - steps;
      return clampScore(next < defaultScore ? defaultScore : next);
    }
    if (score < defaultScore) {
      final next = score + steps;
      return clampScore(next > defaultScore ? defaultScore : next);
    }
    return defaultScore;
  }

  static int scoreAfterEvent(int currentScore, {required bool success}) {
    if (success) {
      return clampScore(currentScore + successBonus);
    }
    return clampScore(currentScore - failurePenalty);
  }

  static bool isPreferred(int score) => score >= 60;

  static bool shouldAvoid(int score) => score < 30;
}
