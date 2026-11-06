"""Inspect originals without editing spreadsheets; build grade-aware app metadata."""
from pathlib import Path
import json, re, zipfile, xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
folder=root/'assets/deped_forms'
source=json.loads((folder/'sources.json').read_text(encoding='utf-8'))
records=[]; hashes=set(); keep=set()
for f in source['files']:
    if f['sha256'] in hashes: continue
    hashes.add(f['sha256'])
    path=root/f['asset']; name=f['filename']; text=(name+' '+f['title']).lower()
    ecr='ecr' in text or 'class record' in text or '/2018/08/' in f['source']
    archive=f['sourcePage'].endswith('e-class-record-templates/')
    kind='ecr' if ecr else 'school'
    minimum,maximum=0,12
    scope='All basic education levels; check edition'
    curriculum='any'; school_year=None; role='adviser'; note='Original published template. Check current school-year instructions before submission.'
    if archive:
        title=Path(name).stem.replace('_',' ').replace('-',' ')
        match=re.search(r'GRADE[ _-]*(\d+)(?:[ _-]+(\d+))?',name,re.I)
        if match:
            minimum=int(match[1]); maximum=int(match[2] or match[1])
        curriculum='legacy'; scope=f'Grades {minimum}–{maximum} · DO 8, s. 2015 reference'
        note='Historical four-quarter ECR. Not a verified DO 015, s. 2026 template. Available online; not bundled in the APK.'
    else: title=f['title']
    if 'alternative learning' in text: curriculum='als';scope='ALS only'; minimum=maximum=-1
    elif 'kinder' in text: minimum=maximum=0;scope='Kindergarten only'
    elif 'strengthened' in text or 'sshs' in text:
        minimum,maximum=11,12;curriculum='sshs_pilot';scope='Strengthened SHS pilot cohort'
        note='Corrected v2026 pilot template. DM 020, s. 2026 restricts use to pilot implementers until further notice. Confirm later rollout instructions.'
    elif 'sf10-shs' in text or 'senior high' in text:
        minimum,maximum=11,12;curriculum='legacy_shs';scope='Existing SHS curriculum'
    elif 'grade4' in text:
        minimum=maximum=4;school_year=2024;scope='Grade 4 · SY 2024–2025 cohort version'
    elif '-es-' in text:minimum,maximum=1,6;scope='Elementary · Grades 1–6'
    elif '-jhs-' in text:minimum,maximum=7,10;scope='Junior high · Grades 7–10'
    elif 'school forms spreadsheet' in text:
        minimum,maximum=1,10;scope='Elementary/JHS · SF1–SF7 reference';role='school'
    elif 'form 5 ' in text or 'form 6 ' in text: minimum,maximum=1,10;scope='Elementary/JHS · Grades 1–10'
    if 'form 6' in text:role='school'
    if ecr: role='teacher'
    sheets=[]
    if path.suffix=='.xlsx' and path.exists():
        with zipfile.ZipFile(path) as z:
            tree=ET.fromstring(z.read('xl/workbook.xml'))
            sheets=[s.attrib['name'] for s in tree.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}sheet')]
    bundled=not archive
    asset=f['asset'] if bundled else None
    if bundled:keep.add(path.name)
    records.append({**f,'title':title,'asset':asset,'kind':kind,'minGrade':minimum,'maxGrade':maximum,'curriculum':curriculum,'schoolYear':school_year,'scope':scope,'role':role,'note':note,'sheets':sheets,'authority':'DM 020, s. 2026' if curriculum=='sshs_pilot' else 'DO 8, s. 2015; DM 060, s. 2015' if archive else 'DO 58, s. 2017; DO 4, s. 2014', 'archive':archive})
for f in folder.iterdir():
    if f.suffix.lower() in ('.xlsx','.xls','.zip') and f.name not in keep:
        assert f.resolve().parent==folder.resolve()
        f.unlink()
catalog={'checked':'2026-11-06','sourceIndex':'https://support.lis.deped.gov.ph/support/','files':records,'unavailable':source['unavailable']}
(folder/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
doc=['# Official DepEd template library','', 'Source snapshot checked 6 November 2026. Files are unmodified public originals. Publication provenance is verified by SHA-256; applicability to a later school year is not implied.','',
     '## Selection rules','',
     '- K–10: DO 010, s. 2024 phased rollout. Kindergarten/Grades 1, 4, 7 from 2024; Grades 2, 5, 8 from 2025; Grades 3, 6, 9 from 2026; Grade 10 from 2027.',
     '- SHS: DM 012, s. 2026. Grade 11 starts Strengthened SHS in 2026–2027. Grade 12 remains on the existing curriculum except the continuing Strengthened SHS pilot cohort.',
     '- DM 020, s. 2026 corrected pilot ECR/SF10 files are restricted to the pilot scope until further notice; they are not recommended automatically for the incoming 2026 Grade 11 cohort.',
     '- The historical ECR download page explicitly references DO 8, s. 2015. Its spreadsheets are reference downloads, not verified DO 015, s. 2026 templates. They are excluded from 2026 recommendations.',
     '- DO 58, s. 2017 and DO 4, s. 2014 establish school-form families; use the current LIS-issued edition for official submissions.',
     '- No single current nationwide SF9 XLSX was established in this search. Do not substitute a fabricated template or certify the built-in draft as official.',
     '- DO 006, s. 2025 lists five report categories; it does not supply one identical workbook for every grade/subject. Lesson-preparation formats are referenced through DO 042, s. 2016.',
     '- ALS originals are available only in the all-reference browser, not recommended for formal K–12 classes.','',
     '## Originals','', '| File | Scope | Access | Official source |','|---|---|---|---|']
for f in records:doc.append(f"| {f['title']} | {f['scope']} | {'Offline' if f['asset'] else 'Online / cached after download'} | [Download]({f['source'].replace(' ','%20')}) |")
doc+=['','## Boundaries','','The library exports blank originals unchanged. It does not automatically fill health, personnel, book inventory, school-wide consolidation or permanent historical records from incomplete class data. Existing KlaseKo generators remain working drafts. A teacher can import an approved Excel layout through the existing mapper for supported data fields. Do not present reconstructed files as LIS-generated submissions.','',f"Unavailable published downloads: {len(source['unavailable'])}. See assets/deped_forms/sources.json for details."]
(root/'docs/OFFICIAL-FORMS.md').write_text('\n'.join(doc)+'\n',encoding='utf-8')
print('Catalog:',len(records),'offline originals:',len(keep))
for f in records:
    if f['asset']: print(f['title'],f['scope'],'sheets:',', '.join(f['sheets']))
