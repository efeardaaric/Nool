import { createAppleRevocationHandler } from './handler.ts';
Deno.serve(createAppleRevocationHandler((name) => Deno.env.get(name)));
