#!/usr/bin/env python3
"""Full rebuild of public human FEST interaction reference; never connects to pharmacy DB.
Usage: python scripts/import_fest.py /path/to/fest251.zip --last-modified 'HTTP date'
Only use the public Rekvirent human extract linked by DMP, never Farmalogg/NAV files.
"""
import argparse, collections, datetime, gzip, hashlib, json, pathlib, re, shutil, tempfile, zipfile
import xml.etree.ElementTree as ET
ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = 'https://www.dmp.no/globalassets/documents/om-oss/distribusjon-av-legemiddeldata/fest/festfiler/fest251.zip'
ATTRIBUTION = 'Contains data under the Norwegian licence for Open Government data (NLOD) distributed by the Norwegian Medical Products Agency (DMP).'
def tag(e): return e.tag.rsplit('}', 1)[-1]
def text(e, name): return e.findtext('{*}' + name, default='').strip()
def code(e): return {'code': e.get('V', ''), 'label': e.get('DN', '')} if e is not None else None
def sha(b): return hashlib.sha256(b).hexdigest()
def packed(value): return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
def require(ok, message):
    if not ok: raise ValueError(message)
def build(path, modified):
    raw = path.read_bytes()
    require(len(raw) < 40_000_000, 'ZIP too large')
    wrappers, substances, basis = [], {}, ''
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        require(len(names) == 1 and re.fullmatch(r'Fest_251_Rekvirent_\d{8}\.xml', names[0]), 'Unexpected public extract')
        require(z.getinfo(names[0]).file_size < 200_000_000, 'XML too large')
        xml_hash = hashlib.sha256()
        with z.open(names[0]) as f:
            for block in iter(lambda: f.read(1024*1024), b''): xml_hash.update(block)
        with z.open(names[0]) as f:
            for _, e in ET.iterparse(f, events=['end']):
                t = tag(e)
                if t == 'HentetDato': basis = (e.text or '').strip()
                if t == 'OppfVirkestoff':
                    s = e.find('{*}Virkestoff')
                    if s is not None and e.find('{*}Status').get('V') == 'A':
                        value = (text(s, 'Navn'), text(s, 'NavnEngelsk'))
                        sid = text(s, 'Id')
                        require(sid not in substances or substances[sid] == value, 'Conflicting substance ID')
                        substances[sid] = value
                if t == 'OppfInteraksjon': wrappers.append(ET.tostring(e))
                if t.startswith('Oppf'): e.clear()
    require(basis and wrappers, 'Missing source basis or interactions')
    english = collections.defaultdict(set)
    for no, en in substances.values():
        if no and en: english[no.casefold()].add(en)
    members, records, unassessed, seen = {}, [], [], set()
    def member(s):
        no = text(s, 'Substans')
        a, ref = s.find('{*}Atc'), text(s, 'RefVirkestoff')
        require(bool(a is not None) != bool(ref), 'Substance must have one identity')
        require(set(map(tag, s)) <= {'Substans','Atc','RefVirkestoff'}, 'Unknown substance field')
        if a is not None:
            v = a.get('V', '')
            require(v == 'WITHOUT' or bool(re.fullmatch(r'[A-Z](?:\d{2}(?:[A-Z](?:[A-Z](?:\d{2})?)?)?)?', v)), 'Unsupported ATC syntax')
            key = 'atc:' + v
            names = {no, a.get('DN','')}
            aliases = {next(iter(english[n.casefold()])) for n in names if len(english[n.casefold()]) == 1}
        else:
            require(ref in substances, 'Unresolved substance reference')
            key = 'substance:' + ref
            names = {no, substances[ref][0]}
            aliases = {substances[ref][1]}
        m = members.setdefault(key, {'id':key,'names':set(),'english':set()})
        m['names'].update(n for n in names if n)
        m['english'].update(n for n in aliases if n)
        return key
    allowed = {'Id','Relevans','KliniskKonsekvens','Interaksjonsmekanisme','Kildegrunnlag','Handtering','Visningsregel','Referanse','Substansgruppe','Situasjonskriterium'}
    for raw_e in wrappers:
        w = ET.fromstring(raw_e)
        require(w.find('{*}Status').get('V') == 'A', 'Unexpected inactive record; review source schema')
        e = w.find('{*}Interaksjon')
        if e is None:
            u = w.find('{*}InteraksjonIkkeVurdert')
            require(u is not None and set(map(tag,u)) == {'Atc'}, 'Unknown unassessed shape')
            # Represent source unassessed codes without inventing interactions.
            s = ET.Element('Substans'); s.append(u.find('{*}Atc'))
            unassessed.append(member(s)); continue
        require(set(map(tag,e)) <= allowed, 'Unknown interaction field')
        rid = text(e,'Id'); require(rid and rid not in seen, 'Duplicate interaction ID'); seen.add(rid)
        relevance = code(e.find('{*}Relevans'))
        require(relevance['code'] in {'1','2','3'}, 'Unknown relevance')
        groups = []
        for g in e.findall('{*}Substansgruppe'):
            require(set(map(tag,g)) <= {'Navn','Substans'}, 'Unknown group field')
            keys = sorted(set(member(s) for s in g.findall('{*}Substans')))
            require(keys, 'Empty interaction group')
            groups.append({'name':text(g,'Navn'),'members':keys})
        require(len(groups)==2, 'Interaction must have exactly two groups')
        refs=[]
        for r in e.findall('{*}Referanse'):
            require(set(map(tag,r)) <= {'Kilde','Lenke'}, 'Unknown reference field')
            refs.append({'citation':text(r,'Kilde'),'url':r.find('{*}Lenke').get('V','') if r.find('{*}Lenke') is not None else ''})
        consequence = text(e,'KliniskKonsekvens'); require(consequence, 'Missing clinical consequence')
        records.append({'id':rid,'updatedAt':text(w,'Tidspunkt'),'relevance':relevance,'groups':groups,
          'consequence':consequence,'situation':text(e,'Situasjonskriterium'), 'mechanism':text(e,'Interaksjonsmekanisme'),
          'management':text(e,'Handtering'),'evidence':code(e.find('{*}Kildegrunnlag')),
          'audiences':[code(x) for x in e.findall('{*}Visningsregel')],'references':refs})
    sorted_members=[]
    for key,m in sorted(members.items()):
        sorted_members.append({**m,'names':sorted(m['names']),'english':sorted(m['english']),
          'selectable':key.startswith('substance:') or bool(re.fullmatch(r'atc:[A-Z]\d{2}[A-Z]{2}\d{2}', key))})
    indices = {m['id']:i for i,m in enumerate(sorted_members)}
    buckets = [[] for _ in range(16)]; light=[]
    for r in sorted(records,key=lambda r:r['id']):
        bucket = int(sha(r['id'].encode())[0],16)
        for g in r['groups']: g['members'] = [indices[k] for k in g['members']]
        buckets[bucket].append(r)
        light.append({'id':r['id'],'groups':[g['members'] for g in r['groups']],'relevance':r['relevance']['code'],'shard':bucket})
    snapshot = sha(raw)[:16]
    index = {'snapshot':snapshot,'members':sorted_members,'records':light,'unassessed':sorted(set(indices[k] for k in unassessed))}
    files = {'index.json.gz':gzip.compress(packed(index),mtime=0)}
    for i,b in enumerate(buckets):files[f'records-{i:02x}.json.gz']=gzip.compress(packed({'snapshot':snapshot,'records':b}),mtime=0)
    manifest = {'format':1,'snapshot':snapshot,'source':'DMP FEST public human Rekvirent 2.5.1','sourceUrl':SOURCE,
      'sourcePage':'https://www.dmp.no/en/about-us/distribution-of-data-on-medicinal-products/electronic-prescription-support-system-fest/responsibility-when-using-fest',
      'license':'NLOD 2.0','licenseUrl':'https://data.norge.no/nlod/en/2.0','attribution':ATTRIBUTION,
      'modifications':'Human interaction and unassessed records extracted; identities indexed; English search aliases from unambiguous FEST substance names. Original Norwegian clinical prose retained. No local clinical approval or product equivalence inferred.',
      'sourceFile':names[0],'basisDate':basis,'zipSha256':sha(raw),'xmlSha256':xml_hash.hexdigest(),'lastModified':modified,
      'importedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'interactionCount':len(records),'unassessedCount':len(unassessed),
      'memberCount':len(members),'relevanceCounts':dict(collections.Counter(r['relevance']['code'] for r in records)),
      'files':{name:{'sha256':sha(b),'bytes':len(b)} for name,b in files.items()}}
    files['manifest.json'] = packed(manifest)
    return files,manifest
if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('zip',type=pathlib.Path);p.add_argument('--last-modified',required=True);a=p.parse_args()
    files,m=build(a.zip,a.last_modified)
    dest=ROOT/'public/clinical/fest'
    dest.parent.mkdir(parents=True,exist_ok=True)
    # Parse and validate everything before replacing a previous complete snapshot.
    with tempfile.TemporaryDirectory(dir=dest.parent) as tmp:
        for name,b in files.items():(pathlib.Path(tmp)/name).write_bytes(b)
        backup = dest.with_name('fest-previous-snapshot')
        require(not backup.exists(), 'Previous interrupted rebuild requires inspection')
        if dest.exists():dest.rename(backup)
        try:
            shutil.copytree(tmp,dest)
        except Exception:
            if dest.exists():shutil.rmtree(dest)
            if backup.exists():backup.rename(dest)
            raise
        if backup.exists():shutil.rmtree(backup)
    (ROOT/'src/festManifest.json').write_bytes(packed(m))
    print(json.dumps({k:v for k,v in m.items() if k!='files'},indent=2))
    print('Total normalized bytes:',sum(map(len,files.values())))
