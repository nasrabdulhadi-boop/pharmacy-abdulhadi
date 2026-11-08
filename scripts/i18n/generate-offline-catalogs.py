"""Build-time offline draft translations. Never reads pharmacy data or credentials.
Requires ctranslate2==4.6.0 and sentencepiece==0.2.1 outside the web app runtime.
Input: English interface JSON and a local M2M100 CT2 model (see audit report).
Usage: python generate-offline-catalogs.py MODEL_DIR ENGLISH_JSON OUTPUT_DIR
"""
import json,pathlib,re,sys,time
import ctranslate2,sentencepiece
model,source_path,output=sys.argv[1:];root=pathlib.Path(output);root.mkdir(parents=True,exist_ok=True)
catalog=json.load(open(source_path));sp=sentencepiece.SentencePieceProcessor(model_file=model+'/sentencepiece.bpe.model')
translator=ctranslate2.Translator(model,device='cpu',compute_type='int8',inter_threads=1,intra_threads=8)
# Interpolated business values and technical identifiers must survive byte-for-byte.
protected=re.compile(r'(\{\d+\}|\b(?:USD|SYP|QA|RLS|RPC|CSV|JSON|FEFO|Supabase|Vercel|Auth|POS|API|RTL|LTR)\b|\b\d+(?:[,.]\d+)*\b)')
parts={k:protected.split(v)for k,v in catalog.items()}
fragments=sorted({p.strip()for a in parts.values()for p in a if p.strip()and not protected.fullmatch(p)and re.search('[A-Za-z]',p)},key=len)
for lang in ['ru','tr','ro','fr','de']:
 began=time.time();translations={};path=root/(lang+'.js')
 for offset in range(0,len(fragments),32):
  batch=fragments[offset:offset+32];tokens=[['__en__']+sp.encode(p,out_type=str)+['</s>']for p in batch]
  results=translator.translate_batch(tokens,target_prefix=[['__'+lang+'__']]*len(batch),beam_size=2,max_decoding_length=256,max_batch_size=32)
  for phrase,result in zip(batch,results):
   translated=sp.decode([t for t in result.hypotheses[0]if not t.startswith('__')and t not in ['<s>','</s>','<pad>']]).strip()
   translations[phrase]=translated or phrase
  if offset%320==0:print(lang,offset,'/',len(fragments),'seconds',round(time.time()-began),flush=True)
 result={}
 for key,pieces in parts.items():
  result[key]=''.join(p.replace(p.strip(),translations[p.strip()])if p.strip()in translations else p for p in pieces)
  assert sorted(re.findall(r'\{\d+\}',result[key]))==sorted(re.findall(r'\{\d+\}',catalog[key]))
 path.write_text('// Offline draft; reviewed UI terminology overrides are applied separately.\nexport default '+json.dumps(result,ensure_ascii=False,indent=2)+';\n')
 print(lang,'completed',len(result),'messages',round(time.time()-began),'seconds',flush=True)
