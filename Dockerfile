FROM alpine:3.12 as build

RUN apk add --no-cache \
    curl \
    git \
    openssh-client \
    rsync

ENV VERSION 0.64.0
WORKDIR  /usr/local/src 
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
#Install Hugo
RUN curl -L -o hugo_${VERSION}_Linux-64bit.tar.gz https://github.com/gohugoio/hugo/releases/download/v${VERSION}/hugo_${VERSION}_Linux-64bit.tar.gz \
    && curl -L https://github.com/gohugoio/hugo/releases/download/v${VERSION}/hugo_${VERSION}_checksums.txt | grep hugo_${VERSION}_Linux-64bit.tar.gz | sha256sum -c \
    && tar -xf hugo_${VERSION}_Linux-64bit.tar.gz \
    && rm hugo_${VERSION}_Linux-64bit.tar.gz \
    && mv hugo /usr/local/bin/hugo 

#Build Site
COPY orgdocs/ /site
WORKDIR /site
RUN hugo

FROM nginx:alpine as production

ARG BUILD_DATE 
ARG BUILD_VERSION
ARG BUILD_REVISION

LABEL maintainer="Anshuman Purohit<apurohit@enoviti.com>"
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.version=$BUILD_VERSION
LABEL org.opencontainers.image.revision=$BUILD_REVISION
LABEL org.opencontainers.image.license="MIT"
LABEL org.opencontainers.image.URL="https://github.com/enoviti/docker-container-security-lp"
LABEL org.opencontainers.image.title="OrgDoc Hugo Builder Image"

#Install tini
RUN apk add --no-cache tini

#Deploy Site 
COPY ./nginx_config/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /site/public /var/www/site
WORKDIR /var/www/site

# Create hugo User and Group
RUN addgroup -Sg 1000 hugo \
    && adduser -SG hugo -u 1000 -h /var/www/site hugo \
    && touch /var/run/nginx.pid \
    && chown -R hugo:hugo /var/run/nginx.pid \
    && chown -R hugo:hugo /var/cache/nginx
USER hugo

HEALTHCHECK --timeout=3s CMD curl http://localhost:8080/ || exit 1
#ENTRYPOINT ["/sbin/tini", "nginx -g 'daemon off;'"]
