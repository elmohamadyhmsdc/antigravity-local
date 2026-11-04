/// Colour histograms describe clothing, not identity. Keep them in discovery,
/// never in automatic person assignment or identity review questions.
bool isClothingOnlyLink(String method) =>
    method == 'appearance' || method == 'event_outfit';
