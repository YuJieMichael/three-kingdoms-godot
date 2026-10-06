const {test}=require('node:test');const assert=require('node:assert/strict');
test('backup rejects edits, cross-world restore and malformed metadata',async()=>{
  const {encodeBackup,decodeBackup}=await import('../scripts/cloud-backup.mjs');
  const fixture={schema:1,namespace:'test-world',version:'3',snapshot:{schema:1,rooms:[],requests:[]}};
  const text=encodeBackup(fixture,1234);
  assert.deepEqual(decodeBackup(text,'test-world').snapshot,fixture.snapshot);
  assert.throws(()=>decodeBackup(text,'other-world'),/namespace/);
  assert.throws(()=>decodeBackup(text.replace('"version":"3"','"version":"4"'),'test-world'),/checksum/);
  assert.throws(()=>decodeBackup(text.replace('"createdAt":1234','"createdAt":-1'),'test-world'),/Invalid/);
  assert.throws(()=>decodeBackup('null','test-world'),/Invalid/);
});
test('private backup output rejects public directories and symlink aliases before reading secrets',async t=>{
  const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
  const {privateBackupOutput}=await import('../scripts/cloud-backup.mjs');
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'tk-backup-output-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const web=path.join(root,'public');await fs.mkdir(web);await fs.mkdir(path.join(root,'build'));
  await assert.rejects(privateBackupOutput(path.join(web,'new','world.json'),{TK_WEB_DIR:web},root),/Web/);
  await assert.rejects(privateBackupOutput(path.join(root,'build','web','world.json'),{TK_WEB_DIR:web},root),/Web/);
  if(process.platform!=='win32'){
    await fs.symlink(web,path.join(root,'alias'),'dir');
    await assert.rejects(privateBackupOutput(path.join(root,'alias','world.json'),{TK_WEB_DIR:web},root),/Web/);
  }
  assert.equal(await privateBackupOutput(path.join(root,'private','world.json'),{TK_WEB_DIR:web},root),path.join(await fs.realpath(root),'private','world.json'));
});
