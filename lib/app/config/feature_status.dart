enum FeatureStatus {
  available('Available'),
  manualVerification('Manual Payment Verification'),
  notYetConnected('Not Yet Connected'),
  comingSoon('Coming Soon'),
  placeholder('Placeholder');

  const FeatureStatus(this.label);
  final String label;
}
