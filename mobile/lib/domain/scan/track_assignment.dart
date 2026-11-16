/// Maximum-weight one-to-one assignment with an explicit unmatched choice.
/// Nonpositive/nonfinite edges are unavailable. Dummy columns cost zero.
({List<int?> columns, double score}) maximumTrackAssignment(
  List<List<double>> weights, {
  (int, int)? forbidden,
}) {
  final n = weights.length;
  if (n == 0) return (columns: const [], score: 0);
  final realColumns = weights.first.length;
  final m = realColumns + n;
  final u = List<double>.filled(n + 1, 0);
  final v = List<double>.filled(m + 1, 0);
  final p = List<int>.filled(m + 1, 0);
  final way = List<int>.filled(m + 1, 0);
  double weight(int row, int col) {
    if (col >= realColumns || forbidden == (row, col)) return 0;
    final value = weights[row][col];
    return value.isFinite && value > 0 ? value : 0;
  }

  // Rectangular Hungarian algorithm; n <= m because of the dummy columns.
  for (var i = 1; i <= n; i++) {
    p[0] = i;
    var j0 = 0;
    final minv = List<double>.filled(m + 1, double.infinity);
    final used = List<bool>.filled(m + 1, false);
    do {
      used[j0] = true;
      final i0 = p[j0];
      var delta = double.infinity;
      var j1 = 0;
      for (var j = 1; j <= m; j++) {
        if (used[j]) continue;
        final cur = -weight(i0 - 1, j - 1) - u[i0] - v[j];
        if (cur < minv[j]) {
          minv[j] = cur;
          way[j] = j0;
        }
        if (minv[j] < delta) {
          delta = minv[j];
          j1 = j;
        }
      }
      for (var j = 0; j <= m; j++) {
        if (used[j]) {
          u[p[j]] += delta;
          v[j] -= delta;
        } else {
          minv[j] -= delta;
        }
      }
      j0 = j1;
    } while (p[j0] != 0);
    do {
      final j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0 != 0);
  }
  final columns = List<int?>.filled(n, null);
  var score = 0.0;
  for (var j = 1; j <= realColumns; j++) {
    if (p[j] == 0) continue;
    final w = weight(p[j] - 1, j - 1);
    if (w <= 0) continue;
    columns[p[j] - 1] = j - 1;
    score += w;
  }
  return (columns: columns, score: score);
}
