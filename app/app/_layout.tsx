import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
// Side-effect import: registers the background location task before React renders, which is
// the only point at which the OS can be told where to deliver locations while the app is
// backgrounded. Guarded internally — a build without expo-task-manager registers nothing.
import '../src/lib/bgTrack';
import { AuthProvider } from '../src/auth-context';
import { ThemeProvider } from '../src/theme-context';
import { colors } from '../src/theme';

export default function RootLayout() {
  return (
    <AuthProvider>
    <ThemeProvider>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.cream },
          animation: 'fade', // quick crossfade — no slide, frees the edge for the slide-to-book gesture
          animationDuration: 70, // ~5x faster than default (~350ms)
          gestureEnabled: false, // back-swipe conflicted with the slider
        }}
      />
    </ThemeProvider>
    </AuthProvider>
  );
}
