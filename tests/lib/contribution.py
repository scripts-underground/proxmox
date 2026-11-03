"""Fixed contribution consumers in an owned output projection, not source refresh."""
import os
import json
from html.parser import HTMLParser
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import urlsplit
from urllib.parse import unquote
import xml.etree.ElementTree as ET

from test_context import AdmissionError, Context, Run, require, sha


def preflight(context):
    """Same read-only budget/retirement gate for direct and supervised entry."""
    from test_pve import NativePVE
    require((context.operation['suite'],context.operation['mode'])==('contribution','contribution'),'contribution source scope required')
    for item in context.document['operations']:
        if 'native' in item:
            require(all(NativePVE.observe_static(v['ctid'],item['native']) is None for v in item['nested']),'contribution requires nested resources retired')
    memory=dict(v.split(':',1) for v in Path('/proc/meminfo').read_text().splitlines() if ':' in v)
    require(int(memory['MemAvailable'].split()[0])*1024>6*1024**3,'contribution 5GiB plus guest reserve admission')
    usage=os.statvfs(context.operation['runs']);require(usage.f_bavail*usage.f_frsize>3*1024**3,'contribution output workspace admission')


class HTML(HTMLParser):
    def __init__(self,text):
        super().__init__(convert_charrefs=True);self.active=[];self.nodes=[];self.references=[];self.images=[];self.feed(text)

    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='img':self.images.append(attrs)
        if tag in ('title','h1','a','code','script'):
            self.active.append(dict(tag=tag,attrs=attrs,parts=[]))
        for key in ('src','href'):
            if attrs.get(key):self.references.append((tag,key,attrs[key]))

    def handle_data(self,data):
        for item in self.active:item['parts'].append(data)

    def handle_endtag(self,tag):
        for item in reversed(self.active):
            if item['tag']==tag:
                self.active.remove(item);self.nodes.append(dict(tag=tag,attrs=item['attrs'],text=''.join(item['parts'])));break

    def text(self,tag):return [' '.join(v['text'].split()) for v in self.nodes if v['tag']==tag]


def read_json(path):
    try:return json.loads(path.read_text())
    except (OSError,ValueError) as error:raise AdmissionError('contribution catalogue/AST JSON invalid: '+str(path)) from error


def metadata(source):
    program=r'''r={}; %w[lxc addon pve vm].each{|t| Dir.glob("_#{t}/*.md").sort.each{|f| s=File.read(f);m=s.match(/\A---\s*\n(.*?\n)---\s*\n/m);next unless m;v=YAML.safe_load(m[1]);slug=v["slug"]||File.basename(f,".md");key="#{t}/#{slug}";raise "duplicate metadata #{key}" if r.key?(key);r[key]={"title"=>v["title"]||slug,"logo"=>v["logo"]} }};puts JSON.generate(r)'''
    result=subprocess.run(['/usr/bin/ruby','-rjson','-ryaml','-e',program],cwd=source,capture_output=True,text=True,timeout=40)
    require(result.returncode==0,'contribution metadata consumer failed: '+result.stderr)
    return json.loads(result.stdout)


def public_file(root,url):
    path=urlsplit(url).path
    require(path.startswith('/') and not any(v in ('.','..') for v in path.split('/')),'contribution public link unsafe')
    result=root/path.lstrip('/')
    require(result.resolve().is_relative_to(root.resolve()),'contribution public file escapes output')
    return result


