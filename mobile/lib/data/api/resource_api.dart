import 'dtos/resources.dart';

/// Optional extension, so older clients/fakes keep the original compute API.
abstract interface class ResourceApi {
  Future<ResourceSnapshot> resources();
}
