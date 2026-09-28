# hermes-kit. Everything targets linux/arm64 and Docker cloud sandboxes.
#
# First run:
#   make base push-base kit        # build + push hermes-base, build + push the kit
#   make secrets                   # prompts for each cloud secret (values never hit argv)
#   make up SIGNAL_ACCOUNT=+1...   # create the sandbox
#   make link                      # scan the QR in Signal > Linked devices
#   make doctor
#
# Known sbx bug (nightly 55b8dd3, v0.46.0-rc5): once a sandbox is created with
# --on-timeout restart, `sbx --cloud exec/cp` fail with "unknown on_timeout 4".
# Until that's fixed, run link/doctor/logs from the Console web terminal
# (same commands, minus the `sbx --cloud exec` prefix).

REGISTRY  ?= docker.io/mcavage
VERSION   ?= 0.1.2
BASE_TAG  ?= 0.1.0
BASE      := $(REGISTRY)/hermes-base:$(BASE_TAG)
KIT       := $(REGISTRY)/hermes-kit:$(VERSION)
NAME      ?= hermes
PLATFORM  := linux/arm64
# micro: 1 vCPU / 2 GiB. The gateway idles light.
SHAPE     ?= --cpus 1 --memory 2g
EXEC      := sbx --cloud exec $(NAME)
EXEC_IT   := sbx --cloud exec -it $(NAME)

.PHONY: base push-base kit secrets up link attach doctor logs quiesce upgrade down

base:
	docker buildx build --platform $(PLATFORM) -t $(BASE) --load images/base

push-base:
	docker push $(BASE)

# The kit frontend (# syntax=docker/sandbox-kit:3) reads hermes.yaml and
# builds hermes.dockerfile on top of $(BASE). Pushed, never loaded: cloud
# can't run images that only exist locally.
kit:
	docker buildx build --platform $(PLATFORM) -f hermes.yaml \
	  --build-arg BASE=$(BASE) -t $(KIT) --push .

secrets:
	sbx --cloud secret set anthropic
	sbx --cloud secret set github
	sbx --cloud secret set-custom --name fastmail --host api.fastmail.com --env FASTMAIL_API_TOKEN
	@echo "optional: sbx --cloud secret set openai | google; sbx --cloud secret set-custom --name parallel --host api.parallel.ai --env PARALLEL_API_KEY --header x-api-key"

up:
	@test -n "$(SIGNAL_ACCOUNT)" || { echo "set SIGNAL_ACCOUNT=+1..."; exit 1; }
	sbx --cloud create --name $(NAME) --platform $(PLATFORM) $(SHAPE) \
	  --ttl 24h --on-timeout restart \
	  --kit-arg signalAccount=$(SIGNAL_ACCOUNT) $(KIT)

# Links this sandbox as a secondary device on your number. Renders a QR in
# the terminal; scan it from Signal > Settings > Linked devices. Then boots
# signal-cli under supervision.
link:
	$(EXEC_IT) bash -lc 'signal-cli link -n hermes-kit && hk-boot'

attach:
	sbx --cloud run --name $(NAME)

doctor:
	$(EXEC) hk-doctor

logs:
	$(EXEC) bash -lc 'tail -n 50 ~/state/logs/*.log'

quiesce:
	$(EXEC) hk-quiesce

# Move ~/state to a sandbox running a new kit version. Signal keys pass
# through a 0700 temp dir on this machine and are deleted afterwards.
upgrade:
	@test -n "$(SIGNAL_ACCOUNT)" || { echo "set SIGNAL_ACCOUNT=+1..."; exit 1; }
	@test -n "$(NEW)" || { echo "set NEW=<new sandbox name>"; exit 1; }
	$(EXEC) hk-quiesce
	$(EXEC) hk-supervise --stop gateway
	umask 077 && tmp=$$(mktemp -d) && trap 'rm -rf "$$tmp"' EXIT && \
	  sbx --cloud cp $(NAME):/home/agent/state "$$tmp/" && \
	  sbx --cloud create --name $(NEW) --platform $(PLATFORM) $(SHAPE) \
	    --ttl 24h --on-timeout restart --kit-arg signalAccount=$(SIGNAL_ACCOUNT) $(KIT) && \
	  sbx --cloud cp "$$tmp/state/." $(NEW):/home/agent/state/ && \
	  sbx --cloud exec $(NEW) hk-boot && sbx --cloud exec $(NEW) hk-doctor
	@echo "new sandbox $(NEW) is up. When happy: sbx --cloud rm --force $(NAME)"

down:
	sbx --cloud rm $(NAME)
