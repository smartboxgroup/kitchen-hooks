FROM sczizzo/trusty-tool:latest
MAINTAINER Sean Clemmer <sczizzo@gmail.com>
ENV DEBIAN_FRONTEND=noninteractive
ARG BUILD_NUMBER=1

COPY . /build

RUN cd /build && /build/tasks/package/_package.sh /artifacts

VOLUME /artifacts