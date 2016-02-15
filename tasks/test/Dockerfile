FROM sczizzo/trusty-tool:latest
MAINTAINER Sean Clemmer <sczizzo@gmail.com>
ENV DEBIAN_FRONTEND=noninteractive

COPY . /build

RUN cd /build \
 && touch .docker \
 && bundle update \
 && bundle exec rake test
