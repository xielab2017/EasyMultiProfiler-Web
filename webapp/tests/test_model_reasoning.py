import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from model_reasoning import capabilities,apply_effort,validate_effort
class ReasoningTests(unittest.TestCase):
 def test_unsupported_model_cannot_silently_accept_effort(self):
  self.assertEqual(capabilities('minimax','MiniMax-M3')['levels'],['auto'])
  with self.assertRaises(ValueError):validate_effort('high','minimax','MiniMax-M3')
  with self.assertRaises(ValueError):validate_effort({'code':'bad'},'openai','gpt-6')
 def test_protocols_use_actual_provider_fields_and_default_omits_overrides(self):
  p={'max_tokens':4096};apply_effort(p,'high','minimax','MiniMax-M3.1-Flash','anthropic');self.assertEqual(p['output_config'],{'effort':'high'});self.assertEqual(p['max_tokens'],16384)
  p={};apply_effort(p,'max','minimax','MiniMax-M3.1-Flash');self.assertEqual(p['reasoning_effort'],'max')
  p={};apply_effort(p,'medium','openai','gpt-5.4');self.assertEqual(p['reasoning_effort'],'medium')
  p={};apply_effort(p,'auto','minimax','MiniMax-M3');self.assertEqual(p,{})
 def test_model_specific_supported_levels(self):
  self.assertIn('xhigh',capabilities('openai','gpt-6.1')['levels'])
  self.assertNotIn('max',capabilities('openai','gpt-5')['levels'])
  self.assertIn('high',capabilities('claude','claude-opus-4-6','anthropic')['levels'])
  self.assertNotIn('medium',capabilities('gemini','gemini-3-pro-preview')['levels'])
 def test_nemotron_budget_uses_the_documented_chat_template_fields(self):
  p={};apply_effort(p,'medium','nvidia','nvidia/nemotron-3-super-120b-a12b')
  self.assertEqual(p['chat_template_kwargs'],{'enable_thinking':True,'reasoning_budget':2048});self.assertEqual(p['max_tokens'],4096)
  self.assertNotIn('reasoning_effort',p)
