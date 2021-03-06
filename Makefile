HOSTNAME   = vulcan
REMOTES	   = hermes athena
GIT_REMOTE = jwiegley
MAX_AGE    = 14

# Lazily evaluated variables; expensive to compute, but we only want it do it
# when first necessary.
GIT_DATE   = git --git-dir=nixpkgs/.git show -s --format=%cd --date=format:%Y%m%d_%H%M%S
HEAD_DATE  = $(eval HEAD_DATE := $(shell $(GIT_DATE) HEAD))$(HEAD_DATE)
LKG_DATE   = $(eval LKG_DATE  := $(shell $(GIT_DATE) last-known-good))$(LKG_DATE)

ifeq ($(NOCACHE),true)
NIXOPTS	   = --option build-use-substitutes false	\
	     --option substituters ''			\
	     --option builders ''
else
NIXOPTS	   =
endif
NIX_CONF   = $(HOME)/src/nix
NIXPATH	   = $(NIX_PATH):localconfig=$(NIX_CONF)/config/$(HOSTNAME).nix
PRENIX	   = PATH=$(BUILD_PATH)/sw/bin:$(PATH) NIX_PATH=$(NIXPATH)

NIX	   = $(PRENIX) nix
NIX_BUILD  = $(PRENIX) nix-build
NIX_ENV	   = $(PRENIX) nix-env
NIX_STORE  = $(PRENIX) nix-store
NIX_GC	   = $(PRENIX) nix-collect-garbage

BUILD_ARGS = $(NIXOPTS) --keep-going --argstr version $(HEAD_DATE)
ifeq ($(REALBUILDPATH),true)
BUILD_PATH = $(eval BUILD_PATH :=					\
		$(shell echo NIX_PATH=$(NIXPATH) nix-build $(BUILD_ARGS)))$(BUILD_PATH)
else
BUILD_PATH = /run/current-system
endif

DARWIN_REBUILD = $(PRENIX) $(BUILD_PATH)/sw/bin/darwin-rebuild
HOME_MANAGER   = $(PRENIX) HOME_MANAGER_CONFIG=$(NIX_CONF)/config/home.nix	\
			   $(BUILD_PATH)/sw/bin/home-manager

all: rebuild

%-all: %
	for host in $(REMOTES); do					\
	    ssh $$host "make -C $(NIX_CONF) HOSTNAME=$$host $<";	\
	done

build:
	$(NIX) build -f . $(BUILD_ARGS)
	@rm -f result*

darwin-switch:
	$(DARWIN_REBUILD) switch -Q
	@echo "Darwin generation: $$($(DARWIN_REBUILD) --list-generations | tail -1)"

home-switch:
	$(HOME_MANAGER) switch
	@echo "Home generation: $$($(HOME_MANAGER) generations | head -1)"
	@for file in $(HOME)/.config/fetchmail/config		\
		     $(HOME)/.config/fetchmail/config-lists; do	\
	    cp -pL $$file $$file.copy;				\
	    chmod 0600 $$file.copy;				\
	done

home-manager-news:
	$(HOME_MANAGER) news

switch: darwin-switch home-switch

rebuild: build switch

pull:
	(cd darwin		   && git pull --rebase)
	(cd home-manager	   && git pull --rebase)
	(cd overlays/emacs-overlay && git pull --rebase)
	(cd nixpkgs		   && git pull --rebase)

tag-before:
	git --git-dir=nixpkgs/.git branch -f before-update HEAD

tag-working:
	git --git-dir=nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=nixpkgs/.git branch -D before-update
	git --git-dir=nixpkgs/.git tag -f known-good-$(LKG_DATE) last-known-good

mirror:
	git --git-dir=nixpkgs/.git push $(GIT_REMOTE) -f master:master
	git --git-dir=nixpkgs/.git push $(GIT_REMOTE) -f unstable:unstable
	git --git-dir=nixpkgs/.git push $(GIT_REMOTE) -f last-known-good:last-known-good
	git --git-dir=nixpkgs/.git push -f --tags $(GIT_REMOTE)
	git --git-dir=darwin/.git push --mirror $(GIT_REMOTE)
	git --git-dir=home-manager/.git push --mirror $(GIT_REMOTE)
	git --git-dir=overlays/emacs-overlay/.git push --mirror $(GIT_REMOTE)

working: tag-working mirror

update: tag-before pull rebuild working

update-sync: update copy rebuild-all

check:
	$(NIX_STORE) --verify --repair --check-contents

########################################################################

copy-nix:
	@for host in $(REMOTES); do			\
	    $(NIX) copy --keep-going --to ssh://$$host	\
	        $(HOME)/.nix-profile $(BUILD_PATH);	\
	done

copy: copy-nix
	@for host in $(REMOTES); do		\
	    push -h $(HOSTNAME) -f src $$host;	\
	done

########################################################################

define delete-generations
	$(NIX_ENV) $(1) --delete-generations			\
	    $(shell $(NIX_ENV) $(1)				\
		--list-generations | field 1 | head -n -$(2))
endef

define delete-generations-all
	$(call delete-generations,,$(1))
	$(call delete-generations,-p /nix/var/nix/profiles/system,$(1))
endef

clean: gc check

fullclean: gc-old check

remove-build-products:
	clean $(HOME)/Documents $(HOME)/src

gc:
	$(call delete-generations-all,$(MAX_AGE))
	$(NIX_GC) --delete-older-than $(MAX_AGE)d

gc-old: remove-build-products
	$(call delete-generations-all,1)
	$(NIX_GC) --delete-old

########################################################################
#
# These rules are used for debugging only
#

sizes:
	df -H /nix

tools:
	@echo ""
	@echo export NIXOPTS=$(NIXOPTS)
	@echo export NIX_PATH=$(NIXPATH)
	@echo ""
	@PATH=$(BUILD_PATH)/sw/bin:$(PATH)	\
	    which				\
		field				\
		find				\
		git				\
		head				\
		make				\
		nix-build			\
		nix-env				\
		sort				\
		sudo				\
		uniq
	@echo ""
