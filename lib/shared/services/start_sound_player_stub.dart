class StartSoundPlayer {
  StartSoundPlayer(this.assetPath);

  final String assetPath;

  Future<bool> play() async => true;

  Future<void> fadeOut({
    Duration duration = const Duration(milliseconds: 800),
  }) async {}

  void dispose() {}
}
