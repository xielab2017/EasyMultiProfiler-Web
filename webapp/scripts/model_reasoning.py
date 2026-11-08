"""Provider-documented effort controls; unknown models receive no guessed parameter."""
import re
LEVELS=('auto','low','medium','high','xhigh','max')
SOURCES={
 'minimax':'https://platform.minimax.cn/docs/guides/text-generation',
 'openai':'https://developers.openai.com/api/docs/guides/reasoning',
 'claude':'https://platform.claude.com/docs/en/build-with-claude/effort',
 'gemini':'https://ai.google.dev/gemini-api/docs/openai',
 'nvidia':'https://docs.nvidia.com/nim/large-language-models/1.15.0/thinking-budget-control.html',
}
def capabilities(provider,model,protocol='openai'):
    name=model.lower();values=[]
    if provider=='minimax' and name.startswith('minimax-m3.1'):values=list(LEVELS[1:])
    elif provider=='nvidia' and name=='nvidia/nemotron-3-super-120b-a12b':values=list(LEVELS[1:4])
    elif provider in {'openai','chatgpt'} and re.match(r'(gpt-[56]|o[134](?:-|$))',name) and not name.startswith(('o1-mini','o1-preview')):
        values=list(LEVELS[1:] if name.startswith('gpt-6') else LEVELS[1:4])
    elif provider=='claude' and re.search(r'claude-(?:opus-(?:4-[5-9]|[5-9])|sonnet-(?:4-[6-9]|[5-9])|haiku-[5-9]|fable-[5-9])',name):values=list(LEVELS[1:4])
    elif provider=='gemini' and re.match(r'gemini-(?:2\.5|3|4)',name):
        values=['low','high'] if name.startswith('gemini-3-pro') else list(LEVELS[1:4])
    parameter='chat_template_kwargs.reasoning_budget' if provider=='nvidia' else 'output_config.effort' if protocol=='anthropic' else 'reasoning_effort'
    return {'supported':bool(values),'levels':['auto',*values],'parameter':parameter,'documentation':SOURCES.get(provider),**({'budgets':{'low':256,'medium':2048,'high':8192}} if provider=='nvidia' and values else {})}
def validate_effort(value,provider,model,protocol='openai'):
    if not isinstance(value,str) or value not in LEVELS:raise ValueError('Invalid reasoning effort')
    info=capabilities(provider,model,protocol)
    if value not in info['levels']:raise ValueError('This model has no documented support for the selected thinking depth; use model default or select a supported model.')
    return info

def apply_effort(payload,value,provider,model,protocol='openai'):
    validate_effort(value,provider,model,protocol)
    if value=='auto':return
    if provider=='nvidia':
        budget={'low':256,'medium':2048,'high':8192}[value]
        payload['chat_template_kwargs']={**payload.get('chat_template_kwargs',{}),'enable_thinking':True,'reasoning_budget':budget}
        payload['max_tokens']=budget+2048
        return
    if protocol=='anthropic':payload['output_config']={**payload.get('output_config',{}),'effort':value}
    else:payload['reasoning_effort']=value
    # Leave bounded space for reasoning and the final response.
    budget=16384 if value in {'high','xhigh','max'} else 8192
    if protocol=='anthropic':payload['max_tokens']=max(payload.get('max_tokens',0),budget)
    else:
        payload.pop('max_tokens',None);payload['max_completion_tokens']=max(payload.get('max_completion_tokens',0),budget)
