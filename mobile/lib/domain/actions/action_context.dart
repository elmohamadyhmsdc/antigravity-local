import 'entity_ref.dart';

class ActionContext {
  const ActionContext({
    this.isCharacter = false,
    this.isVideo = false,
    this.hasPerson = false,
    this.belongsToNoOne = false,
    this.isPcConnected = false,
    this.isMultiSelect = false,
    this.selectedEntities = const [],
    this.extra = const {},
  });

  final bool isCharacter;
  final bool isVideo;
  final bool hasPerson;
  final bool belongsToNoOne;
  final bool isPcConnected;
  final bool isMultiSelect;
  final List<EntityRef> selectedEntities;
  final Map<String, dynamic> extra;

  static const defaultContext = ActionContext();

  ActionContext copyWith({
    bool? isCharacter,
    bool? isVideo,
    bool? hasPerson,
    bool? belongsToNoOne,
    bool? isPcConnected,
    bool? isMultiSelect,
    List<EntityRef>? selectedEntities,
    Map<String, dynamic>? extra,
  }) => ActionContext(
    isCharacter: isCharacter ?? this.isCharacter,
    isVideo: isVideo ?? this.isVideo,
    hasPerson: hasPerson ?? this.hasPerson,
    belongsToNoOne: belongsToNoOne ?? this.belongsToNoOne,
    isPcConnected: isPcConnected ?? this.isPcConnected,
    isMultiSelect: isMultiSelect ?? this.isMultiSelect,
    selectedEntities: selectedEntities ?? this.selectedEntities,
    extra: extra ?? this.extra,
  );
}