def consume_fallbacks(images):
    # Missing primary logo files are an existing product contract: both Liquid
    # logos and cardHTML declare a real SVG error fallback. Execute that actual
    # emitted handler; never infer success merely from an onerror attribute.
    body='''const fs=require("fs"),vm=require("vm");const rows=JSON.parse(fs.readFileSync(0,"utf8"));let out=[];for(const a of rows){const i={src:a.src,onerror:true,dataset:{light:a["data-light"],dark:a["data-dark"]}};vm.runInNewContext("(function(){"+a.onerror+"}).call(image)",{image:i,document:{documentElement:{classList:{contains:()=>false}}}},{timeout:1000});out.push(i);}process.stdout.write(JSON.stringify(out));'''
    result=subprocess.run(['/usr/bin/node','-e',body],input=json.dumps(images),capture_output=True,text=True,timeout=30)
    require(result.returncode==0,'contribution logo fallback handler failed: '+result.stderr)
    values=json.loads(result.stdout);require(len(values)==len(images),'contribution fallback count differs')
    facts=[]
    for image,value in zip(images,values):
        require(value['onerror'] is None and value['src'].startswith('data:image/svg+xml,'),'contribution logo fallback did not produce SVG')
        try:svg=ET.fromstring(unquote(value['src'].split(',',1)[1]))
        except ET.ParseError as error:raise AdmissionError('contribution logo fallback XML invalid') from error
        require(svg.tag=='{http://www.w3.org/2000/svg}svg' and svg.attrib.get('width')==image.get('width') and svg.attrib.get('height')==image.get('height') and ''.join(svg.itertext()).strip(),'contribution logo fallback geometry/label missing')
        facts.append(dict(primary=image['src'],width=svg.attrib['width'],height=svg.attrib['height'],svg_sha256=sha(value['src'].encode()),handler_cleared=True))
    return facts


def consume(source,projection,site,expected,card_output=None):
    catalogue=read_json(projection/'scripts.json');built=read_json(site/'scripts.json')
    rows=catalogue.get('scripts');require(type(rows) is list and catalogue.get('meta',{}).get('total')==len(rows)==len(expected)>0,'contribution catalogue count differs from source metadata')
    mapping={v['type']+'/'+v['slug']:v for v in rows}
    require(len(mapping)==len(rows) and set(mapping)==set(expected) and built==catalogue,'contribution catalogue coverage/built crosslinks differ')
    assets={};fallbacks={};pages={};ast_count=0
    def assets_for(page):
        for tag,attr,url in page.references:
            path=urlsplit(url).path
            if path.startswith('/assets/') or path in ('/favicon-light.png','/favicon-dark.png'):
                original=public_file(source,url);output=public_file(site,url)
                if original.is_file():
                    require(output.is_file() and output.read_bytes()==original.read_bytes(),'contribution asset crosslink/bytes differ: '+path)
                    assets[path]=sha(output.read_bytes())
                else:
                    images=[v for v in page.images if v.get('src')==url]
                    require(tag=='img' and attr=='src' and not output.exists() and images and all(v.get('onerror') for v in images),'contribution missing asset has no declared fallback: '+path)
                    for image in images:fallbacks[sha(json.dumps(image,sort_keys=True).encode())]=image
    for key,item in mapping.items():
        meta=expected[key];kind,slug=key.split('/',1)
        require(item['title']==meta['title'] and item['logo']==meta['logo'] and item['page']=='/'+key+'/' and item['script']=='/scripts/'+key+'.sh','contribution catalogue metadata/link mismatch: '+key)
        script=public_file(source,item['script'])
        if script.exists():
            generated=read_json(projection/'_ast'/(key+'.json'));ast=read_json(site/'ast'/(key+'.json'))
            require(generated==ast and ast.get('schema_version')==2 and ast.get('slug')==slug and ast.get('type')==kind and ast.get('source')==script.read_text(),'contribution AST/source consumer mismatch: '+key)
            require(public_file(site,item['script']).read_bytes()==script.read_bytes(),'contribution published script bytes differ: '+key);ast_count+=1
        file=public_file(site,item['page'])/'index.html';text=file.read_text();page=HTML(text)
        require(page.text('h1')==[' '.join(meta['title'].split())] and any(v.startswith(' '.join(meta['title'].split())+' | ') for v in page.text('title')),'contribution HTML title differs: '+key)
        require('var slug = '+json.dumps(slug)+';' in text and 'fetch("/scripts.json")' in text and "var astUrl = '/ast/' + s.type + '/' + s.slug + '.json';" in text,'contribution HTML catalogue/AST reference differs: '+key)
        require(any(item['script'] in v['text'] for v in page.nodes if v['tag']=='code' and 'install-code' in v['attrs'].get('class','').split()),'contribution HTML script reference differs: '+key)
        assets_for(page);pages[key]=file
    for kind in ('lxc','addon','pve','vm'):
        page=HTML((site/kind/'index.html').read_text());assets_for(page)
        links=[n for n in page.nodes if n['tag']=='a' and n['attrs'].get('href') in {v['page'] for k,v in mapping.items() if k.startswith(kind+'/')}]
        require(len(links)==min(20,sum(k.startswith(kind+'/') for k in expected)),'contribution category card count differs: '+kind)
        for link in links:
            key=link['attrs']['href'].strip('/');require(' '.join(link['text'].split())==' '.join(expected[key]['title'].split()),'contribution category card title/link differs')
    home=HTML((site/'index.html').read_text());assets_for(home)
    flags=[v['text'] for v in home.nodes if v['tag']=='script' and 'window.renderFlagPills = function' in v['text']]
    require(len(flags)==1,'contribution actual flag renderer missing')
    # Execute the emitted real card renderer against the emitted catalogue. The
    # only modeled browser capability is the dark-theme predicate (false).
    body='''const fs=require("fs"),vm=require("vm");const d=JSON.parse(fs.readFileSync(0,"utf8"));const s={window:{},document:{documentElement:{classList:{contains:()=>false}}}};vm.createContext(s);vm.runInContext(d.flags,s,{timeout:1000});vm.runInContext(fs.readFileSync(d.cards,"utf8"),s,{timeout:1000});s.rows=d.rows;process.stdout.write(JSON.stringify(vm.runInContext("rows.map((r,i)=>cardHTML(r,i))",s,{timeout:10000})));'''
    result=subprocess.run(['/usr/bin/node','-e',body],input=json.dumps(dict(flags=flags[0],cards=str(site/'assets/js/cards.js'),rows=rows)),capture_output=True,text=True,timeout=25)
    require(result.returncode==0,'contribution actual card renderer failed: '+result.stderr)
    cards=json.loads(result.stdout);require(len(cards)==len(expected),'contribution runtime card count differs')
    for item,text in zip(rows,cards):
        page=HTML(text);links=[v for v in page.nodes if v['tag']=='a' and v['attrs'].get('href')==item['page']]
        require(len(links)==1 and ' '.join(links[0]['text'].split())==' '.join(item['title'].split()),'contribution runtime card title/link differs')
        assets_for(page)
    fallback_facts=consume_fallbacks(list(fallbacks.values()))
    if card_output is not None:card_output.write_text(result.stdout)
    return dict(metadata=len(expected),catalogue=len(rows),html_pages=len(pages),ast_sources=ast_count,runtime_cards=len(cards),card_output_sha256=sha(result.stdout.encode()),local_assets=len(assets),assets=assets,logo_fallbacks=fallback_facts,missing_primary_logos=len({v['primary'] for v in fallback_facts}))


