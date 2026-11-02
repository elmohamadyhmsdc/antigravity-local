import 'json_util.dart';

class Health {
  const Health({
    required this.serverId,
    required this.name,
    required this.apiVersion,
  });

  final String serverId;
  final String name;
  final String apiVersion;

  factory Health.fromJson(Map<String, dynamic> json) {
    if (json['status'] != 'ok') {
      throw const FormatException('health.status: expected "ok"');
    }
    return Health(
      serverId: field<String>(json, 'server_id'),
      name: field<String>(json, 'name'),
      apiVersion: field<String>(json, 'api_version'),
    );
  }
}

class GpuInfo {
  const GpuInfo({
    required this.name,
    required this.vramTotalMb,
    required this.vramFreeMb,
  });

  final String name;
  final int vramTotalMb;
  final int vramFreeMb;

  factory GpuInfo.fromJson(Map<String, dynamic> json) => GpuInfo(
    name: field<String>(json, 'name', 'gpu'),
    vramTotalMb: integer(json, 'vram_total_mb', 'gpu'),
    vramFreeMb: integer(json, 'vram_free_mb', 'gpu'),
  );
}

class Engines {
  const Engines({
    this.reface = false,
    required this.refaceV3,
    required this.refaceV2,
    required this.dfmModels,
    required this.undress,
    this.restyleRefine = true,
    required this.loraTrain,
    required this.loraGenerate,
    required this.bodyDetection,
    this.characterDetection = false,
    this.sensitiveDetection = false,
    this.bodyEmbeddings = false,
    this.garmentTags = false,
    this.equipment = false,
  });

  final bool reface;
  final bool refaceV3;
  final bool refaceV2;
  final List<String> dfmModels;
  final bool undress;
  final bool restyleRefine;
  final bool loraTrain;
  final bool loraGenerate;
  final bool bodyDetection;
  final bool characterDetection;

  /// Roadmap section 8: the PC can return exposed / covered body-part regions.
  final bool sensitiveDetection;

  /// Roadmap Phase 7: the WD14 tagger is installed, so garment tags can be asked for.
  final bool garmentTags;
  final bool equipment;

  /// Roadmap 7.5: the DINOv2 model is installed, so exposed-region embeddings can be asked for.
  final bool bodyEmbeddings;

  factory Engines.fromJson(Map<String, dynamic> json) => Engines(
    reface: json['reface'] as bool? ?? false,
    refaceV3: field<bool>(json, 'reface_v3', 'engines'),
    refaceV2: field<bool>(json, 'reface_v2', 'engines'),
    dfmModels: list(json['dfm_models'], 'engines.dfm_models').cast<String>(),
    undress: field<bool>(json, 'undress', 'engines'),
    restyleRefine:
        json['restyle_refine'] as bool? ??
        field<bool>(json, 'undress', 'engines'),
    loraTrain: field<bool>(json, 'lora_train', 'engines'),
    loraGenerate: field<bool>(json, 'lora_generate', 'engines'),
    bodyDetection: field<bool>(json, 'body_detection', 'engines'),
    characterDetection: json['character_detection'] as bool? ?? false,
    sensitiveDetection: json['sensitive_detection'] as bool? ?? false,
    garmentTags: json['garment_tags'] as bool? ?? false,
    equipment: json['equipment'] as bool? ?? false,
    bodyEmbeddings: json['body_embeddings'] as bool? ?? false,
  );
}

class ServerLimits {
  const ServerLimits({
    required this.maxImagePx,
    required this.maxUploadMb,
    required this.blobCacheMb,
  });

  final int maxImagePx;
  final int maxUploadMb;
  final int blobCacheMb;

  factory ServerLimits.fromJson(Map<String, dynamic> json) => ServerLimits(
    maxImagePx: integer(json, 'max_image_px', 'limits'),
    maxUploadMb: integer(json, 'max_upload_mb', 'limits'),
    blobCacheMb: integer(json, 'blob_cache_mb', 'limits'),
  );
}

/// The job currently holding the GPU. `source` is `mobile` or `dashboard`.
class BusyInfo {
  const BusyInfo({
    required this.jobId,
    required this.jobType,
    required this.source,
  });

  final String jobId;
  final String jobType;
  final String source;

  factory BusyInfo.fromJson(Map<String, dynamic> json) => BusyInfo(
    jobId: field<String>(json, 'job_id', 'busy'),
    jobType: field<String>(json, 'job_type', 'busy'),
    source: field<String>(json, 'source', 'busy'),
  );
}

