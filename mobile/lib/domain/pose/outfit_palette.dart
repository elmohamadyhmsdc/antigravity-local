/// Roadmap section 5.1 - what the existing 80-float outfit descriptor can honestly say about colour.
///
/// Layout (person_linking._region_hist, per region, 40 floats = sqrt of a normalised histogram):
/// 12 hue bins (OpenCV hue 0..180, 15 units = 30 degrees each) x 3 saturation bins for chromatic pixels
/// (S >= 50, V >= 40), then 4 value bins for the rest. Region 0 = torso, region 1 = legs.
/// Brightness of chromatic pixels is NOT recorded: navy vs sky blue, burgundy vs red, brown vs orange
/// cannot be told apart, so labels are coarse hue families plus white / grey / black.
library;

const _regionLength = 40;
const _hueBins = 12;
const _satBins = 3;

enum OutfitColor {
  white,
  lightGrey,
  darkGrey,
  black,
  red,
  orange,
  yellow,
  green,
  cyan,
  blue,
  purple,
  pink,
}

enum OutfitRegion { torso, legs }

/// Hue bin (30 degrees each, starting at red) -> family.
const _hueFamily = <int, OutfitColor>{
  11: OutfitColor.red,
  0: OutfitColor.red,
  1: OutfitColor.orange,
  2: OutfitColor.yellow,
  3: OutfitColor.green,
  4: OutfitColor.green,
  5: OutfitColor.cyan,
  6: OutfitColor.cyan,
  7: OutfitColor.blue,
  8: OutfitColor.blue,
  9: OutfitColor.purple,
  10: OutfitColor.pink,
};

const _valueBin = <OutfitColor>[
  OutfitColor.black,
  OutfitColor.darkGrey,
  OutfitColor.lightGrey,
  OutfitColor.white,
];

/// Share of a region's pixels per colour (they sum to 1), or null when that region is not visible.
Map<OutfitColor, double>? colorShares(
  List<double> descriptor,
  OutfitRegion region,
) {
  final start = region.index * _regionLength;
  if (descriptor.length < start + _regionLength) return null;
  final probs = [
    for (var i = 0; i < _regionLength; i++)
      descriptor[start + i] * descriptor[start + i],
  ];
  final total = probs.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return null;
  final shares = <OutfitColor, double>{};
  for (var h = 0; h < _hueBins; h++) {
    for (var s = 0; s < _satBins; s++) {
      final family = _hueFamily[h]!;
      shares[family] = (shares[family] ?? 0) + probs[h * _satBins + s] / total;
    }
  }
  for (var v = 0; v < _valueBin.length; v++) {
    shares[_valueBin[v]] =
        (shares[_valueBin[v]] ?? 0) + probs[_hueBins * _satBins + v] / total;
  }
  return shares;
}

/// The colour that holds at least [minShare] of the region, else null ("mixed").
OutfitColor? dominantColor(
  List<double> descriptor,
  OutfitRegion region, {
  double minShare = 0.35,
}) {
  final shares = colorShares(descriptor, region);
  if (shares == null) return null;
  final best = shares.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return best.value >= minShare ? best.key : null;
}

bool _neutral(OutfitColor c) =>
    c == OutfitColor.white ||
    c == OutfitColor.lightGrey ||
    c == OutfitColor.darkGrey ||
    c == OutfitColor.black;

/// Colourful: more than half of the torso or legs is a hue family (not white / grey / black).
bool isColourful(List<double> descriptor) {
  for (final region in OutfitRegion.values) {
    final shares = colorShares(descriptor, region);
    if (shares == null) continue;
    final chromatic = shares.entries
        .where((e) => !_neutral(e.key))
        .fold<double>(0, (a, e) => a + e.value);
    if (chromatic > 0.5) return true;
  }
  return false;
}

/// Torso and legs share the dominant colour.
bool isMonochrome(List<double> descriptor) {
  final top = dominantColor(descriptor, OutfitRegion.torso);
  final bottom = dominantColor(descriptor, OutfitRegion.legs);
  return top != null && top == bottom;
}

/// Torso and legs have different dominant colours.
bool isContrasting(List<double> descriptor) {
  final top = dominantColor(descriptor, OutfitRegion.torso);
  final bottom = dominantColor(descriptor, OutfitRegion.legs);
  return top != null && bottom != null && top != bottom;
}

/// Does [color] dominate the torso (or the legs, when [region] says so)? Region null = either.
bool hasColor(
  List<double> descriptor,
  OutfitColor color, {
  OutfitRegion? region,
  double minShare = 0.35,
}) {
  for (final r in region == null ? OutfitRegion.values : [region]) {
    if (dominantColor(descriptor, r, minShare: minShare) == color) return true;
  }
  return false;
}
