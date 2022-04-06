CONTAINER=farcaster-onprem-agent
TAG=probely/$(CONTAINER):${IMAGE_TAG}
PLATFORMS=linux/arm64,linux/amd64

.PHONY: all build clean prepare check-rust check-docker

build: check-env
	docker buildx build --builder multiarch -f docker/Dockerfile --platform $(PLATFORMS) -t $(TAG) --push .

clean:
	docker buildx --builder multiarch prune
prepare:
	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
	docker buildx create --name multiarch --driver docker-container
	docker buildx inspect --builder multiarch --bootstrap

check-env:
ifndef IMAGE_TAG
	$(error IMAGE_TAG env variable is undefined)
endif
