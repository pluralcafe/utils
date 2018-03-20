#!/bin/bash

# Cron job scripts for Mastodon backup and maintenance
# Usage: ./cron-backup.sh daily
#        ./cron-backup.sh hourly
# Prepend COMPOSE= env for location to docker-compose
# Prepend COMPOSE_LOC= for location to docker-compose.yml

# Adapted from https://github.com/rtucker/mastodon/blob/production/local/cron.daily/mastodon

NOW_SEC=$(date -Iseconds)
COMPOSE="$(command -v docker-compose)"

[ -z "$COMPOSE" ] && COMPOSE="/usr/local/bin/docker-compose"
[ ! -z "$COMPOSE_LOC" ] && COMPOSE=" -f $COMPOSE_LOC"

if [ "$1" == 'daily' ]; then
  find $BACKUP_LOC -type f -name postgres-daily.* -mtime +7 -delete
  $COMPOSE_LOC exec -T -u postgres db sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h db -d postgres -U postgres" > "$BACKUP_LOC/postgres-daily.$NOW_SEC.pgsql"
  $COMPOSE_LOC run -T --rm web rake mastodon:media:remove_remote
fi

if [ "$1" == 'hourly' ]; then
  find $BACKUP_LOC -type f -name postgres-hourly.* -mmin +360 -delete
  $COMPOSE exec -T -u postgres db sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h db -d postgres -U postgres" > "$BACKUP_LOC/postgres-hourly.$NOW_SEC.pgsql"
fi
