// A supabase-js stand-in for chat-mark-read.test.cjs — only `rpc`, because `markChatRead` calls
// nothing else. Every call is RECORDED (name + args, in order), and each RPC's answer is scripted
// per test: a value, an error, or a DEFERRED promise the test resolves later (the reviewer's
// measurement used a delayed skew error, so the fake must be able to hold one open).
//
// An RPC nobody scripted THROWS, so a wrapper that starts calling something new fails loudly rather
// than being answered by accident — including the retired now()-writer, which is exactly the call
// this suite exists to prove never happens.
//
// On globalThis, not module scope: the test requires this file directly AND the api.ts bundle
// resolves `./supabase` to it — one shared state either way.
const state = globalThis.__chatMarkReadFake
  || (globalThis.__chatMarkReadFake = { calls: [], script: {} });

const supabase = {
  auth: { getUser: async () => ({ data: { user: { id: 'owner-1' } } }) },
  rpc: (name, args) => {
    state.calls.push({ name, args: args === undefined ? undefined : JSON.parse(JSON.stringify(args)) });
    const answer = state.script[name];
    if (answer === undefined) return Promise.reject(new Error(`fake-supabase: unscripted rpc ${name}`));
    return typeof answer === 'function' ? answer(args) : Promise.resolve(answer);
  },
  from: (table) => { throw new Error(`fake-supabase: unexpected table ${table}`); },
};

// `./media` resolves here too: api.ts reads only this constant from it, and the real module is a
// React Native component file that cannot load in node.
const MEDIA_BUCKET = 'media';

module.exports = { supabase, MEDIA_BUCKET, __fake: state };
