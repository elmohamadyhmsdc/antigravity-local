enum CorrectionScope {
  single,
  track,
  cluster,
  wholeVideo;

  String get labelEn => switch (this) {
    single => 'This element only',
    track => 'This appearance / track',
    cluster => 'All members of cluster',
    wholeVideo => 'Whole video',
  };
}
