import { createAppleRevocationHandler } from './handler.ts';
const config: Record<string,string> = {
  SUPABASE_URL: 'https://test.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'server-fixture',
  APPLE_CLIENT_ID: 'com.efeardaaric.nool', APPLE_CLIENT_SECRET: 'apple-fixture',
};
const request = () => new Request('https://test.invalid', {
  method:'POST', headers:{Authorization:'Bearer session-fixture'}, body:JSON.stringify({authorization_code:'code-fixture'}),
});
function fixture(options: {subject?:string; revokeStatus?:number; recordStatus?:number; exchangeStatus?:number} = {}) {
  const calls: Array<{url:string; body?:string}> = [];
  const http = (async (url: string | URL | Request, init?:RequestInit) => {
    const target=String(url);calls.push({url:target,body:init?.body?.toString()});
    if(target.endsWith('/auth/v1/user')) return Response.json({id:'user-a',identities:[{provider:'apple',identity_data:{sub:'apple-a'}}]});
    if(target.endsWith('/auth/token')) {
      const claims=btoa(JSON.stringify({iss:'https://appleid.apple.com',aud:config.APPLE_CLIENT_ID,
        sub:options.subject??'apple-a',exp:Math.floor(Date.now()/1000)+3600})).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
      return Response.json({id_token:`header.${claims}.signature`,refresh_token:'refresh-fixture'}, {status:options.exchangeStatus??200});
    }
    if(target.endsWith('/auth/revoke')) return new Response(null,{status:options.revokeStatus??200});
    if(target.includes('/rest/v1/nool_account_deletion_authorizations')) return new Response(null,{status:options.recordStatus??201});
    throw new Error('Unexpected outbound request');
  }) as typeof fetch;
  return {calls,handler:createAppleRevocationHandler(name=>config[name],http)};
}
function equal(actual: unknown, expected:unknown) {if(actual!==expected) throw new Error(`Expected ${expected}, got ${actual}`);}
Deno.test('missing bearer rejects before outbound requests',async()=>{
  const f=fixture(); const result=await f.handler(new Request('https://test.invalid',{method:'POST'}));equal(result.status,401);equal(f.calls.length,0);
});
Deno.test('missing server credentials fail closed',async()=>{
  let called=false; const handler=createAppleRevocationHandler(()=>undefined,(()=>{called=true;throw new Error();}) as typeof fetch);
  equal((await handler(request())).status,503);equal(called,false);
});
Deno.test('another Apple account cannot be revoked',async()=>{
  const f=fixture({subject:'apple-b'});equal((await f.handler(request())).status,403);equal(f.calls.length,2);
});
Deno.test('Apple exchange failure cannot authorize deletion',async()=>{
  const f=fixture({exchangeStatus:400});equal((await f.handler(request())).status,502);equal(f.calls.length,2);
});
Deno.test('revocation failure cannot authorize deletion',async()=>{
  const f=fixture({revokeStatus:400});equal((await f.handler(request())).status,502);equal(f.calls.length,3);
});
Deno.test('recording failure cannot report success',async()=>{
  const f=fixture({recordStatus:500});equal((await f.handler(request())).status,503);
});
Deno.test('verified revocation records only a temporary self-deletion authorization',async()=>{
  const f=fixture(); const response=await f.handler(request());equal(response.status,200);equal((await response.json()).revoked,true);
  equal(f.calls.length,4);const record=JSON.parse(f.calls[3].body!);equal(record.user_id,'user-a');
  equal(Object.keys(record).sort().join(','),'expires_at,user_id');
  const lifetime=Date.parse(record.expires_at)-Date.now();if(lifetime<=0||lifetime>600000)throw new Error('Invalid lifetime');
  const form=new URLSearchParams(f.calls[2].body);equal(form.get('token'),'refresh-fixture');equal(form.get('token_type_hint'),'refresh_token');
});
