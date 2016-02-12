FROM sczizzo/trusty-tool
MAINTAINER Sean Clemmer <sczizzo@gmail.com>

COPY . /build

RUN cd /build \
 && /build/tasks/package/_package.sh \
 && rm -rf /build /tmp/* /var/lib/apt/lists/*

VOLUME /artifacts