"""Short-lived operation events, without prompts, arguments or model reasoning."""
import re
import threading
import time

_lock = threading.Lock()
_runs = {}

def start(run_id):
    if not isinstance(run_id, str) or not re.fullmatch(r'[a-f0-9]{32}', run_id):
        raise ValueError('Invalid agent run ID')
    with _lock:
        for key in list(_runs):
            if time.monotonic() - _runs[key]['created'] > 1800:
                del _runs[key]
        if run_id in _runs:
            raise ValueError('Agent run ID already used')
        if len(_runs) >= 100:
            del _runs[min(_runs, key=lambda k: _runs[k]['created'])]
        _runs[run_id] = {'created': time.monotonic(), 'events': []}

def emit(run_id, stage, **values):
    if not run_id:
        return
    event = {'stage': stage}
    event.update({key: value for key, value in values.items() if key in {'tool', 'status', 'duration_ms'}})
    with _lock:
        if run_id in _runs:
            _runs[run_id]['events'] = (_runs[run_id]['events'] + [event])[-48:]

def get(run_id):
    if not isinstance(run_id, str) or not re.fullmatch(r'[a-f0-9]{32}', run_id):
        return None
    with _lock:
        row = _runs.get(run_id)
        if not row or time.monotonic() - row['created'] > 1800:
            return None
        return {'run_id': run_id, 'events': [dict(event) for event in row['events']]}
