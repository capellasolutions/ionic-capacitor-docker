FROM ubuntu:26.04
LABEL org.opencontainers.image.authors="Al-Mothafar Al-Hasan"
LABEL org.opencontainers.image.title="ionic-capacitor-app-builder"
LABEL org.opencontainers.image.description="Toolchain image for building Ionic/Capacitor Android apps (and preparing iOS)."

# -----------------------------------------------------------------------------
# General environment variables
# -----------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive

# A Capacitor android/ project ships its own Gradle wrapper, so the build runs ./gradlew
# and the wrapper downloads the version pinned in the generated project. We still install a
# system Gradle below (its distribution cache warms the wrapper download) and pin the
# version here so it can move via --build-arg.
ARG GRADLE_VERSION
ENV GRADLE_VERSION=${GRADLE_VERSION:-8.14.5}


# -----------------------------------------------------------------------------
# Install system basics
# -----------------------------------------------------------------------------
RUN \
  apt-get update -qqy && \
  apt-get install -qqy --no-install-recommends \
          apt-transport-https \
          ca-certificates \
          software-properties-common \
          gnupg \
          python3 \
          make \
          g++ \
          curl \
          expect \
          zip \
          unzip \
          libsass-dev \
          git \
          rsync \
          sudo


# -----------------------------------------------------------------------------
# Install Java
#
# Capacitor 8's Android template uses the Android Gradle Plugin 8.x, which runs on JDK 21
# (with Gradle 8.x) — the newest LTS that works here. JDK 25 would need AGP 9 / Gradle 9.1+.
# Kept as an ARG so it can move.
# -----------------------------------------------------------------------------

ARG JAVA_VERSION
ENV JAVA_VERSION=${JAVA_VERSION:-21}

ENV JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64}

RUN apt-get update -qqy && \
  apt-get install -qqy --no-install-recommends openjdk-${JAVA_VERSION}-jdk


# -----------------------------------------------------------------------------
# Install Android / Android SDK / Android SDK elements
# -----------------------------------------------------------------------------

ENV ANDROID_SDK_ROOT=/opt/android-sdk-linux
# ANDROID_HOME is the modern name; keep it pointing at the same path for tooling that expects it.
ENV ANDROID_HOME=${ANDROID_SDK_ROOT}
ENV PATH=${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/latest:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:/opt/tools

RUN \
  echo ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT} >> /etc/environment && \
  dpkg --add-architecture i386 && \
  apt-get update -qqy && \
  apt-get install -qqy --no-install-recommends \
          libc6-i386 \
          lib32stdc++6 \
          lib32gcc-s1 \
          lib32ncurses6 \
          lib32z1

# Check https://capacitorjs.com/docs/android first, and keep @capacitor/android in
# package.json current. The generated android/ project's compileSdk/targetSdk should match
# ANDROID_PLATFORMS_VERSION. Capacitor 8 compiles against SDK Platform 36, but its Android
# Gradle Plugin pins Build Tools 35.0.0 (not 36) — that's the version to install, otherwise
# Gradle tries to auto-download it and fails on the read-only SDK dir.
ARG ANDROID_PLATFORMS_VERSION
ENV ANDROID_PLATFORMS_VERSION=${ANDROID_PLATFORMS_VERSION:-36}

ARG ANDROID_SDK_TOOLS_VERSION
ENV ANDROID_SDK_TOOLS_LINK=https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS_VERSION:-14742923}_latest.zip

ARG ANDROID_BUILD_TOOLS_VERSION
ENV ANDROID_BUILD_TOOLS_VERSION=${ANDROID_BUILD_TOOLS_VERSION:-35.0.0}

