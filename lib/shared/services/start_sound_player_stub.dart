class StartSoundPlayer {
  StartSoundPlayer(this.assetPath);

  final String assetPath;

  Future<void> play() async {}

  Future<void> fadeOut({
    Duration duration = const Duration(milliseconds: 800),
  }) async {}

  void dispose() {}
}
