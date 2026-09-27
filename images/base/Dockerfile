# syntax=docker/dockerfile:1
#
# hermes-base: DHI sandbox floor + Hermes Agent + signal-cli (native, arm64).
# Rebuilt only when a pin moves. The kit (../../hermes.dockerfile) layers
# config, persona and skills on top.
#
# linux/arm64 only. Upstream signal-cli ships a native binary for amd64 only,
# and libsignal's jar carries no linux-aarch64 JNI lib, so both are built here.

# Pinned to a main commit: the latest tag (v2026.9.24) still caps Python at <3.14,
# and the DHI sandbox template ships 3.14. Move to a tag once one allows 3.14.
ARG HERMES_REF=ca16be564d0a95f86bd6da44bb41d39cde9db089
ARG SIGNAL_CLI_VERSION=0.14.8
# Must match signal-cli's ./libsignal-version for SIGNAL_CLI_VERSION.
ARG LIBSIGNAL_VERSION=0.102.1

# ---- libsignal JNI (Rust) -------------------------------------------------
FROM dhi.io/rust:1-debian13-dev AS libsignal
ARG LIBSIGNAL_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends git clang libclang-dev cmake make protobuf-compiler libprotobuf-dev \
 && rm -rf /var/lib/apt/lists/*
ADD --keep-git-dir=false https://github.com/signalapp/libsignal.git#v${LIBSIGNAL_VERSION} /src
WORKDIR /src
# Mirrors java/build_jni.sh's desktop flags (ARMv8 AES, tokio metrics).
ENV RUSTFLAGS="--cfg aes_armv8 --cfg tokio_unstable"
RUN cargo build --locked --release -p libsignal-jni \
 && install -D -m 0644 target/release/libsignal_jni.so /out/libsignal_jni_aarch64.so

# ---- signal-cli native image (GraalVM, build stage only) ------------------
FROM container-registry.oracle.com/graalvm/native-image:25 AS signalcli
ARG SIGNAL_CLI_VERSION
ADD --keep-git-dir=false https://github.com/AsamK/signal-cli.git#v${SIGNAL_CLI_VERSION} /src
WORKDIR /src
# libsignal's loader looks for the classpath resource /libsignal_jni_<os.arch>.so
# first; resources.autodetect() bundles it into the native image.
COPY --from=libsignal /out/libsignal_jni_aarch64.so src/main/resources/libsignal_jni_aarch64.so
RUN GRAALVM_HOME="$JAVA_HOME" ./gradlew nativeCompile --no-daemon \
      -Porg.gradle.java.installations.auto-download=false \
 && install -D -m 0755 build/native/nativeCompile/signal-cli /out/signal-cli

# ---- runtime ----------------------------------------------------------------
# sbx-templates:shell is DHI and already carries the sandbox floor: user agent
# (1000), bash, git, gh, uv, rg, jq, curl, CA store, Python 3.14, BASH_ENV and
# NO_PROXY conventions. No Docker engine.
FROM dhi.io/sbx-templates:shell@sha256:2d3c3fb72105d2951f081ec61e26a4a05dcdbacb4163d365de67030ae61817a6
ARG HERMES_REF
USER root

# signal-cli: the real binary lives in libexec; /usr/local/bin/signal-cli (kit)
# is a wrapper that pins --config to the state dir.
COPY --from=signalcli /out/signal-cli /usr/local/libexec/signal-cli
# Fallback for libsignal's System.loadLibrary("signal_jni") path.
COPY --from=libsignal /out/libsignal_jni_aarch64.so /usr/local/lib/libsignal_jni.so
RUN ldconfig && /usr/local/libexec/signal-cli --version

# Hermes, pinned by tag, deps from its own uv.lock. Editable install so the
# bundled skills and data files resolve from the checkout.
ADD --keep-git-dir=false https://github.com/NousResearch/hermes-agent.git#${HERMES_REF} /opt/hermes/src
ENV UV_PROJECT_ENVIRONMENT=/opt/hermes/venv \
    UV_PYTHON_DOWNLOADS=never \
    UV_LINK_MODE=copy
RUN cd /opt/hermes/src \
 && uv sync --frozen --no-dev --python /usr/bin/python3 \
      --extra anthropic --extra parallel-web --extra exa \
 && ln -s /opt/hermes/venv/bin/hermes /usr/local/bin/hermes \
 && hermes --version

LABEL org.opencontainers.image.source="https://github.com/mcavage/hermes-kit" \
      org.opencontainers.image.title="hermes-base" \
      dev.hermes-kit.hermes-ref="${HERMES_REF}"

USER agent
WORKDIR /home/agent
