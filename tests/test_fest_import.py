import importlib.util, pathlib, tempfile, unittest, zipfile
spec=importlib.util.spec_from_file_location('fest',pathlib.Path(__file__).parents[1]/'scripts/import_fest.py')
fest=importlib.util.module_from_spec(spec);spec.loader.exec_module(fest)
BASIC='''<FEST xmlns="http://www.kith.no/xmlstds/eresept/m30/2014-12-01"><HentetDato>2026-10-08T14:02:49</HentetDato><OppfInteraksjon><Id>w</Id><Tidspunkt>2026-10-08</Tidspunkt><Status V="A"/><Interaksjon><Id>record1</Id><Relevans V="1" DN="Bør unngås"/><KliniskKonsekvens>Original consequence</KliniskKonsekvens><Situasjonskriterium>Only oral doses</Situasjonskriterium><Kildegrunnlag V="4" DN="Indirect"/><Substansgruppe><Substans><Substans>A</Substans><Atc V="B01AC04" DN="A"/></Substans></Substansgruppe><Substansgruppe><Substans><Substans>B</Substans><Atc V="A02BC01" DN="B"/></Substans></Substansgruppe></Interaksjon></OppfInteraksjon></FEST>'''
def build(xml=BASIC,name='Fest_251_Rekvirent_20261013.xml'):
 with tempfile.TemporaryDirectory() as tmp:
  path=pathlib.Path(tmp)/'data.zip'
  with zipfile.ZipFile(path,'w') as z:z.writestr(name,xml)
  return fest.build(path,'Wed, 21 Oct 2026 10:13:57 GMT')
class ImportTest(unittest.TestCase):
 def test_context_and_missing_references_preserved(self):
  import gzip,json
  files,m=build();self.assertEqual(m['interactionCount'],1)
  record=next(json.loads(gzip.decompress(b))['records'][0] for name,b in files.items() if name.startswith('records-') and json.loads(gzip.decompress(b))['records'])
  self.assertEqual(record['situation'],'Only oral doses');self.assertEqual(record['references'],[])
 def test_unknown_clinical_field_fails(self):
  with self.assertRaises(ValueError):build(BASIC.replace('<KliniskKonsekvens>','<NewClinicalField>oops</NewClinicalField><KliniskKonsekvens>'))
 def test_inactive_record_requires_review(self):
  with self.assertRaises(ValueError):build(BASIC.replace('Status V="A"','Status V="U"'))
 def test_invalid_group_count_fails(self):
  with self.assertRaises(ValueError):build(BASIC.replace('</Interaksjon>','<Substansgruppe/></Interaksjon>'))
 def test_unknown_relevance_fails(self):
  with self.assertRaises(ValueError):build(BASIC.replace('Relevans V="1"','Relevans V="9"'))
 def test_nonpublic_archive_fails(self):
  with self.assertRaises(ValueError):build(name='../../Farmalogg.xml')
if __name__=='__main__':unittest.main()
