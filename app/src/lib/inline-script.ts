/**
 * Serialize a string for a JavaScript expression embedded in an HTML <script>.
 *
 * JSON quoting alone is not enough: a literal "</script>" closes the HTML
 * element before the JavaScript parser sees the quoted value. Escaping "<"
 * removes that parser boundary while preserving the original string value.
 */
export function safeInlineScriptString(value: string): string {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}
