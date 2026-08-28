const { safeInlineScriptString } = require('./inline-script.build.cjs');

let pass = 0;
let fail = 0;
const t = (name, fn) => {
  try { fn(); console.log(`PASS ${name}`); pass++; }
  catch (error) { console.log(`FAIL ${name} — ${error.message}`); fail++; }
};
const ok = (condition, message) => { if (!condition) throw new Error(message); };

t('ordinary strings round-trip exactly', () => {
  const value = 'client_key-123 "quoted" \\ slash';
  ok(JSON.parse(safeInlineScriptString(value)) === value, 'round trip changed the value');
});

t('a script-closing payload cannot cross the HTML parser boundary', () => {
  const value = '</script><script>throw new Error("injected")</script>';
  const encoded = safeInlineScriptString(value);
  ok(!encoded.includes('<'), `literal angle bracket survived: ${encoded}`);
  ok(encoded.includes('\\u003c/script>'), 'script close was not neutralized');
  ok(JSON.parse(encoded) === value, 'neutralization changed the JavaScript value');
});

t('JavaScript line separators are escaped but preserved', () => {
  const value = `before\u2028middle\u2029after`;
  const encoded = safeInlineScriptString(value);
  ok(!encoded.includes('\u2028') && !encoded.includes('\u2029'), 'literal line separator survived');
  ok(JSON.parse(encoded) === value, 'line separator round trip changed the value');
});

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
