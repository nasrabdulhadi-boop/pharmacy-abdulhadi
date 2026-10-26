import hashlib
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from research_primary_label_cases import extract_case

SET_ID='00000000-0000-4000-8000-000000000001'
CASE={'set_id':SET_ID,'ingredient_a':'synthetic-a','ingredient_b':'synthetic-b','section_prefix':'4.3','quote':'Synthetic source statement.'}
XML=f'''<document xmlns="urn:hl7-org:v3"><id root="00000000-0000-4000-8000-000000000002"/><setId root="{SET_ID}"/><versionNumber value="1"/><effectiveTime value="20261026"/><component><section><id root="00000000-0000-4000-8000-000000000003"/><title>4.3 Synthetic section</title><text><paragraph>Synthetic source statement.</paragraph></text></section></component></document>'''.encode()

class PrimaryLabelCollectorTests(unittest.TestCase):
 def test_exact_excerpt_and_version_hash_are_retained_without_approval(self):
  result=extract_case(XML,CASE,'2026-10-26T00:00:00Z')
  self.assertEqual(result['original_text'],CASE['quote'])
  self.assertEqual(result['source_sha256'],hashlib.sha256(XML).hexdigest())
  self.assertEqual(result['source_version'],'1')
  self.assertFalse(result['clinical_approved'])
  self.assertEqual(result['license_status'],'unknown')
 def test_source_set_id_mismatch_is_rejected(self):
  with self.assertRaises(ValueError): extract_case(XML,{**CASE,'set_id':'other'},'2026-10-26')
 def test_missing_or_ambiguous_quote_is_not_inferred(self):
  with self.assertRaises(ValueError): extract_case(XML,{**CASE,'quote':'Synthetic safe combination.'},'2026-10-26')
  section=XML[XML.index(b'<component>')+len(b'<component>'):XML.index(b'</component>')]
  doubled=XML.replace(b'</component>',section+b'</component>')
  with self.assertRaises(ValueError): extract_case(doubled,CASE,'2026-10-26')
 def test_entity_declarations_and_oversized_xml_are_rejected(self):
  for data in [b'<!DOCTYPE document [<!ENTITY x "bad">]>'+XML,b'x'*5_000_001]:
   with self.assertRaises(ValueError): extract_case(data,CASE,'2026-10-26')
 def test_missing_version_and_long_quote_are_rejected(self):
  with self.assertRaises(ValueError): extract_case(XML.replace(b'<versionNumber value="1"/>',b''),CASE,'2026-10-26')
  quote=' '.join(['word']*26)
  xml=XML.replace(b'Synthetic source statement.',quote.encode())
  with self.assertRaises(ValueError): extract_case(xml,{**CASE,'quote':quote},'2026-10-26')

if __name__=='__main__': unittest.main()
