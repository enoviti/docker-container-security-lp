FROM alpine:3.12

ARG BUILD_DATE 
ARG BUILD_VERSION
ARG BUILD_REVISION

LABEL maintainer="Anshuman Purohit<apurohit@enoviti.com>"
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.version=$BUILD_VERSION
LABEL org.opencontainers.image.revision=$BUILD_REVISION
LABEL org.opencontainers.image.license="MIT"
LABEL org.opencontainers.image.URL="http://enoviti.com"
LABEL org.opencontainers.image.title="OrgDoc Hugo Builder Image"


RUN apk add --no-cache \
    curl \
    git \
    openssh-client \
    rsync

ENV VERSION 0.64.0
WORKDIR  /usr/local/src 
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# Install Hugo
RUN curl -L -o hugo_${VERSION}_Linux-64bit.tar.gz https://github.com/gohugoio/hugo/releases/download/v${VERSION}/hugo_${VERSION}_Linux-64bit.tar.gz \
    && curl -L https://github.com/gohugoio/hugo/releases/download/v${VERSION}/hugo_${VERSION}_checksums.txt | grep hugo_${VERSION}_Linux-64bit.tar.gz | sha256sum -c \
    && tar -xf hugo_${VERSION}_Linux-64bit.tar.gz \
    && rm hugo_${VERSION}_Linux-64bit.tar.gz \
    && mv hugo /usr/local/bin/hugo 
# Create hugo User and Group
RUN addgroup -Sg 1000 hugo \
    && adduser -SG hugo -u 1000 -h /src hugo

USER hugo
HEALTHCHECK --timeout=3s CMD hugo env || exit 1

WORKDIR /src

EXPOSE 1313