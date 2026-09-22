// JSX factory injected by esbuild (--jsx-factory=__h --jsx-fragment=__f) when the test harness
// bundles OwnerRunActivity.tsx for node. It turns every element into a plain, walkable object so
// the pins can collect the text the banner would draw.
export function __h(type, props, ...children) {
  return { type, props: props || {}, children };
}
export function __f(props, ...children) {
  return { type: 'Fragment', props: props || {}, children };
}
