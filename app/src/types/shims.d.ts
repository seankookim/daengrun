// Ambient shim so typecheck passes before `npx expo install @react-native-async-storage/async-storage`.
// Real types take over once the package is installed (this stays harmless).
declare module '@react-native-async-storage/async-storage';
declare module 'expo-web-browser';
