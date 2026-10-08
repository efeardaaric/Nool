/** Server-only entry points must fail closed before reading payloads. */
export function isAuthorizedServerRequest(request: Request): boolean {
  const secret = Deno.env.get('NOOL_SERVER_WEBHOOK_SECRET');
  if (!secret) return false;
  const supplied = request.headers.get('x-nool-webhook-secret') ?? '';
  if (supplied.length !== secret.length) return false;
  let difference = 0;
  for (let i = 0; i < secret.length; i++) {
    difference |= secret.charCodeAt(i) ^ supplied.charCodeAt(i);
  }
  return difference === 0;
}
