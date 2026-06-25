#!/usr/bin/env bash
#
# Build (Android) or prepare (iOS) a Capacitor native platform inside the Docker image.
# Called by the per-app Dockerfile build stages. Not meant to be run by hand.
#
# Usage: build-capacitor.sh <android|ios>
#
# Reads from the environment (set by the Dockerfile / app-builder image):
#   PACKAGE_MANAGER  npm | yarn | pnpm   (how to run scripts and the Capacitor CLI)
#   PACKAGE_TYPE     bundle | apk        (Android artifact: .aab for Play, or installable .apk)

set -euo pipefail

platform="${1:?usage: build-capacitor.sh <android|ios>}"
PM="${PACKAGE_MANAGER:-npm}"
PACKAGE_TYPE="${PACKAGE_TYPE:-bundle}"

# Resolve how to run the build script and the Capacitor CLIs for the selected package
# manager. The Capacitor CLI (@capacitor/cli) and @capacitor/assets are project-local
# devDependencies, so they run through the package manager's executor, not a global install.
# Note: pnpm and yarn forward extra args straight to the script, so a literal `--` would
# reach `ng` as a duplicate separator and fail schema validation — only npm needs the `--`.
case "$PM" in
  pnpm) build_web="pnpm run build";    cap="pnpm exec cap";  assets="pnpm exec capacitor-assets" ;;
  yarn) build_web="yarn run build";    cap="yarn cap";       assets="yarn capacitor-assets" ;;
  *)    build_web="npm run build --";  cap="npx cap";        assets="npx capacitor-assets" ;;
esac

# Start from a clean slate so `cap add` regenerates the native project deterministically
# (appId in capacitor.config.ts — already injected in prepare-build — becomes the Android
# namespace/applicationId and the iOS bundle id).
rm -rf ./www ./android ./ios

echo ">>> Building Angular web app (www/) <<<"
$build_web --configuration=production

echo ">>> Adding Capacitor $platform project <<<"
$cap add "$platform"

# Icons & splash from assets/. Non-fatal: a missing/odd asset must not fail the build —
# Capacitor falls back to its default launcher icons.
$assets generate --"$platform" || echo "Asset generation skipped for $platform."

if [ "$platform" = "android" ]; then
  # Firebase config: inert unless the Google Services Gradle plugin is wired in, but copied
  # into the native project for parity with the Cordova template.
  [ -f google-services.json ] && cp google-services.json android/app/google-services.json || true

  $cap sync android

  # Sign the release with Gradle's injected signing properties so the generated android/
  # project needs no hand-edits to build.gradle. Values come from keystore.properties.
  # shellcheck disable=SC1091
  . ./keystore.properties
  store_abs="$(pwd)/${storeFile}"
  task=$([ "$PACKAGE_TYPE" = "apk" ] && echo assembleRelease || echo bundleRelease)

  echo ">>> Gradle :app:$task (signed release) <<<"
  ( cd android && ./gradlew ":app:${task}" \
      -Pandroid.injected.signing.store.file="${store_abs}" \
      -Pandroid.injected.signing.store.password="${storePassword}" \
      -Pandroid.injected.signing.key.alias="${keyAlias}" \
      -Pandroid.injected.signing.key.password="${keyPassword}" )

  mkdir -p ./output/android && mv ./android/* ./output/android
  echo ">>> Android artifact(s) in ./output/android <<<"
else
  # iOS cannot be compiled on Linux — we only prepare the Xcode project for a macOS runner.
  # `cap sync ios` runs `pod install` (CocoaPods is installed in the toolchain image).
  [ -f GoogleService-Info.plist ] && cp GoogleService-Info.plist ios/App/App/GoogleService-Info.plist || true

  $cap sync ios

  mkdir -p ./output/ios && mv ./ios/* ./output/ios
  echo ">>> iOS Xcode project in ./output/ios (finish the build on macOS) <<<"
fi
