// Test stub for 'expo-widgets'. The real `createLiveActivity` registers the widget with the
// native module; here it hands the raw function back so the test can CALL it with a payload and
// read the tree it returns. That is the whole point of this harness: the pins execute the real
// widget body rather than matching its source text.
function createLiveActivity(name, fn) {
  return { name, render: fn };
}
module.exports = { createLiveActivity };
