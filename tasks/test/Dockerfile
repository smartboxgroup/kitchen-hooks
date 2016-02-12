FROM ruby:2.2
MAINTAINER Sean Clemmer <sczizzo@gmail.com>
ENV DEBIAN_FRONTEND=noninteractive

COPY . /franz

RUN cd /franz \
 && touch .docker \
 && bundle \
 && bundle exec rake test
