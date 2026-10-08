type Env = (name: string) => string | undefined;
type Http = typeof fetch;
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {status, headers: {'Content-Type': 'application/json'}});

export function createAppleRevocationHandler(env: Env, http: Http = fetch) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return json(405, {error: 'POST required'});
    const authorization = req.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/.test(authorization)) return json(401, {error: 'Sign in required'});
    const project = env('SUPABASE_URL');
    const serviceKey = env('SUPABASE_SERVICE_ROLE_KEY');
    const clientId = env('APPLE_CLIENT_ID');
    const clientSecret = env('APPLE_CLIENT_SECRET');
    if (!project || !serviceKey || !clientId || !clientSecret) return json(503, {error: 'Account deletion is temporarily unavailable'});
    try {
      const authResponse = await http(`${project}/auth/v1/user`, {headers: {Authorization: authorization, apikey: serviceKey}});
      if (!authResponse.ok) return json(401, {error: 'Invalid session'});
      const user = await authResponse.json();
      const identity = user.identities?.find((i: {provider: string}) => i.provider === 'apple');
      const subject = identity?.identity_data?.sub ?? identity?.id;
      if (!user.id || typeof subject !== 'string' || !subject) return json(403, {error: 'Apple identity required'});
      const payload = await req.json();
      const code = payload.authorization_code;
      if (typeof code !== 'string' || !code.trim() || code.length > 4096) return json(400, {error: 'Authorization code required'});
      const exchange = await http('https://appleid.apple.com/auth/token', {
        method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({client_id: clientId, client_secret: clientSecret, code, grant_type: 'authorization_code'}),
      });
      if (!exchange.ok) return json(502, {error: 'Apple authorization failed'});
      const tokens = await exchange.json();
      // This token comes directly from Apple's authenticated HTTPS token endpoint,
      // never from the client. Bind it to the Apple identity in the verified session.
      const encoded = tokens.id_token?.split('.')[1];
      if (typeof encoded !== 'string') return json(502, {error: 'Apple identity unavailable'});
      const padded = encoded.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - encoded.length % 4) % 4);
      const claims = JSON.parse(atob(padded));
      if (claims.iss !== 'https://appleid.apple.com' || claims.aud !== clientId || claims.sub !== subject ||
          typeof claims.exp !== 'number' || claims.exp <= Date.now() / 1000) {
        return json(403, {error: 'Apple account does not match this session'});
      }
      const token = tokens.refresh_token ?? tokens.access_token;
      if (typeof token !== 'string' || !token) return json(502, {error: 'Apple token unavailable'});
      const revoke = await http('https://appleid.apple.com/auth/revoke', {
        method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({client_id: clientId, client_secret: clientSecret, token,
          token_type_hint: tokens.refresh_token ? 'refresh_token' : 'access_token'}),
      });
      if (!revoke.ok) return json(502, {error: 'Apple token revocation failed'});
      const recorded = await http(`${project}/rest/v1/nool_account_deletion_authorizations?on_conflict=user_id`, {
        method: 'POST', headers: {Authorization: `Bearer ${serviceKey}`, apikey: serviceKey,
          'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates'},
        body: JSON.stringify({user_id: user.id, expires_at: new Date(Date.now() + 10 * 60_000).toISOString()}),
      });
      if (!recorded.ok) return json(503, {error: 'Account deletion authorization could not be recorded'});
      return json(200, {revoked: true});
    } catch {
      return json(502, {error: 'Account deletion authorization failed'});
    }
  };
}
