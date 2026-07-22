import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { ThemeProvider } from '../src/theme-context';
import { colors } from '../src/theme';

export default function RootLayout() {
  return (
    <ThemeProvider>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.cream },
          animation: 'fade', // quick crossfade — no slide, frees the edge for the slide-to-book gesture
          gestureEnabled: false, // back-swipe conflicted with the slider
        }}
      />
    </ThemeProvider>
  );
}
