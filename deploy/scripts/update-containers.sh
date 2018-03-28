#!/bin/bash

[ -z "$COMPOSE" ] && COMPOSE="$(command -v docker-compose)"
[ -z "$COMPOSE" ] && COMPOSE="/usr/local/bin/docker-compose"

cd $HOME

($COMPOSE pull 2>&1 | grep --silent "Downloaded newer") && \
  $COMPOSE up -d && \
  docker cp $($COMPOSE ps -q mstweb):/mastodon/public/assets public/ && \
  docker cp $($COMPOSE ps -q mstweb):/mastodon/public/packs public/ && \
  docker image prune -f
