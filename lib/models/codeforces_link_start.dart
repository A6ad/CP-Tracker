/// Response from `POST /user/link-codeforces/start`.
///
/// The user proves they own the handle by placing [verificationCode] in their
/// public Codeforces profile, then calling the verify endpoint.
class CodeforcesLinkStart {
  final String handle;
  final String verificationCode;
  final String instructions;

  const CodeforcesLinkStart({
    required this.handle,
    required this.verificationCode,
    required this.instructions,
  });

  factory CodeforcesLinkStart.fromJson(Map<String, dynamic> json) {
    return CodeforcesLinkStart(
      handle: json['handle'] as String,
      verificationCode: json['verification_code'] as String,
      instructions: json['instructions'] as String? ?? '',
    );
  }
}
