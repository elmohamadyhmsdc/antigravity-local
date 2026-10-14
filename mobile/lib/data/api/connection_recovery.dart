import '../platform/lan_network.dart';
import 'api_exception.dart';
import 'dtos/system.dart';
import 'lan_host.dart';
import 'mobile_api.dart';

typedef ApiFactory = MobileApi Function(ServerSession session);

class VerifiedEndpoint {
  const VerifiedEndpoint(this.session, this.capabilities);
  final ServerSession session;
  final Capabilities capabilities;
}

Future<VerifiedEndpoint> verifyEndpoint(
  ServerSession saved,
  LanEndpoint endpoint, {
  ApiFactory? factory,
}) async {
  if (!isLanHost(endpoint.host) || endpoint.port < 1 || endpoint.port > 65535) {
    throw ApiException.badResponse(
      'Choose a local PC address and a valid port.',
    );
  }
  final moved = saved.copyWith(host: endpoint.host, port: endpoint.port);
  final api = factory == null
      ? HttpMobileApi(moved, connectTimeout: const Duration(seconds: 3))
      : factory(moved);
  try {
    // Health deliberately carries no token. UDP metadata is never trusted as identity.
    final health = await api.health();
    if (health.serverId != saved.serverId) {
      throw ApiException.badResponse('This address belongs to a different PC.');
    }
    final caps = await api.capabilities();
    if (caps.serverId != saved.serverId) {
      throw ApiException.badResponse(
        'The PC identity changed during connection.',
      );
    }
    return VerifiedEndpoint(moved, caps);
  } finally {
    if (api is HttpMobileApi) api.close();
  }
}

Future<VerifiedEndpoint?> recoverEndpoint(
  ServerSession saved,
  LanNetwork network, {
  ApiFactory? factory,
}) async {
  final candidates = await network.discover(serverId: saved.serverId);
  final results = await Future.wait(
    candidates.take(8).map((endpoint) async {
      try {
        return await verifyEndpoint(saved, endpoint, factory: factory);
      } on ApiException catch (error) {
        return error;
      }
    }),
  );
  for (final result in results) {
    if (result is VerifiedEndpoint) return result;
  }
  for (final result in results) {
    if (result is ApiException && result.isUnauthorized) throw result;
  }
  return null;
}
