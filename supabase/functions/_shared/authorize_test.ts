import { isAuthorizedServerRequest } from './authorize.ts';
const name = 'NOOL_SERVER_WEBHOOK_SECRET';
Deno.test('webhooks fail closed without a configured secret', () => {
  const previous = Deno.env.get(name);
  try {
    Deno.env.delete(name);
    if (isAuthorizedServerRequest(new Request('https://example.com'))) throw new Error('Allowed unauthenticated request');
  } finally {
    if (previous === undefined) Deno.env.delete(name); else Deno.env.set(name, previous);
  }
});
Deno.test('webhooks require the exact server secret', () => {
  const previous = Deno.env.get(name);
  try {
    Deno.env.set(name, 'test-server-secret');
    for (const supplied of ['', 'test-server-secreu', 'other']) {
      if (isAuthorizedServerRequest(new Request('https://example.com', {headers: {'x-nool-webhook-secret': supplied}}))) {
        throw new Error('Invalid secret accepted');
      }
    }
    if (!isAuthorizedServerRequest(new Request('https://example.com', {headers: {'x-nool-webhook-secret': 'test-server-secret'}}))) {
      throw new Error('Valid secret rejected');
    }
  } finally {
    if (previous === undefined) Deno.env.delete(name); else Deno.env.set(name, previous);
  }
});
