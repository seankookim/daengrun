// PaperSheet — the house sheet presentation. [HIG N8 · components/sheets]
//
// Before this, every sheet in the owner flow was `<Modal transparent animationType="slide">`
// with a hand-drawn 44×5 grabber and a backdrop Pressable. Three things were wrong with that
// shape and only one of them is cosmetic:
//   · no swipe-to-dismiss — the single gesture iOS users try first on a sheet did nothing;
//   · the grabber was a FAKE AFFORDANCE — HIG reserves it for a RESIZABLE sheet, and none of
//     ours resize, so the bar promised a drag the sheet could not perform;
//   · no header order — the dismiss control was wherever the body happened to put it, or was
//     only the backdrop, which VoiceOver reads as one unlabelled region.
// `presentationStyle="pageSheet"` is the one correct sheet this repo already had
// (`toss-sheet-impl.tsx:70`); this is that, plus the header HIG asks for: dismiss on the
// LEADING edge, title centred. The system draws the sheet's corner radius, its dimmed backdrop
// and its drag — so none of them are ours to fake.
//
// ⚠ WHAT THE CALLER LOSES, stated plainly rather than discovered on a device: tap-outside-to-
// dismiss. iOS does not dismiss a pageSheet on a backdrop tap. The two exits are the leading
// 닫기 button and the swipe down, and BOTH land on the same `onClose` the old backdrop and
// `onRequestClose` already used — so no handler changed, only how many ways reach it.
//
// ⚠ There is no `onDone` prop and that is deliberate, not an omission. HIG puts Done on the
// trailing edge *when the sheet has a commit action*; neither sheet converted in this slice has
// one (the slot picker commits on the chip tap and closes itself; the booking sheet's commit is
// a destructive button that carries the server's fee quote in its own label and must stay in the
// body). Writing the arm anyway would ship a branch with no caller and no way to test it. The
// trailing slot is reserved as a spacer — the next sheet that genuinely commits adds the prop.
//
// ⚠ SafeAreaView from react-native-safe-area-context, NOT `useSafeAreaInsets()`: the hook reads
// the ROOT window's insets through context, and a pageSheet does not start at the root window's
// top edge, so the hook over-pads a sheet by a whole status bar. The native view measures its
// own frame instead. The core RN SafeAreaView is deprecated in 0.86 (see toss-sheet-impl.tsx:32).
import { ReactNode } from 'react';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { paper } from '../theme';

export type PaperSheetProps = {
  visible: boolean;
  /** Centred header title — says which task the sheet is, per HIG N6. */
  title: string;
  /** The one dismiss path: the leading button, the swipe down, and the Android back key. */
  onClose: () => void;
  children: ReactNode;
};

export function PaperSheet({ visible, title, onClose, children }: PaperSheetProps) {
  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={s.root}>
        <View style={s.header}>
          <Pressable
            onPress={onClose}
            style={s.edge}
            hitSlop={10}
            accessibilityRole="button"
            accessibilityLabel="닫기"
          >
            <Text style={s.dismiss}>닫기</Text>
          </Pressable>
          <Text numberOfLines={1} style={s.title}>{title}</Text>
          {/* trailing edge — HIG's Done side, a spacer today so the title sits optically centred */}
          <View style={s.edge} pointerEvents="none" />
        </View>
        <View style={s.body}>{children}</View>
      </SafeAreaView>
    </Modal>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    minHeight: 52,
    paddingHorizontal: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: paper.line,
  },
  // 64 wide / 44 tall on both sides: the tap target floor, and equal widths are what centre the title
  edge: { width: 64, minHeight: 44, justifyContent: 'center' },
  dismiss: { fontSize: 16.5, fontWeight: '700', color: paper.actionInk },
  title: { flex: 1, textAlign: 'center', fontSize: 17, fontWeight: '900', color: paper.ink },
  body: { flex: 1 },
});