def output_negatives(run,source,projection,site,expected):
    rows=read_json(site/'scripts.json')['scripts'];item=next(v for v in rows if public_file(source,v['script']).is_file())
    html=public_file(site,item['page'])/'index.html';ast=site/'ast'/item['type']/(item['slug']+'.json');catalogue=site/'scripts.json'
    changed=read_json(catalogue);changed['scripts'][0]['script']='/scripts/lxc/owned-corrupt-link.sh'
    ast_bad=read_json(ast);ast_bad['source']+='\n# owned corruption control\n'
    card_js=site/'assets/js/cards.js'
    controls=[('invalid-json',catalogue,b'{'),('wrong-script-link',catalogue,json.dumps(changed).encode()),('wrong-ast-source',ast,json.dumps(ast_bad).encode()),('wrong-html-reference',html,html.read_bytes().replace(b'fetch("/scripts.json")',b'fetch("/owned-corrupt.json")',1)),('wrong-required-asset',card_js,card_js.read_bytes()+b'\n// owned corruption control\n')]
    missing=next((v for v in rows if v.get('logo','') and v['logo'].startswith('/assets/') and not public_file(source,v['logo']).is_file()),None)
    if missing:
        page=public_file(site,missing['page'])/'index.html';raw=page.read_bytes();controls.append(('broken-declared-logo-fallback',page,re.sub(b'onerror="[^"]*"',b'onerror="this.onerror=null"',raw,count=1)))
    for name,path,bad in controls:
        require(path.is_relative_to(run.directory) and not path.is_symlink(),'owned output control scope')
        original=path.read_bytes();require(bad!=original,'owned output corruption did not change bytes')
        try:
            path.write_bytes(bad)
            try:consume(source,projection,site,expected)
            except AdmissionError as error:run.record('contribution-negative',dict(control=name,path=str(path),refused=True,reason=str(error),original_sha256=sha(original),corrupt_sha256=sha(bad)))
            else:raise AdmissionError('contribution corrupted owned output accepted: '+name)
        finally:path.write_bytes(original)
        require(path.read_bytes()==original,'owned output restore failed');run.context.recheck()