RUN \
  mkdir -p /root/.android && touch /root/.android/repositories.cfg  && \
  cd /opt && \
  curl -SLo sdk-tools-linux.zip ${ANDROID_SDK_TOOLS_LINK} && \
  unzip sdk-tools-linux.zip -d ${ANDROID_SDK_ROOT}/ && mkdir -p ${ANDROID_SDK_ROOT}/latest && \
  mv ${ANDROID_SDK_ROOT}/cmdline-tools/* ${ANDROID_SDK_ROOT}/latest && mv ${ANDROID_SDK_ROOT}/latest ${ANDROID_SDK_ROOT}/cmdline-tools/latest &&  \
  rm -f sdk-tools-linux.zip && chmod 775 ${ANDROID_SDK_ROOT} -R

RUN  yes | sdkmanager --update && yes | sdkmanager --licenses && \
  sdkmanager "platform-tools" && \
  sdkmanager "platforms;android-${ANDROID_PLATFORMS_VERSION}" && \
  sdkmanager "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" && \
  # Make the whole SDK world-writable so the non-root build user's Gradle can auto-install
  # any extra component a future AGP asks for (otherwise it fails on the read-only dir).
  chmod -R a+rwX ${ANDROID_SDK_ROOT}

# -----------------------------------------------------------------------------
# Install Gradle
#
# The generated Capacitor android/ project runs through its own ./gradlew wrapper, so a
# system Gradle is not strictly required. We still install the official distribution (and
# put it on PATH) so its cache warms the wrapper download and so `gradle` is available for
# any ad-hoc use. Ubuntu's apt Gradle is far too old for the Android Gradle Plugin.
# -----------------------------------------------------------------------------
RUN curl -SLo /tmp/gradle.zip https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip && \
  unzip -q /tmp/gradle.zip -d /opt && \
  rm -f /tmp/gradle.zip && \
  ln -s /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle && \
  gradle --version

# -----------------------------------------------------------------------------
# Install Node & npm via NodeSource
#
# The old manual tarball + GPG verification relied on the SKS keyserver pool, which
# was permanently shut down in 2021 and made this image impossible to build. NodeSource
# ships a maintained apt repo with its own signing key.
# -----------------------------------------------------------------------------

ARG PACKAGE_MANAGER
ENV PACKAGE_MANAGER=${PACKAGE_MANAGER:-npm}

ARG NODE_VERSION
ENV NODE_VERSION=${NODE_VERSION:-24}

ENV NPM_CONFIG_LOGLEVEL=info

RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -qqy --no-install-recommends nodejs && \
    node --version && \
    npm --version

# Yarn and pnpm are installed on demand with npm (which always ships with Node). We avoid
# Corepack on purpose: it is being unbundled from Node (25+), so relying on it would break
# the moment NODE_VERSION moves forward. Only the SELECTED manager is installed — npm builds
# (the default) add nothing extra, keeping the image smaller. Pick one per build via
# PACKAGE_MANAGER. This RUN executes as root, so the global install lands on the shared PATH
# and stays usable by the non-root build user created later.
ARG YARN_VERSION
ENV YARN_VERSION=${YARN_VERSION:-stable}

ARG PNPM_VERSION
ENV PNPM_VERSION=${PNPM_VERSION:-latest}

RUN if [ "${PACKAGE_MANAGER}" = "pnpm" ]; then \
      npm install -g pnpm@${PNPM_VERSION} && pnpm --version; \
    elif [ "${PACKAGE_MANAGER}" = "yarn" ]; then \
      npm install -g yarn@${YARN_VERSION} && yarn --version; \
    else \
      echo "Using npm bundled with Node; no extra package manager installed."; \
    fi

# -----------------------------------------------------------------------------
# Install Ruby + CocoaPods (used when preparing the iOS project)
# -----------------------------------------------------------------------------

RUN apt-get update && apt-get install -qqy --no-install-recommends ruby-full && \
    gem install bigdecimal etc && gem install cocoapods

# -----------------------------------------------------------------------------
# Clean up
# -----------------------------------------------------------------------------
RUN \
  apt-get clean && \
  apt-get autoclean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*


# -----------------------------------------------------------------------------
# Create a non-root docker user to run this container
# -----------------------------------------------------------------------------

ARG USER
ENV USER=${USER:-ionic}

RUN \
  echo "create the build user" && \
  useradd --user-group --create-home --shell /bin/bash ${USER} && \
  echo "${USER}:${USER}" | chpasswd && \
  adduser ${USER} sudo && \
  \
  echo "create app/build dirs owned by the build user" && \
  mkdir /app && chown ${USER}:${USER} /app && chmod 775 /app && \
  mkdir /build && chown ${USER}:${USER} /build && chmod 775 /build && \
  \
  echo "image.config is written below as the build user" && \
  touch /image.config && chown ${USER}:${USER} /image.config && chmod 664 /image.config && \
  \
  echo "this is necessary for ionic commands to run" && \
  mkdir /home/${USER}/.ionic && chown ${USER}:${USER} /home/${USER}/.ionic && chmod 775 /home/${USER}/.ionic && \
  \
  echo "give the build user its own Android config dir (the SDK itself is world-readable via chmod 775 above)" && \
  mkdir -p /home/${USER}/.android && touch /home/${USER}/.android/repositories.cfg && \
  chown -R ${USER}:${USER} /home/${USER}/.android


# -----------------------------------------------------------------------------
# Switch the user of this image only now, because previous commands need to be
# run as root
# -----------------------------------------------------------------------------
USER ${USER}

ENV NPM_CONFIG_PREFIX=/home/${USER}/.npm-global
ENV PATH="/home/${USER}/.npm-global/bin:${PATH}"

# Give Gradle an explicit, build-user-owned home so ./gradlew can cache the wrapper
# distribution and dependencies (defaults to ~/.gradle, which is fine here, but pinning it
# documents the location and keeps it writable for the non-root user).
ENV GRADLE_USER_HOME=/home/${USER}/.gradle

# -----------------------------------------------------------------------------
# Install Global node modules
# -----------------------------------------------------------------------------

ARG IONIC_CLI_VERSION
ENV IONIC_CLI_VERSION=${IONIC_CLI_VERSION:-7.2.1}

# Capacitor's CLI (@capacitor/cli) is a project devDependency, run via `npx cap` /
# `pnpm exec cap`, so nothing Capacitor-specific is installed globally. We keep the Angular
# CLI for `ng`, and the Ionic CLI optionally (its Capacitor integration lives in
# ionic.config.json). Installed with npm because these globals are just executables on PATH;
# PACKAGE_MANAGER only selects how the *app's* deps are installed (in the app Dockerfile).
RUN npm install -g @angular/cli && \
    if [ -n "${IONIC_CLI_VERSION}" ]; then npm install -g @ionic/cli@"${IONIC_CLI_VERSION}"; fi && \
    npm cache clean --force


# -----------------------------------------------------------------------------
# Create the image.config file for the container to check the build
# configuration of this container later on
# -----------------------------------------------------------------------------
RUN { \
  echo "USER: ${USER}"; \
  echo "JAVA_VERSION: ${JAVA_VERSION}"; \
  echo "GRADLE_VERSION: ${GRADLE_VERSION}"; \
  echo "ANDROID_PLATFORMS_VERSION: ${ANDROID_PLATFORMS_VERSION}"; \
  echo "ANDROID_BUILD_TOOLS_VERSION: ${ANDROID_BUILD_TOOLS_VERSION}"; \
  echo "NODE_VERSION: ${NODE_VERSION}"; \
  echo "PACKAGE_MANAGER: ${PACKAGE_MANAGER}"; \
  echo "IONIC_CLI_VERSION: ${IONIC_CLI_VERSION}"; \
  echo "CAPACITOR_CLI: project-local (@capacitor/cli devDependency)"; \
} >> /image.config && \
cat /image.config


# -----------------------------------------------------------------------------
# Just in case you are installing from private git repositories, enable git
# credentials
# -----------------------------------------------------------------------------
RUN git config --global credential.helper store

# -----------------------------------------------------------------------------
# WORKDIR is the generic /app folder. All volume mounts of the actual project
# code need to be put into /app.
# -----------------------------------------------------------------------------
WORKDIR /app
