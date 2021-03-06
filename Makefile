include make_env

NS ?= enoviti
VERSION ?= latest

IMAGE_NAME ?= hugo-builder
CONTAINER_NAME ?= hugo-builder
CONTAINER_INSTANCE ?= default
USER ?= apurohit

default: build

clean:
	@echo "Cleaning up output from previous build..."
	@docker image prune -f
	@docker container prune -f
	@docker volume prune -f
	-rm -rf ./public
	@echo "Finished cleaning up!"

analyze: Dockerfile
	@echo "Analyzing Dockerfile using Hadolint..."
	@docker run --rm -i hadolint/hadolint hadolint --ignore DL3018 --ignore SC1068 - < Dockerfile
	@echo "Analyzing Dockerfile using DockerfileLint..."
	@docker run -it --rm -v $(PWD):/root/ projectatomic/dockerfile-lint dockerfile_lint \
		-r /root/policies/all_rules.yml \
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

start: 
	@echo "Starting OrgDoc Site..."
	@docker run --rm --name $(CONTAINER_NAME)-$(CONTAINER_INSTANCE) -d $(PORTS) $(ENV) $(NS)/$(IMAGE_NAME):$(VERSION) 
	@echo "Started Serving OrgDoc Site!"

start-trusted: 
	@echo "Starting OrgDoc Site (Trusted)..."
	@DOCKER_CONTENT_TRUST=1 \
		docker run --rm --name $(CONTAINER_NAME)-$(CONTAINER_INSTANCE) -d $(PORTS) $(ENV) $(NS)/$(IMAGE_NAME):1.0 
	@echo "Started OrgDoc Site (Trusted)!"

stop:
	@echo "Stop serving OrgDoc Site..."
	@docker stop $(CONTAINER_NAME)-$(CONTAINER_INSTANCE)
	@echo "Stopped OrgDoc Site!"

healthcheck:
	@echo "Checking health of OrgDoc site..."
	@docker inspect --format='{{json .State.Health}}' $(CONTAINER_NAME)-$(CONTAINER_INSTANCE)
	@echo "Finished checking health of OrgDoc site!"

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

security-scan:  
	@echo "Scanning Hugo Builder for security vulnerabilities..."
	@make start-clair
	@./clair-scanner --ip `docker network inspect bridge --format='{{(index .IPAM.Config 0).Gateway}}'` $(NS)/$(CONTAINER_NAME):$(VERSION)
	@make stop-clair
	@echo "Finished Scanning Hugo Builder for security vulnerabilities!"

inspect-labels:
	@echo "Inspecting Hugo Server Container labels..."
	@echo "maintainer set to..."
	@docker inspect --format '{{ index .Config.Labels "maintainer"}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "OCI created set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.created"}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "OCI version set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.version"}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "OCI revision set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision"}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "OCI license set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.license"}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "OCI URL set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.URL"}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "OCI title set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.title"}}' $(NS)/$(CONTAINER_NAME):$(VERSION)
	@echo "Labels inspected!"

bom:
	@echo "Genarating Bill of Materials using Tern ..."
	@docker run --privileged --rm -v /var/run/docker.sock:/var/run/docker.sock -v /hostmount \
		ternd report -i $(NS)/$(CONTAINER_NAME):$(VERSION) > bom.spdx
	@ls -la bom.spdx
	@echo "Finished genaration of Bill of Materials!"

test:
	@make start
	@sleep 10
	@make healthcheck stop
	
push:
	@echo "Pushing docker image to Docker registry..."
	@docker push $(NS)/$(IMAGE_NAME):$(VERSION)
	@echo "Finished pushing docker image to Docker registry!"

release: build test security-scan inspect-labels bom
	@make push -e VERSION=$(VERSION)

dct-keygen:
	@docker trust key generate $(USER) --dir ~/.docker/trust
	@docker trust signer add --key ~/.docker/trust/$(USER).pub $(USER) $(NS)/$(IMAGE_NAME)
	@notary -d ~/.docker/trust key list

dct-sign:
	@docker trust sign $(NS)/$(IMAGE_NAME):$(VERSION)
	@docker trust inspect --pretty $(NS)/$(IMAGE_NAME):$(VERSION)

.PHONY: clean test security-scan inspect-labels stop-clair start-clair analyze build build-site start stop healthcheck push release
