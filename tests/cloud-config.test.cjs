const {test}=require('node:test');
const assert=require('node:assert/strict');
const env={TK_PUBLIC_ORIGIN:'https://game.example.test',SUPABASE_URL:'https://game.supabase.co',
  SUPABASE_PUBLISHABLE_KEY:'sb_publishable_example',DATABASE_URL:'postgresql://server:example@database.test:5432/postgres?sslmode=verify-full',
  TK_ALLOWED_EMAILS:'Player@example.test,friend@example.test'};
test('production config validates and keeps credentials server-side',async()=>{
  const {loadCloudConfig}=await import('../scripts/cloud-config.mjs');const c=loadCloudConfig(env,'/game');
  assert.equal(c.publicOrigin,env.TK_PUBLIC_ORIGIN);assert.equal(c.host,'127.0.0.1');
  assert.deepEqual(c.allowedEmails,['player@example.test','friend@example.test']);assert.equal(c.webDir,'/game/build/web-online');
});
test('production config rejects unsafe or incomplete setup without echoing secrets',async()=>{
  const {loadCloudConfig}=await import('../scripts/cloud-config.mjs');
  const bad=[{TK_PUBLIC_ORIGIN:'http://game.test'},{TK_PUBLIC_ORIGIN:'https://secret@game.test'},
    {TK_PUBLIC_ORIGIN:'https://game.test/path'},{TK_PUBLIC_ORIGIN:'https://game.test?secret=1'},
    {SUPABASE_URL:'http://project.test'},{SUPABASE_PUBLISHABLE_KEY:'sb_secret_secret'},
    {DATABASE_URL:'postgresql://server:SECRET@db.test:6543/postgres'},
    {DATABASE_URL:'postgresql://server:SECRET@db.test/db?sslmode=no-verify'},
    {DATABASE_URL:'postgresql://server:SECRET@db.test/db?pgbouncer=true'},
    {TK_ALLOWED_EMAILS:''},{TK_ALLOWED_EMAILS:'a@example.test,A@example.test'},
    {PORT:'0'},{PORT:'3080.1'},{TK_HOST:'example.test'},{TK_DB_NAMESPACE:'../data'},
    {NODE_TLS_REJECT_UNAUTHORIZED:'0'}];
  for(const patch of bad){let error;try{loadCloudConfig({...env,...patch});}catch(value){error=value;}
    assert.ok(error,JSON.stringify(Object.keys(patch)));assert.ok(!error.message.includes('SECRET'));}
  assert.throws(()=>loadCloudConfig({}),/TK_PUBLIC_ORIGIN/);
});
