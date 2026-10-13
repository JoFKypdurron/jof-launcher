/// Which EternalJK client build a user wants installed.
///
/// `beta` and `alpha` are unreleased test builds published as GitHub
/// prereleases on `JediofFreedom/JoF_EJK`, resolved by tag rather than by the
/// jofhub manifest (see [ClientChannelCodec] and `ClientReleaseService`).
enum ClientChannel { stable, beta, alpha }

extension ClientChannelCodec on ClientChannel {
  String get persistedValue {
    return switch (this) {
      ClientChannel.stable => 'stable',
      ClientChannel.beta => 'beta',
      ClientChannel.alpha => 'alpha',
    };
  }

  /// The channel segment as it appears in a prerelease tag, e.g. the `alpha`
  /// in `1.6.1-alpha.59`. Unused for [ClientChannel.stable], which has no
  /// such tag shape — stable releases are looked up by their bare version.
  String? get prereleaseTagSegment {
    return switch (this) {
      ClientChannel.stable => null,
      ClientChannel.beta => 'beta',
      ClientChannel.alpha => 'alpha',
    };
  }

  static ClientChannel? tryParse(String? value) {
    return switch (value) {
      'stable' => ClientChannel.stable,
      'beta' => ClientChannel.beta,
      'alpha' => ClientChannel.alpha,
      _ => null,
    };
  }
}
