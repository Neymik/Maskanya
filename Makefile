.PHONY: help install-deps lint syntax-check apply bootstrap add-entry add-exit \
        rotate-reality-keys rotate-awg-keys wipe-msk decrypt-check

ANSIBLE_DIR := ansible
PLAYBOOK := ansible-playbook -i inventory/production/hosts.yml

help:
	@echo "Maskanya operator commands:"
	@echo "  make install-deps           - install Ansible collections"
	@echo "  make lint                   - run ansible-lint + yamllint"
	@echo "  make syntax-check           - validate playbook syntax"
	@echo "  make decrypt-check          - smoke-test SOPS decryption"
	@echo "  make apply                  - converge entire fleet (site.yml)"
	@echo "  make bootstrap HOST=<name>  - first-contact bootstrap for one host"
	@echo "  make add-entry HOST=<name>  - provision new entry node"
	@echo "  make add-exit HOST=<name>   - provision new exit node"
	@echo "  make rotate-reality-keys    - rotate xray Reality keypairs"
	@echo "  make rotate-awg-keys        - rotate AmneziaWG keypairs"
	@echo "  make wipe-msk               - DESTRUCTIVE: wipe MaskanyaHopMsk (typed confirmation required)"

install-deps:
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

lint:
	yamllint $(ANSIBLE_DIR)
	cd $(ANSIBLE_DIR) && ansible-lint

syntax-check:
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/site.yml --syntax-check

decrypt-check:
	@for f in secrets/*.yml; do \
		[ -f "$$f" ] || continue; \
		echo "Checking $$f"; \
		sops --decrypt "$$f" > /dev/null || exit 1; \
	done
	@echo "All SOPS files decrypt cleanly."

apply:
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/site.yml

bootstrap:
	@test -n "$(HOST)" || (echo "Usage: make bootstrap HOST=<name>" && exit 1)
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/bootstrap.yml --limit $(HOST)

add-entry:
	@test -n "$(HOST)" || (echo "Usage: make add-entry HOST=<name>" && exit 1)
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/add-entry-node.yml --limit $(HOST)

add-exit:
	@test -n "$(HOST)" || (echo "Usage: make add-exit HOST=<name>" && exit 1)
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/add-exit-node.yml --limit $(HOST)

rotate-reality-keys:
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/rotate-reality-keys.yml

rotate-awg-keys:
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/rotate-awg-keys.yml

wipe-msk:
	cd $(ANSIBLE_DIR) && $(PLAYBOOK) playbooks/wipe-msk.yml --limit MaskanyaHopMsk
