KUBECFG = kubecfg
export KUBECFG_JPATH = $(CURDIR)/../../manifests/lib

install:
	$(KUBECFG) update --gc-tag=prod-runtime-ci --skip-gc jenkins.jsonnet

validate:
	$(KUBECFG) validate jenkins.jsonnet
