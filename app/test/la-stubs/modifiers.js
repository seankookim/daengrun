// Test stub for '@expo/ui/swift-ui/modifiers'. Modifiers are styling only — this test asserts
// the WORDS the banner draws, never its colours or padding, so each one records its arguments
// and nothing reads them.
const mk = (name) => (arg) => ({ modifier: name, arg });
module.exports = {
  background: mk('background'),
  border: mk('border'),
  font: mk('font'),
  foregroundStyle: mk('foregroundStyle'),
  padding: mk('padding'),
};