def main():
    context = Context.admit(os.environ['SU_TEST_CONTEXT'],'contribution','contribution')
    preflight(context)
    with Run(context) as run:
        source = Path(context.document['source']['path'])
        projection = run.directory/'projection'
        shutil.copytree(source,projection,symlinks=True)
        env = dict(os.environ,TMPDIR=context.operation['tmpdir'],HOME=str(run.directory),GOTOOLCHAIN='local',GOMAXPROCS='2',
                   MAKEFLAGS='-j2',BUNDLE_JOBS='2',PRE_COMMIT_HOME=str(Path(context.document['target']['workspace'])/'cache/pre-commit'),PYTHONDONTWRITEBYTECODE='1',
                   JEKYLL_ENV='production',PAGES_REPO_NWO='scripts-underground/proxmox')
        commands = [
            ['pre-commit','run','--all-files','--show-diff-on-failure'],
            ['/usr/local/go/bin/go','test','-C','tools/ast','./...'],
            ['/usr/local/go/bin/go','run','-C','tools/ast','.'],
            ['/usr/bin/ruby','tools/regen-scripts-json.rb'],
            ['bundle','exec','jekyll','build','--destination',str(run.directory/'site')],
        ]
        end=time.monotonic()+context.operation['deadline']
        for number, argv in enumerate(commands):
            context.recheck()
            with (run.directory/f'contribution-{number}.log').open('x') as log:
                result = subprocess.run(argv,cwd=projection,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=max(1,end-time.monotonic()),umask=0o022)
            run.record('contribution-consumer',dict(argv=argv,status=result.returncode))
            if result.returncode:
                return result.returncode
        result = subprocess.run(['/usr/bin/git','--no-optional-locks','diff','--binary'],cwd=projection,capture_output=True,check=True,timeout=30)
        (run.directory/'generated.diff').write_bytes(result.stdout)
        site = run.directory/'site'
        expected=metadata(source)
        consume(source,projection,site,expected)
        output_negatives(run,source,projection,site,expected)
        outcome=consume(source,projection,site,expected,run.directory/'runtime-cards.json');context.recheck()
        outputs=[site/'scripts.json',site/'index.html',*(site/k/'index.html' for k in ('lxc','addon','pve','vm'))]
        for key in expected:
            outputs.append(site/key/'index.html')
            if (source/'scripts'/(key+'.sh')).is_file():outputs.extend([site/'ast'/(key+'.json'),site/'scripts'/(key+'.sh')])
        outputs.extend(public_file(site,path) for path in outcome['assets'])
        manifest=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p.read_bytes())) for p in sorted(set(outputs))]
        run.record('contribution-output-manifest',dict(source=context.document['source']['tree_sha256'],files=manifest))
        samples=[site/'scripts.json',site/'index.html',site/'assets/js/cards.js',site/'assets/css/style.css']
        for key in list(expected)[:1]+['lxc/odysseus','lxc/calibre-web-automated']:
            if key in expected:samples.extend([site/key/'index.html',site/'ast'/(key+'.json'),site/'scripts'/(key+'.sh')])
        evidence=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p.read_bytes())) for p in sorted(set(samples)) if p.is_file()]
        run.record('contribution-outputs',dict(**outcome,source=context.document['source']['tree_sha256'],catalogue_sha256=sha((projection/'scripts.json').read_bytes()),generated_diff_sha256=sha(result.stdout),site=str(site),evidence=evidence))
        print('CONTRIBUTION_CONSUMERS_PASS '+json.dumps({k:v for k,v in outcome.items() if k not in ('assets','logo_fallbacks')},sort_keys=True),flush=True)
        return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (AdmissionError,OSError,subprocess.SubprocessError) as error:
        print('CONTEXT_REFUSED:',error,file=sys.stderr)
        raise SystemExit(65)
