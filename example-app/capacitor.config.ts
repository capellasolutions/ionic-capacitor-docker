import type { CapacitorConfig } from '@capacitor/cli';

// Capacitor replaces Cordova's config.xml. `appId` becomes the Android namespace /
// applicationId and the iOS bundle id, so it must be set BEFORE `npx cap add` runs — the
// Docker build injects PACKAGE_ID here (and overrides appName for non-prod) before adding
// the native platforms. `webDir` points at the flat Angular output so `cap sync` copies it
// into the native projects.
const config: CapacitorConfig = {
  appId: 'com.example.app',
  appName: 'My App',
  webDir: 'www',
};

export default config;
