# syntax=docker/dockerfile:1
# Kit layer: config, persona, skills and boot scripts on top of hermes-base.
# Keep this thin; everything heavy lives in images/base.
ARG BASE=docker.io/mcavage/hermes-base:0.1.0
FROM ${BASE}

USER root
COPY --chmod=0755 bin/ /usr/local/bin/
COPY config/  /opt/hermes-kit/config/
COPY context/ /opt/hermes-kit/context/
COPY skills/  /opt/hermes-kit/skills/

# All mutable state lives under ~/state (sandbox disk; survives the 24h
# restart). `make upgrade` moves this one directory between sandboxes.
ENV HERMES_HOME=/home/agent/state/hermes \
    HK_STATE=/home/agent/state

USER agent
WORKDIR /home/agent
# Attach = interactive Hermes CLI against the same HERMES_HOME the gateway uses.
ENTRYPOINT ["/usr/local/bin/hk-attach"]
