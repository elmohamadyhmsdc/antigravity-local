/// Stateless comparison. No user labels or person identities leave the phone.
abstract interface class ActionMatchApi {
  Future<Map<String, double?>> compareActions({
    required String kind,
    required List<Map<String, dynamic>> query,
    required List<({String id, List<Map<String, dynamic>> frames})> candidates,
    bool allowMirror = false,
  });
}
