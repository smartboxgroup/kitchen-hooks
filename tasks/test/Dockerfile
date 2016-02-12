FROM sczizzo/trusty-tool:latest
MAINTAINER Sean Clemmer <sczizzo@gmail.com>

COPY . /build

RUN cd /build \
 && touch .docker \
 && bundle \
 && bundle exec rake test
