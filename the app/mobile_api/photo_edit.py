"""Photo editor validation/adapter over the shared, device-owned Studio queue."""
from .errors import ApiError, bad_request

TYPE = 'edit_image'


def validate_photo_edit(body, capabilities):
    inputs = body.get('inputs')
    if body.get('type') != TYPE or not isinstance(inputs, dict) or not isinstance(inputs.get('image'), str):
        raise bad_request('Photo editing requires one image blob.')
    from photo_edit import DEFAULT_MODEL, MAX_REFERENCES, MODEL_SDXL_GGUF, validate_options
    try:
        options = validate_options(body.get('params'), guided='refs' in inputs)
    except ValueError as exc:
        raise bad_request(str(exc)) from exc
    expected = {'image'} if options['auto_body'] else {'image', 'mask'}
    if set(inputs) - {'refs'} != expected or ('mask' in expected and not isinstance(inputs['mask'], str)):
        raise bad_request('Automatic editing takes only an image; brush editing also needs one selection mask.')
    engines = capabilities.get('engines', {})
    if not engines.get('photo_edit', False):
        raise ApiError(409,'engine_unavailable','Photo editing requires the current PC server and its local models.')
    if options['auto_body'] and not engines.get('photo_edit_auto_body', False):
        raise ApiError(409, 'engine_unavailable', 'Automatic clothing selection requires the local clothing parser.')
    if options['preserve_body_shape'] and not engines.get('photo_edit_body_shape', False):
        raise ApiError(409, 'engine_unavailable', 'Keep body shape requires the local body outline model.')
    if 'refs' in inputs:
        refs = inputs['refs']
        if not isinstance(refs, list) or not 1 <= len(refs) <= MAX_REFERENCES or not all(isinstance(ref, str) for ref in refs):
            raise bad_request('Choose one to three reference photos.')
        if options['operation'] != 'replace' or options['model'] != DEFAULT_MODEL:
            raise bad_request('Reference photos require the guided Replace mode.')
        if not capabilities.get('engines', {}).get('photo_edit_reference', False):
            raise ApiError(409, 'engine_unavailable', 'Reference guidance requires the local image adapter on the PC.')
    if options['model'] == MODEL_SDXL_GGUF and MODEL_SDXL_GGUF not in capabilities.get('photo_edit_models', ()):
        raise ApiError(409, 'engine_unavailable', 'Start the Gallary ComfyUI photo editor on the PC, then retry.', retryable=True)


def run_photo_edit(job, directory, report, stopped):
    from photo_edit import edit_photo
    return edit_photo(job,directory,report,stopped)
