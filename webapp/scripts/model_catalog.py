"""Bounded provider model discovery. No prompts, files or runtime settings are sent/changed."""
import json
from urllib.request import Request, build_opener, HTTPRedirectHandler
import model_settings

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None

def discover(value):
    value=dict(value);value['model']=value.get('model') if value.get('model') not in {None,'','auto','fusion','mixed'} else 'catalog-probe'
    cfg=model_settings.validate_configuration(value);provider=cfg['provider'];endpoint=cfg['endpoint']
    headers={'Accept':'application/json'}
    if cfg['key']:headers['x-api-key' if provider=='claude' else 'Authorization']=cfg['key'] if provider=='claude' else 'Bearer '+cfg['key']
    if provider=='claude':headers['anthropic-version']='2023-06-01'
    if provider=='minimax':url=('https://api.minimax.cn' if cfg['region']=='china' else 'https://api.minimax.io')+'/v1/models'
    elif provider=='claude':url='https://api.anthropic.com/v1/models'
    else:url=endpoint.removesuffix('/chat/completions')+'/models'
    with build_opener(NoRedirect()).open(Request(url,headers=headers),timeout=20) as response:raw=response.read(1024**2+1)
    if len(raw)>1024**2:raise ValueError('Model list exceeds limit')
    data=json.loads(raw);models=[];seen=set()
    if not isinstance(data,dict) or not isinstance(data.get('data'),list):raise ValueError('Provider did not return a model list')
    for item in data.get('data',[])[:2000]:
        if not isinstance(item,dict):continue
        model=item.get('id')
        if not isinstance(model,str) or not model or len(model)>200 or any(ord(c)<33 for c in model) or model in seen:continue
        seen.add(model);created=item.get('created',item.get('created_at'))
        if isinstance(created,(int,float)) and 0<=created<2**40:date=created
        elif isinstance(created,str) and len(created)<=40:date=created
        else:date=None
        models.append({'id':model,'created':date})
    models.sort(key=lambda m:(m['created'] is not None,str(m['created'] or ''),m['id']),reverse=True)
    if not models:raise ValueError('No model IDs returned by this endpoint')
    return {'provider':provider,'models':models[:500],'source':'provider_models_endpoint','live_chat_verified':False,'latest_is_known':any(m['created'] is not None for m in models)}
