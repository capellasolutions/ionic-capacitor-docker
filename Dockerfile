ARG PLATFORM=android
FROM app-builder AS prepare-build

ARG USER
ARG ENV_NAME
ARG PACKAGE_ID
ARG VERSION
ARG PACKAGE_TYPE

# If arguments not specified then set a value
ENV USER=${USER:-ionic}
ENV ENV_NAME=${ENV_NAME:-dev}
ENV PACKAGE_ID=${PACKAGE_ID:-"com.example.com"}
ENV VERSION=${VERSION:-"MISSING"}
# Android artifact type: "bundle" (.aab for Google Play) or "apk" (installable on a device).
# Selects the Gradle task (bundleRelease vs assembleRelease) in scripts/build-capacitor.sh.
ENV PACKAGE_TYPE=${PACKAGE_TYPE:-bundle}

RUN echo "------------------------------------------"&& \
    echo "| BUILDING MOBILE APPLICATION             "&& \
    echo "| Environment: ${ENV_NAME}                "&& \
    echo "| Package: ${PACKAGE_ID}                  "&& \
    echo "| Version: ${VERSION}                     "&& \
    echo "------------------------------------------"

# Add package.json, lockfiles and the package-manager config first (before the rest of the project) so the
# dependency-install layer is cached and only re-runs when dependencies change. pnpm-workspace.yaml / .npmrc must be
# here too: pnpm 11 reads allowBuilds and nodeLinker (hoisted) from them, and without those the install leaves build
# scripts ignored (non-zero exit) and an un-hoisted node_modules that breaks Capacitor plugin discovery. The trailing *
# makes each optional, so npm/yarn projects without them still build.
# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#use-multi-stage-builds
ADD --chown=ionic package.json package-lock.json* yarn.lock* pnpm-lock.yaml* pnpm-workspace.yaml* .npmrc* ./

RUN sed -i "s/\"name\":.*/\"name\": \"${PACKAGE_ID}\",/g" ./package.json
# Uncomment if you want the version from Argument
#RUN sed -i "s/\"version\":.*/\"version\": \"${VERSION}\",/g" ./package.json

# PACKAGE_MANAGER is inherited from the app-builder image (selected there via --build-arg PACKAGE_MANAGER). yarn/pnpm
# use a clean, reproducible install when their lockfile is present; npm falls back to `install` if there's no
# package-lock.json yet. (This demo defaults to pnpm; pnpm-workspace.yaml's nodeLinker: hoisted makes pnpm's
# node_modules flat enough for Capacitor to discover plugin android/ ios/ folders during `cap sync`.)
RUN \
  if [ "${PACKAGE_MANAGER}" = "yarn" ]; then \
    yarn install --frozen-lockfile; \
  elif [ "${PACKAGE_MANAGER}" = "pnpm" ]; then \
    pnpm install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then \
    npm ci; \
  else \
    npm install; \
  fi

ADD --chown=ionic  . .

# Capacitor replaces Cordova's config.xml: inject the bundle id into capacitor.config.ts. This MUST happen before
# `cap add` (in the build stages) because appId becomes the Android namespace/applicationId and the iOS bundle id when
# the native project is generated.
RUN sed -i "s/appId: '[^']*'/appId: '${PACKAGE_ID}'/" ./capacitor.config.ts
# Uncomment if you want the version from Argument (Capacitor reads it from package.json)
#RUN sed -i "s/\"version\":.*/\"version\": \"${VERSION}\",/g" ./package.json

USER ${USER}
RUN if [ "$ENV_NAME" = "prod" ]; \
    then \
      echo "Building Prod (No changes for environment files)"; \
    else \
      cp /app/src/environments/environment.${ENV_NAME}.ts /app/src/environments/environment.prod.ts; \
      sed -i "s/appName: '[^']*'/appName: 'My App Test'/" ./capacitor.config.ts; \
    fi

RUN cp /app/google-services/${ENV_NAME}-google-services.json  google-services.json; \
    cp /app/google-services/${ENV_NAME}-GoogleService-Info.plist  GoogleService-Info.plist;

FROM prepare-build AS build-android
RUN echo ">>> Building Android App <<<"
ENV BUILD_RESULT="Building Android App is done"

# Build the Angular web app, generate the native Android project with Capacitor, copy the web assets + plugins in
# (cap sync), then build a signed release with Gradle. See scripts/build-capacitor.sh for the full flow. Run via bash
# so a missing +x bit on Windows checkouts doesn't matter.
RUN bash ./scripts/build-capacitor.sh android

FROM prepare-build AS build-ios
RUN echo ">>> Building iOS App <<<"
ENV BUILD_RESULT="Building iOS App is done"

# iOS cannot be compiled on Linux; we only prepare the Xcode project (cap add + cap sync, which runs pod install) for a
# macOS runner to finish.
RUN bash ./scripts/build-capacitor.sh ios

FROM prepare-build AS build-all
RUN echo ">>> Building Android and then iOS Apps <<<"
ENV BUILD_RESULT="Building Android and then iOS Apps is done"

RUN bash ./scripts/build-capacitor.sh android
RUN bash ./scripts/build-capacitor.sh ios

FROM build-${PLATFORM} AS final-build
RUN echo ">>> Yaay!! ${BUILD_RESULT} <<<"
