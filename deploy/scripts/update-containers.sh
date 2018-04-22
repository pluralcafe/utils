#!/bin/bash

[ -z "$COMPOSE" ] && COMPOSE="$(command -v docker-compose)"
[ -z "$COMPOSE" ] && COMPOSE="/usr/local/bin/docker-compose"

cd "$HOME" || exit

[ -z "$NGINX_WEBHOOK" ] || printf "Content-Type: text/plain\r\n\r\n"

($COMPOSE pull 2>&1 | grep --silent "Downloaded newer") && {
  $COMPOSE up -d

  docker cp "$($COMPOSE ps -q mstweb):/mastodon/public/assets" public/
  docker cp "$($COMPOSE ps -q mstweb):/mastodon/public/packs" public/

  docker system prune --all -f

  curl -sS "https://raw.githubusercontent.com/pluralcafe/utils/master/deploy/docker-compose.yml" > docker-compose.yml
}
