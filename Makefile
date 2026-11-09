.PHONY: bootstrap check fmt

bootstrap:
	scripts/bootstrap.sh

check:
	scripts/check.sh

fmt:
	. "$${TOOLS_DIR:-$$HOME/.local/aws-platform-tools}/env.sh" && terraform fmt -recursive
