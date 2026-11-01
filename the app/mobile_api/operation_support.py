"""Model-aware execution support, separate from engine-wide readiness flags.

This describes installed execution paths, never measured output quality. No
identity vector is converted between recognition spaces to satisfy a capability.
"""

HUMAN_MODEL = 'buffalo_l@1'
CHARACTER_MODEL = 'ccip-caformer24@1'


def operation_support(snapshot):
    engines = snapshot.get('engines', {})
    entries = []

    def add(operation, kind, media_types, engine, available, models=(), reason=None):
        entries.append(dict(operation=operation, kind=kind, media_types=list(media_types),
                            available=bool(available), engine=engine,
                            identity_models=list(models),
                            experimental=engine == 'reference_guided_diffusion',
                            reason=None if available else (reason or 'Required local models are not installed.')))

    for kind, model in (('person', HUMAN_MODEL), ('character', CHARACTER_MODEL)):
        detection = engines.get('face_detection', False) if kind == 'person' else engines.get('character_identity', False)
        add('analyze', kind, ('photo', 'video'), 'insightface' if kind == 'person' else 'humanart_ccip',
            detection, (model,))
        add('action_match', kind, ('photo', 'video'), 'pose_geometry_temporal_v1', True)
        add('grouping', kind, ('photo', 'video'), 'identity_grouping', True, (model,))
        add('pose', kind, ('photo', 'video'), 'humanart_rtmpose', engines.get('body_detection', False))
        add('equipment', kind, ('photo',), 'florence_objects', engines.get('equipment', False))
        add('marks', kind, ('photo',), 'local_patch_matching', True)
        add('dataset_build', kind, ('photo', 'video'), 'face_dataset' if kind == 'person' else 'ccip_dataset',
            engines.get('dataset_person' if kind == 'person' else 'dataset_character', False), (model,))
        add('lora_train', kind, ('dataset',), 'sd_scripts', engines.get('lora_train', False), (model,))
        add('lora_generate', kind, ('model',), 'diffusion_lora', engines.get('lora_generate', False), (model,))
        add('reface_reference', kind, ('photo', 'video'), 'reference_guided_diffusion',
            engines.get('reface_reference', False))
        if kind == 'person':
            add('reface', kind, ('photo', 'video'), 'arcface_swap', engines.get('reface', False), (model,))
        else:
            add('reface', kind, ('photo', 'video'), 'reference_guided_diffusion',
                engines.get('reface_reference', False), reason='Anime identities require the reference-image execution path.')
    return entries
