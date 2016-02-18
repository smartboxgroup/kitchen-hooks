FROM sczizzo/trusty-tool:latest
MAINTAINER Sean Clemmer <sczizzo@gmail.com>
ENV DEBIAN_FRONTEND=noninteractive

COPY . /build

RUN cd /build \
 && touch .docker \
 && bundle update \
 && bundle exec rake report \
 && mkdir -p /reports/test \
 && mv doc /reports \
 && mv coverage /reports \
 && mv test/reports/* /reports/test

VOLUME /reports