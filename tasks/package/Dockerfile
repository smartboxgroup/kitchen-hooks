FROM sczizzo/trusty-tool:latest
MAINTAINER Sean Clemmer <sczizzo@gmail.com>
ENV DEBIAN_FRONTEND=noninteractive

COPY . /hooks

RUN cd /hooks \
 && /hooks/tasks/package/_package.sh \
 && rm -rf /hooks /tmp/* /var/lib/apt/lists/*

VOLUME /package