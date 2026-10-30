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

class Capabilities {
  const Capabilities({
    this.refaceProfiles = const {},
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
