'use strict';
// Observe native cold-hook descriptors and inject pathname mutations only.
// The product's reader/admission/revalidation code is never replaced.
const fs=require('node:fs'),assert=require('node:assert/strict');
const open=fs.openSync,read=fs.readSync,close=fs.closeSync;
const paths=new Map(),owned=new Set(),variant=process.env.VARIANT,c=process.env.CASE_ROOT;
let changed=false,contentOpens=0,reads=0,maxRead=0;
fs.openSync=function(p,flags,...args){
  if(typeof p==='string'&&p.startsWith('/proc/self/fd/')){
    contentOpens++;
    const admitted=paths.get(Number(p.split('/').at(-1)));
    const target=variant.includes('-primary-')?'/opt/bookorbit/.env':'/opt/bookorbit/server/.env';
    if(variant.startsWith('cfg-race-')&&admitted===target&&!changed){
      changed=true;fs.renameSync(target,target+'.old');
      if(variant.endsWith('-fifo'))require('node:child_process').execFileSync('/usr/bin/mkfifo',[target]);
      else fs.symlinkSync('/dev/zero',target);
    }
    assert(fs.fstatSync(Number(p.split('/').at(-1))).isFile(),'content open must name admitted regular metadata FD');
  }else if((flags&0o10000000)===0){
    try{const s=fs.statSync(p);assert(s.isFile()||s.isDirectory(),'special file opened for content');}catch(error){if(error.code!=='ENOENT')throw error;}
  }
  const fd=open.call(fs,p,flags,...args);if((flags&0o10000000)!==0){paths.set(fd,p);owned.add(fd);}else if(typeof p==='string'&&p.startsWith('/proc/self/fd/'))owned.add(fd);return fd;
};
fs.closeSync=function(fd){const result=close.call(fs,fd);owned.delete(fd);paths.delete(fd);return result;};
fs.readSync=function(fd,buffer,offset,length,...args){reads++;maxRead=Math.max(maxRead,length);assert(length<=1048577,'config read request exceeds bound');return read.call(fs,fd,buffer,offset,length,...args);};
process.on('exit',()=>{
  assert.equal(owned.size,0,'config metadata/content descriptor leaked');
  if(variant.startsWith('cfg-race-'))assert(changed,'pathname mutation was not reached');
  fs.appendFileSync(c+'/config-observations',JSON.stringify({variant,contentOpens,reads,maxRead,changed,FDs_closed:true})+'\n');
  console.error('CONFIG_FD_GREEN '+variant+' admitted regular descriptors only; bounded reads; FDs closed');
});
