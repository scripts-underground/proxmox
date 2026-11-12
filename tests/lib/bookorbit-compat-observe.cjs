'use strict';
// Synthetic filesystem metadata vectors, never a native filesystem qualification.
// All ordinary lookup/FD/inode facts remain produced by the actual guest kernel.
const fs=require('node:fs'),read=fs.readFileSync,open=fs.openSync,v=process.env.VARIANT;
if(v.startsWith('compat-fs-')){
  const ambiguous=v==='compat-fs-network-ambiguous',kind=ambiguous?'cifs':v.slice('compat-fs-'.length);
  const appDomain=read.call(fs,'/proc/self/mountinfo','utf8').split('\n').map(l=>l.split(' - ')[0].split(' ')).find(f=>f[4]==='/opt')[2];
  fs.readFileSync=function(p,...args){
    const value=read.call(fs,p,...args);if(p!=='/proc/self/mountinfo')return value;
    return value.split('\n').map(line=>{
      const pair=line.split(' - ');if(pair.length!==2)return line;const tail=pair[1].split(' ');
      if(!['ext4','xfs','tmpfs'].includes(tail[0])||(!ambiguous&&pair[0].split(' ')[2]!==appDomain))return line;
      tail[0]=kind;const head=pair[0].split(' ');if(kind==='nfs4'){tail[1]='fixture-nas:'+head[3];head[3]='/';}
      return head.join(' ')+' - '+tail.join(' ');
    }).join('\n');
  };
}
if(v==='compat-missing-within'){
  let changed=false;
  fs.openSync=function(p,...args){try{return open.call(fs,p,...args);}catch(error){if(!changed&&p==='/mnt/missing/missing.epub'&&error.code==='ENOENT'){changed=true;fs.writeFileSync(p,'appeared during lookup');}throw error;}};
}