/// One installed execution path. Availability does not imply output-quality validation.
class OperationSupport {
  const OperationSupport({
    required this.operation,
    required this.kind,
    required this.mediaTypes,
    required this.available,
    required this.engine,
    required this.identityModels,
    this.reason,
    this.experimental = false,
  });
  final String operation, kind, engine;
  final List<String> mediaTypes, identityModels;
  final bool available;
  final bool experimental;
  final String? reason;
  factory OperationSupport.fromJson(Map<String, dynamic> json) =>
      OperationSupport(
        operation: field<String>(json, 'operation', 'operation'),
        kind: field<String>(json, 'kind', 'operation'),
        mediaTypes: list(
          json['media_types'],
          'operation.media_types',
        ).cast<String>(),
        available: field<bool>(json, 'available', 'operation'),
        engine: field<String>(json, 'engine', 'operation'),
        identityModels: list(
          json['identity_models'],
          'operation.identity_models',
        ).cast<String>(),
        reason: json['reason'] as String?,
        experimental: json['experimental'] as bool? ?? false,
      );
}

class Capabilities {
  const Capabilities({
    this.refaceProfiles = const {},
    this.operations = const [],
    this.hasOperationSupport = false,
    required this.apiVersion,
    required this.serverId,
    required this.name,
    required this.embeddingModelId,
    required this.embeddingDim,
    required this.gpu,
    required this.engines,
    required this.restorers,
    required this.loraBaseCheckpoints,
    required this.limits,
    required this.busy,
  });

  final List<OperationSupport> operations;
  final bool hasOperationSupport;

  bool supportsOperation(
    String operation,
    String kind, {
    String? mediaType,
    String? identityModelId,
    bool allowExperimental = false,
  }) => operations.any(
    (entry) =>
        entry.operation == operation &&
        entry.kind == kind &&
        entry.available &&
        (allowExperimental || !entry.experimental) &&
        (mediaType == null || entry.mediaTypes.contains(mediaType)) &&
        (identityModelId == null ||
            entry.identityModels.isEmpty ||
            entry.identityModels.contains(identityModelId)),
  );

  final Map<String, String> refaceProfiles;
  final String apiVersion;
  final String serverId;
  final String name;
  final String embeddingModelId;
  final int embeddingDim;
  final GpuInfo? gpu;
  final Engines engines;
  final List<String> restorers;
  final List<String> loraBaseCheckpoints;
  final ServerLimits limits;
  final BusyInfo? busy;

  bool get isBusy => busy != null;

  factory Capabilities.fromJson(Map<String, dynamic> json) {
    final model = map(json['embedding_model'], 'embedding_model');
    return Capabilities(
      hasOperationSupport: json.containsKey('operations'),
      operations: [
        for (final item in list(json['operations'] ?? [], 'operations'))
          OperationSupport.fromJson(map(item, 'operation')),
      ],
      refaceProfiles: {
        for (final entry
            in (json['reface_profiles'] as Map<String, dynamic>? ?? {}).entries)
          entry.key: field<String>(
            map(entry.value, 'reface_profiles.${entry.key}'),
            'restorer',
          ),
      },
      apiVersion: field<String>(json, 'api_version'),
      serverId: field<String>(json, 'server_id'),
      name: field<String>(json, 'name'),
      embeddingModelId: field<String>(model, 'id', 'embedding_model'),
      embeddingDim: integer(model, 'dim', 'embedding_model'),
      gpu: json['gpu'] == null
          ? null
          : GpuInfo.fromJson(map(json['gpu'], 'gpu')),
      engines: Engines.fromJson(map(json['engines'], 'engines')),
      restorers: list(json['restorers'], 'restorers').cast<String>(),
      loraBaseCheckpoints: list(
        json['lora_base_checkpoints'],
        'lora_base_checkpoints',
      ).cast<String>(),
      limits: ServerLimits.fromJson(map(json['limits'], 'limits')),
      busy: json['busy'] == null
          ? null
          : BusyInfo.fromJson(map(json['busy'], 'busy')),
    );
  }
}

class PairRequest {
  const PairRequest({required this.code, required this.deviceName});

  final String code;
  final String deviceName;

  Map<String, dynamic> toJson() => {'code': code, 'device_name': deviceName};
}

class PairResponse {
  const PairResponse({
    required this.token,
    required this.serverId,
    required this.serverName,
  });

  final String token;
  final String serverId;
  final String serverName;

  factory PairResponse.fromJson(Map<String, dynamic> json) => PairResponse(
    token: field<String>(json, 'token'),
    serverId: field<String>(json, 'server_id'),
    serverName: field<String>(json, 'server_name'),
  );
}
