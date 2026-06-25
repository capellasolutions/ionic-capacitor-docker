# Ionic Capacitor App Builder
So this is a project that should help you produce an Android project and build, and/or an Xcode project for iOS, using Docker only. It is basically a set of command lines that make it easier for you to produce the final app build with **Capacitor**.

These files can be placed inside an Ionic project to use.

> Looking for the Cordova flavour? See the sibling project [ionic-cordova-docker](https://github.com/capellasolutions/ionic-cordova-docker). This repo is the Capacitor port of it and defaults to **pnpm** instead of npm.

## Repository layout
* `app-builder.Dockerfile` — builds the heavy **toolchain base image** (Ubuntu + JDK + Android SDK + Node + Angular/Ionic CLIs). Build it once and reuse it; that's why it is a separate image. Capacitor's own CLI is a project devDependency, so it is **not** installed globally here.
* `Dockerfile` — `FROM app-builder`, copies your app in, builds the Angular web app and then generates + builds the native project with Capacitor. This is the per-app build.
* `scripts/build-capacitor.sh` — the build helper the `Dockerfile` runs inside the image: it builds the web app, runs `cap add` / `cap sync`, and produces a signed Android release with Gradle (or prepares the iOS Xcode project).
* `build-mobile.sh` — convenience wrapper that builds both images and copies the artifact out.
* `example-app/` — a small **Angular 22 + Ionic v9 (zoneless) + Capacitor** demo you can **clone and build immediately** to test the pipeline end-to-end. It carries its **own copies** of the template files above so it is self-contained (Docker can't reach files outside its build context, so the copies are required, not accidental). The root files are the source of truth; the `example-app` copies of `Dockerfile`, `app-builder.Dockerfile` and `scripts/build-capacitor.sh` are kept byte-for-byte identical (CI enforces this). `example-app/build-mobile.sh` is intentionally slightly different (it uses `version=0.0.0` and a self-contained header comment).

To try it out right away:
```shell
cd example-app
./build-mobile.sh
```

## The demo app (`example-app`)

The bundled demo is a small **Angular 22 + Ionic v9 + Capacitor** app that runs **fully zoneless** (no `zone.js`). It exercises the Docker pipeline end-to-end and doubles as an up-to-date reference for the modern toolchain:

* **Angular 22** with the esbuild `@angular/build:application` builder, standalone components and signals — zoneless by default (`provideZonelessChangeDetection()`), no `zone.js` in the bundle.
* **Ionic** pinned to a **v9 pre-release dev build** of `@ionic/angular` (`8.8.12-dev…`). v9 adds Angular 21/22 support and zoneless-by-default. Until it ships as stable (~Q3 2026) the pin is exact. **When `@ionic/angular@9` is released, bump the pin to `^9` and delete this note.**
* **Capacitor 8** (`@capacitor/core`, `@capacitor/android`, `@capacitor/ios`) with the `@capacitor/cli` and `@capacitor/assets` as devDependencies, plus the `@capacitor/{status-bar,keyboard,device,splash-screen}` plugins.
* **pnpm** is the default package manager (the Cordova sibling defaults to npm — this is the "different way"). An `.npmrc` sets `node-linker=hoisted` so pnpm's `node_modules` is flat enough for Capacitor to discover each plugin's native `android/` and `ios/` folders during `cap sync`.
* **TypeScript 6**, **Vitest** (jsdom) for unit tests, **angular-eslint** for linting.
* The toolchain base image builds on **Ubuntu 26.04**.

`pnpm run build` emits a flat `www/` (configured as `webDir` in `capacitor.config.ts`, so `cap sync` copies it into the native projects), and the production configuration swaps `src/environments/environment.ts` for `environment.prod.ts` — the Dockerfile first copies `environment.<ENV_NAME>.ts` over `environment.prod.ts` so one production build can target dev or prod.

### How the native build works
Capacitor replaces Cordova's `config.xml` with `capacitor.config.ts`. Because the native `android/` and `ios/` projects are **generated fresh inside Docker** on every build (they are not committed), the Dockerfile injects `PACKAGE_ID` into `appId` *before* `cap add` runs — `appId` becomes the Android namespace/applicationId and the iOS bundle id. The Android release is signed with Gradle's [injected signing properties](https://developer.android.com/build/building-cmdline#sign_cmdline) (`-Pandroid.injected.signing.*`) read from `keystore.properties`, so the generated project needs no hand-edits.

## Usage
**First** you need to build (and optionally push) the builder image. It is separated so you don't waste time rebuilding it every time you build a new app.
Use the following commands:
```shell
docker build . -f ./app-builder.Dockerfile -t app-builder
docker push app-builder
```
Optionally, you can use `--build-arg` like

```shell
docker build . -f ./app-builder.Dockerfile \
  --build-arg PACKAGE_MANAGER=pnpm \
  --build-arg ANDROID_PLATFORMS_VERSION=36 \
  -t app-builder
```

*Note: You can change `app-builder` with whatever name you like, but you need to change it as well inside `Dockerfile` (the `FROM app-builder` line).*

Docker builder arguments (defaults shown):
* `GRADLE_VERSION`: Gradle installed in the image. Default `8.14.5`. The generated Capacitor `android/` project runs its own `./gradlew` wrapper; the system Gradle mainly warms the wrapper's distribution cache (stay on Gradle 8.x for the AGP 8.x plugin).
* `JAVA_VERSION`: JDK version. Default `21` (LTS). Capacitor 8's Android template uses AGP 8.x, which runs on JDK 21 with Gradle 8.x; JDK 25 would need AGP 9 / Gradle 9.1+.
* `ANDROID_PLATFORMS_VERSION`: Android platform (compile/target SDK) to install. Default `36`.
* `ANDROID_BUILD_TOOLS_VERSION`: Android build-tools version. Default `35.0.0` (the version Capacitor 8's Android Gradle Plugin pins, even though it compiles against platform 36).
* `ANDROID_SDK_TOOLS_VERSION`: Android command-line tools build number. Default `14742923`.
* `PACKAGE_MANAGER`: `npm`, `yarn`, or `pnpm`. Default `npm` for the image, but the demo's `build-mobile.sh` passes `pnpm`. Only the **selected** manager is installed (npm ships with Node; yarn/pnpm are added on demand with `npm install -g`). This avoids Corepack, which is being unbundled from Node 25+. It also selects how `Dockerfile` installs *your app's* dependencies, so commit the matching lockfile (`package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`).
* `NODE_VERSION`: Node.js major (installed via NodeSource). Default `24` (current LTS).
* `YARN_VERSION`: Yarn version (installed only when `PACKAGE_MANAGER=yarn`). Default `stable`.
* `PNPM_VERSION`: pnpm version (installed only when `PACKAGE_MANAGER=pnpm`). Default `latest`.
* `USER`: helpful for permissions. Default `ionic`.
* `IONIC_CLI_VERSION`: Ionic CLI version (optional; Capacitor itself is driven via `npx cap` / `pnpm exec cap`). Default `7.2.1`.

> Check the [Capacitor Android docs](https://capacitorjs.com/docs/android) first, keep `@capacitor/android` in `package.json` current, and make sure the generated project's compile/target SDK matches `ANDROID_PLATFORMS_VERSION`.

**Then**, you can use your image to build the app:
```shell
docker build . \
  --build-arg ENV_NAME="${ENV_NAME}" \
  --build-arg PACKAGE_ID="${PACKAGE_ID}" \
  --build-arg PACKAGE_MANAGER=pnpm \
  --build-arg PLATFORM=${platform} \
  --build-arg VERSION="${version}" \
  -f ./Dockerfile \
  -t app-build
```

Arguments:
* `PACKAGE_ID`: the bundle id for your app — injected into `appId` in `capacitor.config.ts` before the native project is generated.
* `ENV_NAME`: `prod` or `dev`, depending on what your environment files are called inside the `environments` folder.
* `PLATFORM`: `ios` or `android`, or both using `all`.
* `VERSION`: optional override for the app version (read from `package.json`). See `Dockerfile` and uncomment the line that sets it.
* `PACKAGE_TYPE`: Android artifact type — `bundle` (`.aab` for Google Play, default) or `apk` (installable on a device). Selects the Gradle task (`bundleRelease` vs `assembleRelease`).

**Finally**, to get the build out of that image:
For the Android build:
```shell
docker run --user root:root --privileged=true -v ./build-output:/app/mount:Z --rm --entrypoint cp app-build -r ./output/android /app/mount
```

For the iOS build (note: iOS can only be *prepared* on Linux, never compiled — finish the build on macOS):
```shell
docker run --user root:root --privileged=true -v ./build-output:/app/mount:Z --rm --entrypoint cp app-build -r ./output/ios /app/mount
cd ./build-output/ios/App && pod repo update && pod install
```

There is a `build-mobile.sh` file if you want to run all these steps from a shell (you can comment out the first part later).

## Verifying and using the Android build
The Android build is copied to `build-output/android`. By default it produces a **signed Android App Bundle** (the file you upload to the Google Play Console):
```
build-output/android/app/build/outputs/bundle/release/app-release.aab
```

Verify the artifact is signed:
```shell
jarsigner -verify build-output/android/app/build/outputs/bundle/release/app-release.aab
# -> "jar verified."
```

An `.aab` cannot be installed on a device directly. To get an **installable APK** (e.g. for sideload testing), build with `PACKAGE_TYPE=apk`:
```shell
PACKAGE_TYPE=apk ./build-mobile.sh android
```
The APK then lands under `build-output/android/app/build/outputs/apk/release/`. Alternatively, generate APKs from an existing bundle with [bundletool](https://developer.android.com/tools/bundletool):
```shell
bundletool build-apks --mode=universal \
  --bundle=app-release.aab --output=app.apks \
  --ks=keys/android.jks --ks-key-alias=alias_name
```

> ⚠️ **Signing key:** the demo signs with the committed `keys/android.jks` (passwords `Changeit` in `keystore.properties`). For a real app, generate your **own** keystore, keep it out of source control, and supply the passwords via secrets/environment — an app signed with the demo key can never be updated on Play by you.

## Continuous integration
`.github/workflows/build.yml` runs on push/PR and:
1. checks the `example-app` template copies (`Dockerfile`, `app-builder.Dockerfile`, `scripts/build-capacitor.sh`) haven't drifted from the root files,
2. lints, builds and unit-tests the demo app with pnpm, and
3. builds the toolchain image and the demo Android app end-to-end.

`.github/dependabot.yml` keeps the demo's dependencies (it reads `pnpm-lock.yaml`), the Docker base images, and the GitHub Actions up to date.

Good Luck 🧡

[Al-Mothafar Al-Hasan](https://github.com/almothafar) from
[Capella Solutions](https://www.capellasolutions.com/)
