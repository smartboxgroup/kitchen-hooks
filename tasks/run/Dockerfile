FROM sczizzo/trusty-tool:latest
MAINTAINER Sean Clemmer <sczizzo@gmail.com>
ENV DEBIAN_FRONTEND=noninteractive

COPY . /kitchen_hooks

RUN mkdir -p /etc/kitchen_hooks/ && touch /etc/kitchen_hooks/app.db
RUN ln -s /kitchen_hooks/etc/config.json /etc/config.json
RUN cd /kitchen_hooks && bundle update && bundle package --all && rake build && rake install

EXPOSE 80

CMD kitchen_hooks server -c etc/config.json -p 80 -e production
