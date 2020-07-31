include make_env

NS ?= enoviti
VERSION ?= latest

IMAGE_NAME ?= hugo-builder
CONTAINER_NAME ?= hugo-builder
CONTAINER_INSTANCE ?= default

default: build

clean:
	@echo "Cleaning up output from previous build..."
	-docker rm -f $(CONTAINER_NAME)-$(CONTAINER_INSTANCE)
	-rm -rf ./public ./archetypes
	@echo "Finished cleaning up!"

stop-clair:
	@echo "Shutting down Clair server..."
	-docker stop clair clairdb 
	-docker network remove clairnet 
	@echo "Finished shutting down Clair server!"
	
start-clair: 
	@echo "Starting Clair server..."
	@docker network create clairnet 
	@docker run --network clairnet -d --rm --name clairdb  arminc/clair-db:`date +%Y-%m-%d` 
	@sleep 5
	@docker run --network clairnet -d --rm --name clair  -p 6060-6061:6060-6061 -v $(PWD)/clair_config:/config quay.io/coreos/clair:latest -config=/config/config.yaml
	@echo "Clair Server is up!"

analyze: Dockerfile
	@echo "Analyzing Dockerfile using Hadolint..."
	@docker run --rm -i hadolint/hadolint hadolint --ignore DL3018 --ignore SC1068 - < Dockerfile
	@echo "Analyzing Dockerfile using DockerfileLint..."
	@docker run -it --rm -v $(PWD):/root/ projectatomic/dockerfile-lint dockerfile_lint \
		-r /root/policies/security_rules.yml \
		-f /root/Dockerfile
	@echo "Finished analyzing Dockerfile!"

build: analyze
	@echo "Building Hugo Builder container..."
	@docker build \
		--build-arg BUILD_DATE=`date -u +'%Y-%m-%dT%H:%M:%SZ'` \
		--build-arg BUILD_VERSION=$(VERSION) \
		--build-arg BUILD_REVISION=`git rev-parse HEAD` \
		-t $(NS)/$(CONTAINER_NAME):$(VERSION) .
	@docker images $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "Hugo Builder container built!"

build-site: build
	@echo "Building OrgDoc Site..."
	@docker run --rm --name $(CONTAINER_NAME)-$(CONTAINER_INSTANCE) -it $(PORTS) $(VOLUMES) $(ENV) -u hugo $(NS)/$(IMAGE_NAME):$(VERSION) hugo
	@echo "Finished building OrgDoc Site!"

start: build-site
	@echo "Serving OrgDoc Site..."
	@docker run --rm --name $(CONTAINER_NAME)-$(CONTAINER_INSTANCE) -it $(PORTS) $(VOLUMES) $(ENV) -u hugo $(NS)/$(IMAGE_NAME):$(VERSION) hugo server -w --bind=0.0.0.0
	@echo "Finished Serving OrgDoc Site!"

stop:
	@echo "Stop serving OrgDoc Site..."
	@docker stop $(CONTAINER_NAME)-$(CONTAINER_INSTANCE)
	@echo "Finished Serving OrgDoc Site!"

check-health:
	@echo "Checking health of OrgDoc site..."
	@docker inspect --format='{{json .State.Health}}' $(CONTAINER_NAME)-$(CONTAINER_INSTANCE)
	@echo "Finished checking health of OrgDoc site!"


security-scan:  
	@echo "Scanning Hugo Builder for security vulnerabilities..."
	@make start-clair
	@./clair-scanner --ip 172.17.0.1 $(NS)/$(CONTAINER_NAME):$(VERSION)
	@make stop-clair
	@echo "Finished Scanning Hugo Builder for security vulnerabilities!"

inspect-labels:
	@echo "Inspecting Hugo Server Container labels..."
	@echo "maintainer set to..."
	@docker inspect --format '{{ index .Config.Labels}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "Labels inspected!"

bom:
	@echo "Genarating Bill of Materials using Tern ..."
	@docker run --privileged --rm -v /var/run/docker.sock:/var/run/docker.sock -v /hostmount \
		ternd report -i $(NS)/$(CONTAINER_NAME):$(VERSION) > bom.txt
	@echo "Finished genaration of Bill of Materials!"

push:
	@echo "Pushing docker image to Docker registry..."
	@docker push $(NS)/$(IMAGE_NAME):$(VERSION)
	@echo "Finished pushing docker image to Docker registry!"

release: build security-scan
	@make push -e VERSION=$(VERSION)

.PHONY: clean security-scan inspect-labels stop-clair start-clair analyze build build-site start stop check-health push release
