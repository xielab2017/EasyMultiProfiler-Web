"""Local-owner model loading; saving never performs an external model call."""
import json
from urllib.parse import urlsplit
import model_settings
import model_catalog
import model_plugins
from workbench_api import local_owner


def install(Handler):
    old_get, old_post = Handler.do_GET, Handler.do_POST
    path = '/api/public-data/agent/config'

    def get(self):
        route = urlsplit(self.path).path
        if route not in {path, '/api/public-data/agent/plugins'}: return old_get(self)
        if not local_owner(self): return self.reply(403, {'error': 'Local owner origin required'})
        if route.endswith('/plugins'):
            return self.reply(200, {'api_version': 1, 'plugins': list(model_plugins.providers().values())})
        return self.reply(200, model_settings.public_status())

    def post(self):
        route=urlsplit(self.path).path
        if route not in {path,'/api/public-data/agent/plugins/install','/api/public-data/agent/plugins/uninstall','/api/public-data/agent/models','/api/public-data/agent/test','/api/public-data/agent/ui-localize'}: return old_post(self)
        if not local_owner(self): return self.reply(403, {'error': 'Local owner origin required'})
        if self.headers.get('Transfer-Encoding') or self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
            return self.reply(415, {'error': 'Bounded JSON settings required'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 8192: return self.reply(413, {'error': 'Model settings exceed the request limit'})
            self.connection.settimeout(15)
            value = json.loads(self.rfile.read(size))
            if not isinstance(value,dict):raise ValueError('Settings object required')
            if route.endswith('/plugins/uninstall'):
                result = model_plugins.uninstall_manifest(value)
                model_settings.clear(provider=result['provider'])
                return self.reply(200,result)
            if route.endswith('/plugins/install'):
                return self.reply(200,model_plugins.install_manifest(value))
            if route.endswith('/ui-localize'):
                import ui_translation_build
                return self.reply(200,ui_translation_build.translate(value))
            if route.endswith('/test'):
                import agent_adapter
                if value.pop('consent',False) is not True:return self.reply(400,{'error':'Explicit test consent required'})
                runtime=dict(model_settings.validate_configuration(value), revision=model_settings.public_status()['config_revision'])
                result=agent_adapter.respond('Connection test using a synthetic planning request only: call propose_count_workflow with question "bulk RNA-seq raw counts PCA DESeq2 edgeR heatmap", then report that the draft was not executed.',True,expected_config_revision=runtime['revision'],_runtime_override=runtime)
                return self.reply(200,{'provider':runtime['provider'],'model':runtime['model'],'chat_verified':result['status']=='ok','tool_verified':any(row['status']=='ok' for row in result['audit']),'status':result['status'],'audit':result['audit'],'answer':result['answer']})
            if route.endswith('/models'):return self.reply(200,model_catalog.discover(value))
            if value == {'reset_runtime': True}: return self.reply(200, model_settings.clear())
            return self.reply(200, model_settings.configure(value))
        except model_settings.GenerationOptionError as exc:
            return self.reply(400, {'error': str(exc)})
        except (ValueError, TypeError, OSError) as exc:
            if route.endswith(('/ui-localize','/plugins/install','/plugins/uninstall')):return self.reply(400,{'error':str(exc)[:220]})
            return self.reply(400, {'error': 'Choose one chat model, a supported provider/Base URL and its API key. Settings were not loaded.'})
    Handler.do_GET, Handler.do_POST = get, post
