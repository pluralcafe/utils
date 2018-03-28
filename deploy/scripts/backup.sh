#!/bin/bash

[ -z "$COMPOSE" ] && COMPOSE="$(command -v docker-compose)"
[ -z "$COMPOSE" ] && COMPOSE="/usr/local/bin/docker-compose"
[ -z "$YML_LOC" ] && YML_LOC="$HOME/docker-compose.yml"

COMPOSE="$COMPOSE -f $YML_LOC"

if [ "$1" == 'daily' ]; then
  find $HOME/backups -type f -name postgres-daily.* -mtime +7 -delete
  $COMPOSE exec -T -u postgres mstdb sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h mstdb -d postgres -U postgres" > "$HOME/backups/postgres-daily.$(date -Iseconds).pgsql"
  $COMPOSE run -T --rm web rake mastodon:media:remove_remote
fi

if [ "$1" == 'hourly' ]; then
  find $HOME/backups -type f -name postgres-hourly.* -mmin +360 -delete
  $COMPOSE exec -T -u postgres mstdb sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h mstdb -d postgres -U postgres" > "$HOME/backups/postgres-hourly.$(date -Iseconds).pgsql"
fi
