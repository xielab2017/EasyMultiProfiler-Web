"""Owner-selected model configuration, held in memory without logging credentials."""
import model_plugins
import ipaddress
import math
import re
import threading
import time
from urllib.parse import urlsplit, urlunsplit

_lock = threading.RLock()
_active = None
_revision = 0
_verified = None
FIXED = {'openai': 'https://api.openai.com/v1/chat/completions',
         'nvidia': 'https://integrate.api.nvidia.com/v1/chat/completions',
         'openrouter': 'https://openrouter.ai/api/v1/chat/completions',
         'deepseek': 'https://api.deepseek.com/chat/completions',
         'monica':'https://openapi.monica.im/v1/chat/completions',
         'gemini':'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
         'claude':'https://api.anthropic.com/v1/messages',
         'qwen': 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'}


def endpoint(base):
    if not isinstance(base, str) or len(base) > 1000 or any(ord(c) < 33 for c in base):
        raise ValueError('Provide a valid API Base URL')
    url = urlsplit(base)
    if url.scheme not in {'http', 'https'} or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('Use an HTTP(S) API Base URL without credentials, query or fragment')
    if url.hostname.lower() in {'metadata.google.internal', 'instance-data'}:
        raise ValueError('Cloud metadata endpoints are not model APIs')
    try:
        address = ipaddress.ip_address(url.hostname)
    except ValueError:
        address = None
    if address and (address.is_link_local or address.is_multicast or address.is_unspecified):
        raise ValueError('This address is not a supported model API destination')
    if url.scheme == 'http' and url.hostname != 'localhost' and not (address and (address.is_private or address.is_loopback)):
        raise ValueError('Use HTTPS for a public model API')
    path = url.path.rstrip('/')
    if not path.endswith('/chat/completions'): path += '/chat/completions'
    return urlunsplit((url.scheme, url.netloc, path, '', ''))


class GenerationOptionError(ValueError):
    pass


def validate_configuration(value):
    if not isinstance(value, dict) or set(value) - {'provider', 'model', 'api_key', 'base_url', 'enabled', 'region', 'protocol', 'profile_id', 'temperature', 'max_tokens_output'}:
        raise ValueError('Unsupported model settings')
    provider = value.get('provider')
    plugin = model_plugins.providers().get(provider) if isinstance(provider, str) and provider.startswith('plugin-') else None
    if not plugin and provider not in {*FIXED, 'custom', 'campus', 'minimax'}: raise ValueError('Select a single supported chat provider, or a custom OpenAI-compatible API')
    model = value.get('model', '')
    if not isinstance(model, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}', model) or model in {'auto', 'fusion', 'mixed'}:
        raise ValueError('Select one explicit chat model for the research agent')
    key = value.get('api_key', '')
    if not isinstance(key, str) or len(key) > 4096 or any(ord(c) < 33 for c in key): raise ValueError('Invalid API credential format')
    if provider not in {'custom', 'campus'} and not key: raise ValueError('An API key is required for this provider')
    if type(value.get('enabled')) is not bool: raise ValueError('Explicitly choose whether to enable model requests')
    base = value.get('base_url', '')
    protocol=value.get('protocol','anthropic' if provider=='claude' else 'openai');region=value.get('region','china')
    if provider == 'minimax':
        if protocol not in {'openai','anthropic'} or region not in {'china','international'}:raise ValueError('Choose MiniMax region and protocol')
        host='https://api.minimax.cn' if region=='china' else 'https://api.minimax.io'
        expected=host+('/v1' if protocol=='openai' else '/anthropic')
        if base and base.rstrip('/') != expected:raise ValueError('MiniMax Base URL must match the chosen region and protocol')
        target=expected+('/chat/completions' if protocol=='openai' else '/v1/messages')
    elif provider=='claude':
        if protocol!='anthropic' or base and base.rstrip('/') not in {'https://api.anthropic.com/v1','https://api.anthropic.com/v1/messages'}:raise ValueError('Use the official Claude Messages endpoint')
        target=FIXED[provider]
    elif provider=='gemini':
        if protocol!='openai' or base and base.rstrip('/') not in {'https://generativelanguage.googleapis.com/v1beta','https://generativelanguage.googleapis.com/v1beta/openai'}:raise ValueError('Use the official Gemini endpoint')
        target=FIXED[provider]
    elif protocol != 'openai':raise ValueError('This provider uses the OpenAI-compatible transport')
    elif plugin:
        target = endpoint(plugin['base_url'])
        if not base or endpoint(base) != target:
            raise ValueError('Plugin endpoint changed; reload its configuration')
    elif provider in {'custom', 'campus'}: target = endpoint(base)
    else:
        target = FIXED[provider]
        if base and endpoint(base) != target: raise ValueError('Use the custom provider for a custom Base URL')
    options = {}
    if 'profile_id' in value:
        profile_id = value['profile_id']
        if not isinstance(profile_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', profile_id):
            raise ValueError('Invalid model profile identifier')
        options['profile_id'] = profile_id
    if 'temperature' in value:
        temperature = value['temperature']
        if type(temperature) not in (int, float) or not 0 <= temperature <= 2 or not math.isfinite(temperature):
            raise GenerationOptionError('Temperature must be between 0 and 2')
        if provider == 'minimax':
            raise GenerationOptionError('MiniMax uses its fixed sampling temperature. Leave Temperature empty.')
        if provider == 'openai' and re.match(r'(gpt-[56]|o[134](?:-|$))', model.lower()):
            raise GenerationOptionError('Leave Temperature empty for this OpenAI reasoning model in EMP.')
        if provider == 'claude' and re.search(r'claude-(?:opus-4[.-][7-9]|(?:opus|sonnet|haiku)-[5-9]|mythos|fable)', model.lower()):
            raise GenerationOptionError('Leave Temperature empty for this Claude model.')
        if protocol == 'anthropic' and temperature > 1:
            raise GenerationOptionError('Anthropic-compatible temperature must be between 0 and 1')
        options['temperature'] = temperature
    if 'max_tokens_output' in value:
        limit = value['max_tokens_output']
        if type(limit) is not int or not 1 <= limit <= 65536:
            raise GenerationOptionError('Maximum output must be an integer between 1 and 65536 tokens')
        options['max_tokens_output'] = limit
    return dict(provider=provider,model=model,key=key,endpoint=target,enabled=value['enabled'],protocol=protocol,region=region if provider=='minimax' else None, **options)


def configure(value):
    global _active, _revision, _verified
    selected=validate_configuration(value)
    with _lock:
        _revision += 1
        _active = dict(selected,revision=_revision)
        _verified = None
        return public_status()


def active():
    with _lock: return dict(_active) if _active else None


def runtime_snapshot():
    """Bind consent to a revision even when environment configuration is active."""
    with _lock:
        return active(), _revision


def clear(provider=None):
    global _active, _revision, _verified
    with _lock:
        if provider is not None and (not _active or _active["provider"] != provider): return public_status()
        _active = None; _revision += 1; _verified = None
        return public_status()


def mark_verified(config,tool=False):
    global _verified
    with _lock:
        if _active and config.get('revision') == _active['revision'] and all(config.get(k)==_active.get(k) for k in ('provider','model','key','endpoint','enabled','protocol','temperature','max_tokens_output','profile_id')):
            _verified={'live_chat_verified':True,'live_tools_verified':bool(tool or (_verified and _verified['live_tools_verified'])),'verified_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}


def public_status():
    with _lock:
        value = active()
        verified = dict(_verified or {'live_chat_verified': False, 'live_tools_verified': False})
        revision = _revision
    if not value: return {'source': 'environment', 'runtime_configured': False, 'config_revision': revision}
    target = urlsplit(value['endpoint'])
    return {'source': 'runtime_memory', 'runtime_configured': True, 'provider': value['provider'],
            'model': value['model'], 'enabled': value['enabled'], 'credential_present': bool(value['key']),
            'endpoint_origin': urlunsplit((target.scheme, target.netloc, '', '', '')),
            'protocol':value['protocol'],'region':value['region'],
            **{key: value[key] for key in ('profile_id', 'temperature', 'max_tokens_output') if key in value},
            'config_revision': value['revision'], 'live_verified': verified['live_chat_verified'] and verified['live_tools_verified'], **verified}
