"""Photo editor validation/adapter over the shared, device-owned Studio queue."""
from .errors import ApiError, bad_request

TYPE = 'edit_image'


def validate_photo_edit(body, capabilities):
    if body.get('type') != TYPE or not isinstance(body.get('inputs'),dict) or set(body['inputs']) != {'image','mask'}:
        raise bad_request('Photo editing requires one image and one selection mask.')
    if not all(isinstance(value,str) for value in body['inputs'].values()):
        raise bad_request('Image and mask must each reference one blob.')
    from photo_edit import validate_options
    try:
        validate_options(body.get('params'))
    except ValueError as exc:
        raise bad_request(str(exc)) from exc
    if not capabilities.get('engines',{}).get('photo_edit',False):
        raise ApiError(409,'engine_unavailable','Photo editing requires the current PC server and its local models.')


def run_photo_edit(job, directory, report, stopped):
    from photo_edit import edit_photo
    return edit_photo(job,directory,report,stopped)
