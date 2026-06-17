// 7-card Texas Hold'em hand evaluator.
// Returns an int where higher = better hand. Compares directly with >.

// Hand categories (stored in bits 20-23 of result)
const int _kHighCard = 0;
const int _kOnePair = 1;
const int _kTwoPair = 2;
const int _kThreeOfAKind = 3;
const int _kStraight = 4;
const int _kFlush = 5;
const int _kFullHouse = 6;
const int _kFourOfAKind = 7;
const int _kStraightFlush = 8;

/// Bit offset where [evaluate7]/[evaluateBest] store the hand category.
const int kCategoryShift = 20;

/// Category names indexed by category value (0 = high card … 8 = straight
/// flush). The single source of truth for the encoding, so external consumers
/// (e.g. the eval harness's fixture baker) decode categories the same way the
/// evaluator encodes them instead of hard-coding `>> 20` + their own list.
const List<String> kHandCategoryNames = [
  'HIGH_CARD',
  'ONE_PAIR',
  'TWO_PAIR',
  'THREE_OF_A_KIND',
  'STRAIGHT',
  'FLUSH',
  'FULL_HOUSE',
  'FOUR_OF_A_KIND',
  'STRAIGHT_FLUSH',
];

/// The category component of an evaluator result (0–8).
int handCategory(int value) => value >> kCategoryShift;

/// Name of the category component of an evaluator result.
String handCategoryName(int value) {
  final c = handCategory(value);
  return c >= 0 && c < kHandCategoryNames.length
      ? kHandCategoryNames[c]
      : 'UNKNOWN';
}

/// Best 5-card value from 5, 6, or 7 cards. Same encoding as [evaluate7]
/// (higher = better, compare with >). Used to score a 2-card combo against a
/// partial board (flop = 5 cards, turn = 6, river = 7).
int evaluateBest(List<int> cards) {
  assert(cards.length >= 5 && cards.length <= 7);
  if (cards.length == 5) return _evaluate5(cards);
  if (cards.length == 7) return evaluate7(cards);
  // 6 cards: C(6,5) = 6 ways to drop one
  int best = 0;
  for (int drop = 0; drop < 6; drop++) {
    final five = <int>[];
    for (int k = 0; k < 6; k++) {
      if (k != drop) five.add(cards[k]);
    }
    final v = _evaluate5(five);
    if (v > best) best = v;
  }
  return best;
}

int evaluate7(List<int> cards) {
  assert(cards.length == 7);
  int best = 0;
  // Try all C(7,2)=21 ways to remove 2 cards → evaluate remaining 5
  for (int i = 0; i < 7; i++) {
    for (int j = i + 1; j < 7; j++) {
      final five = <int>[];
      for (int k = 0; k < 7; k++) {
        if (k != i && k != j) five.add(cards[k]);
      }
      final v = _evaluate5(five);
      if (v > best) best = v;
    }
  }
  return best;
}

int _evaluate5(List<int> cards) {
  assert(cards.length == 5);

  // Extract ranks (0=2 ... 12=A) and suits (0-3)
  final rs = [for (final c in cards) c >> 2]..sort((a, b) => b.compareTo(a));
  final ss = [for (final c in cards) c & 3];

  final isFlush = ss[0] == ss[1] && ss[1] == ss[2] && ss[2] == ss[3] && ss[3] == ss[4];

  // Count rank frequencies
  final cnt = <int, int>{};
  for (final r in rs) { cnt[r] = (cnt[r] ?? 0) + 1; }

  // Check straight (normal and wheel A-2-3-4-5)
  bool isStraight = false;
  int strHigh = rs[0];
  if (cnt.length == 5) {
    if (rs[0] - rs[4] == 4) {
      isStraight = true;
    } else if (rs[0] == 12 && rs[1] == 3 && rs[2] == 2 && rs[3] == 1 && rs[4] == 0) {
      // Wheel: A-2-3-4-5, ace plays as low
      isStraight = true;
      strHigh = 3; // 5-high
    }
  }

  // Sort by frequency desc, then rank desc for tiebreaking
  final groups = cnt.entries.toList()
    ..sort((a, b) {
      if (a.value != b.value) return b.value.compareTo(a.value);
      return b.key.compareTo(a.key);
    });

  int cat;
  final List<int> tb = [];

  if (isStraight && isFlush) {
    cat = _kStraightFlush;
    tb.add(strHigh);
  } else if (groups[0].value == 4) {
    cat = _kFourOfAKind;
    tb.add(groups[0].key);
    tb.add(groups[1].key);
  } else if (groups[0].value == 3 && groups[1].value == 2) {
    cat = _kFullHouse;
    tb.add(groups[0].key);
    tb.add(groups[1].key);
  } else if (isFlush) {
    cat = _kFlush;
    tb.addAll(rs);
  } else if (isStraight) {
    cat = _kStraight;
    tb.add(strHigh);
  } else if (groups[0].value == 3) {
    cat = _kThreeOfAKind;
    tb.add(groups[0].key);
    tb.add(groups[1].key);
    tb.add(groups[2].key);
  } else if (groups[0].value == 2 && groups[1].value == 2) {
    cat = _kTwoPair;
    tb.add(groups[0].key);
    tb.add(groups[1].key);
    tb.add(groups[2].key);
  } else if (groups[0].value == 2) {
    cat = _kOnePair;
    tb.add(groups[0].key);
    tb.add(groups[1].key);
    tb.add(groups[2].key);
    tb.add(groups[3].key);
  } else {
    cat = _kHighCard;
    tb.addAll(rs);
  }

  // Encode: bits 20-23 = category, bits 16-19 = tb[0], ..., bits 0-3 = tb[4]
  int value = cat << 20;
  for (int i = 0; i < tb.length && i < 5; i++) {
    value |= tb[i] << (16 - i * 4);
  }
  return value;
}
