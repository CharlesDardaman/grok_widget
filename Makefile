.PHONY: install-resign-agent uninstall-resign-agent resign check-resign

resign:
	./scripts/resign.sh --force

check-resign:
	./scripts/resign.sh --check

install-resign-agent:
	./scripts/install-resign-agent.sh

uninstall-resign-agent:
	./scripts/install-resign-agent.sh --uninstall
