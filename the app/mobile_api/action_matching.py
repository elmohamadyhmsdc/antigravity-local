"""Bounded stateless pose/action comparison for either identity kind.

Names, ownership and confirmation stay on the phone. These geometric ranking
scores are not action classifications or calibrated probabilities.
"""

import math

MIRROR = (0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15)
MAX_CANDIDATES = 64
MAX_FRAMES = 20


class ActionRequestError(ValueError):
    pass


def _sequence(raw, kind, max_span=120000):
    if not isinstance(raw, list) or not (1 <= len(raw) <= MAX_FRAMES):
        raise ActionRequestError('frames must contain 1–20 samples.')
    if (kind == 'photo' and len(raw) != 1) or (kind == 'video' and len(raw) < 3):
        raise ActionRequestError('A photo needs one sample; video needs at least three.')
    frames = []
    previous = None
    count = None
    for f in raw:
        if not isinstance(f, dict) or type(f.get('time')) is not int or f['time'] < 0:
            raise ActionRequestError('Every sample needs a non-negative integer time.')
        if previous is not None and not 0 < f['time'] - previous <= 15000:
            raise ActionRequestError('Video samples must be ordered and at most15 seconds apart after bounded resampling.')
        previous = f['time']
        members = f.get('members')
        if not isinstance(members, list) or not 1 <= len(members) <= 6:
            raise ActionRequestError('A sample needs one to six participants.')
        if count is not None and count != len(members):
            raise ActionRequestError('Participant count must stay constant within a sequence.')
        count = len(members)
        checked = []
        for m in members:
            if not isinstance(m, dict):
                raise ActionRequestError('Invalid participant pose.')
            data, mask, scale = m.get('points'), m.get('mask'), m.get('scale')
            if (not isinstance(data, list) or len(data) != 34 or
                    any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 100 for v in data) or
                    type(mask) is not int or not 0 <= mask < (1 << 17) or mask.bit_count() < 8 or
                    scale not in ('torso', 'shoulder', 'group')):
                raise ActionRequestError('A pose needs 34 finite coordinates, visibility and a known scale.')
            checked.append(dict(points=data, mask=mask, scale=scale))
        frames.append(dict(time=f['time'], members=checked))
    if frames[-1]['time'] - frames[0]['time'] > max_span:
        raise ActionRequestError('The sampled sequence exceeds the supported duration.')
    return frames


def _distance(a, b):
    if a['scale'] != b['scale']:
        return math.inf
    shared = (a['mask'] & b['mask']).bit_count()
    visible = (a['mask'] | b['mask']).bit_count()
    if shared < 8 or shared / visible < .7:
        return math.inf
    total = 0.0
    for i in range(17):
        if a['mask'] & b['mask'] & (1 << i):
            total += math.hypot(a['points'][2*i] - b['points'][2*i],
                                a['points'][2*i+1] - b['points'][2*i+1])
    return total / shared + (1 - shared / visible) * .5


def _mirrored(frames):
    result = []
    for f in frames:
        members = []
        for m in f['members']:
            data, mask = [0.0] * 34, 0
            for i, j in enumerate(MIRROR):
                data[2*j], data[2*j+1] = -m['points'][2*i], m['points'][2*i+1]
                if m['mask'] & (1 << i):
                    mask |= 1 << j
            members.append(dict(points=data, mask=mask, scale=m['scale']))
        result.append(dict(time=f['time'], members=members))
    return result


def _assignment(a, b):
    n = len(a)
    costs = [math.inf] * (1 << n)
    choices = [-1] * (1 << n)
    costs[0] = 0
    for mask in range(1 << n):
        i = mask.bit_count()
        if i == n or not math.isfinite(costs[mask]):
            continue
        for j in range(n):
            if mask & (1 << j):
                continue
            nxt = mask | (1 << j)
            score = costs[mask] + _distance(a[i], b[j])
            if score < costs[nxt]:
                costs[nxt], choices[nxt] = score, j
    if not math.isfinite(costs[-1]):
        return None
    mask, order = (1 << n) - 1, [0] * n
    for i in range(n-1, -1, -1):
        j = choices[mask]
        order[i] = j
        mask ^= 1 << j
    return order


def compare(query, candidate, allow_mirror=False):
    if len(query[0]['members']) != len(candidate[0]['members']):
        return None
    best = None
    for b in [candidate] + ([_mirrored(candidate)] if allow_mirror else []):
        order = _assignment(query[0]['members'], b[0]['members'])
        if order is None:
            continue

        def distance(left, right):
            return sum(_distance(left['members'][i], right['members'][j])
                       for i, j in enumerate(order)) / len(order)

        n, m = len(query), len(b)
        dp = [[math.inf] * (m+1) for _ in range(n+1)]
        steps = [[0] * (m+1) for _ in range(n+1)]
        dp[0][0] = 0
        for i in range(1, n+1):
            for j in range(1, m+1):
                if n > 1 and m > 1 and abs(i/n-j/m) > .3:
                    continue
                p, q = min(((i-1, j-1), (i-1, j), (i, j-1)), key=lambda x: dp[x[0]][x[1]])
                dp[i][j] = dp[p][q] + distance(query[i-1], b[j-1])
                steps[i][j] = steps[p][q] + 1
        if not math.isfinite(dp[n][m]):
            continue
        mean = dp[n][m] / steps[n][m]
        endpoints = (distance(query[0], b[0]) + distance(query[-1], b[-1])) / 2
        d = max(mean, endpoints * .8)
        score = math.exp(-d*d/(2*.35*.35))
        best = score if best is None else max(best, score)
    return best


def match_request(body):
    if not isinstance(body, dict) or body.get('kind') not in ('photo', 'video'):
        raise ActionRequestError('kind must be photo or video.')
    if type(body.get('allow_mirror', False)) is not bool:
        raise ActionRequestError('allow_mirror must be boolean.')
    kind = body['kind']
    query = _sequence(body.get('query'), kind)
    candidates = body.get('candidates')
    if not isinstance(candidates, list) or not 1 <= len(candidates) <= MAX_CANDIDATES:
        raise ActionRequestError('Send one to 64 candidate sequences.')
    parsed, ids = [], set()
    for c in candidates:
        if (not isinstance(c, dict) or not isinstance(c.get('id'), str) or
                not 1 <= len(c['id']) <= 128 or c['id'] in ids):
            raise ActionRequestError('Candidate IDs must be distinct strings of 1–128 characters.')
        ids.add(c['id'])
        parsed.append((c['id'], _sequence(c.get('frames'), kind, max_span=210000)))
    return dict(version=1, method='pose_geometry_temporal_v1', matches=[
        dict(id=key, score=compare(query, frames, body.get('allow_mirror', False)))
        for key, frames in parsed])
