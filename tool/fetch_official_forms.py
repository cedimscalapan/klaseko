"""Download unmodified public DepEd templates and record provenance.

Only retrieves links published on the specified official pages. Never executes downloads.
"""
import hashlib
import json
import urllib.request
import urllib.parse
import zipfile
import io
from html.parser import HTMLParser
from pathlib import Path
from datetime import date

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets' / 'deped_forms'
DEST.mkdir(parents=True, exist_ok=True)

class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links=[]; self.href=None; self.label=[]
    def handle_starttag(self, tag, attrs):
        if tag=='a': self.href=dict(attrs).get('href'); self.label=[]
    def handle_data(self, data):
        if self.href: self.label.append(data)
    def handle_endtag(self, tag):
        if tag=='a' and self.href:
            self.links.append((self.href,' '.join(' '.join(self.label).split()))); self.href=None

def read(url):
    parts=urllib.parse.urlsplit(url)
    url=urllib.parse.urlunsplit(('https',parts.netloc,urllib.parse.quote(urllib.parse.unquote(parts.path),safe='/'),parts.query,parts.fragment))
    req=urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=60) as response: return response.read()

pages=[
    'https://support.lis.deped.gov.ph/support/',
    'https://catanduanes.deped.gov.ph/new-school-forms.html',
    'https://www.deped.gov.ph/alternative-learning-system/resources/downloads/e-class-record-templates/',
]
entries=[]; seen=set(); errors=[]
for page in pages:
    try:
        parser=Links(); parser.feed(read(page).decode('utf-8',errors='replace'))
    except Exception as e:
        errors.append({'url':page,'error':str(e)}); continue
    for href,label in parser.links:
        url=urllib.parse.urljoin(page,href)
        path=urllib.parse.unquote(urllib.parse.urlparse(url).path)
        ext=Path(path).suffix.lower()
        if ext not in ('.xlsx','.xls','.zip','.docx'): continue
        host=urllib.parse.urlparse(url).hostname or ''
        if host!='deped.gov.ph' and not host.endswith('.deped.gov.ph'): continue
        lower=(path+' '+label).lower()
        if page==pages[0] and not any(s in lower for s in ['schoolform','school form','sf 10','ecr','e-class']): continue
        if url in seen: continue
        seen.add(url)
        ident='official_'+hashlib.sha256(url.encode()).hexdigest()[:12]
        try:
            existing=ROOT/f'assets/deped_forms/{ident}{ext}'
            content=existing.read_bytes() if existing.exists() else read(url)
            if ext in ('.xlsx','.docx','.zip'):
                with zipfile.ZipFile(io.BytesIO(content)) as z:
                    members=z.namelist()
                    if ext=='.xlsx' and 'xl/workbook.xml' not in members: raise ValueError('Not an XLSX workbook')
            if ext=='.xls' and not content.startswith(bytes.fromhex('D0CF11E0')): raise ValueError('Not an XLS workbook')
            asset=f'assets/deped_forms/{ident}{ext}'
            (ROOT/asset).write_bytes(content)
            entries.append({'id':ident,'title':label or Path(path).stem,'filename':Path(path).name,'source':url,'sourcePage':page,'asset':asset,'sha256':hashlib.sha256(content).hexdigest(),'bytes':len(content),'retrieved':date.today().isoformat()})
            print('Saved:',label or Path(path).name, len(content),flush=True)
        except Exception as e: errors.append({'url':url,'error':str(e)}); print('Unavailable:',url,str(e),flush=True)

(DEST/'sources.json').write_text(json.dumps({'retrieved':date.today().isoformat(),'files':entries,'unavailable':errors},ensure_ascii=False,indent=2),encoding='utf-8')
print('Total:',len(entries),'unavailable:',len(errors))
