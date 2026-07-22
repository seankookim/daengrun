import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
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
