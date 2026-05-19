const pyritaDistribution = String.fromEnvironment(
  'PYRITA_DISTRIBUTION',
  defaultValue: 'direct',
);

const isGooglePlayBuild = pyritaDistribution == 'google_play';
