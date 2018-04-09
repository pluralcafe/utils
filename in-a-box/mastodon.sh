#!/bin/bash

do_help() {
  local myself
  myself="$(basename $0)"
  echo "Usage: $myself [command] [arguments]"
  echo
  echo "Possible commands:"
  echo
  echo " - $myself setup: Setup this instance. Generates .env.production in public/system."
  echo " - $myself update: Download and apply updates if there are newer available."
  echo " - $myself acme: Install Lets Encrypt certificates."
  echo " - $myself cron: Run cron job."
  echo " - $myself backup hourly: Run hourly backup."
  echo " - $myself backup daily: Run daily backup."
  echo " - $myself backup restore [file]: Restore .pgsql file from backup."
  echo
  echo "Also runs rake commands, e.g.:"
  echo
  echo " - $myself make_admin USERNAME=yourname"
  echo " - $myself revoke_staff USERNAME=yourname"
  echo " - $myself confirm_email USER_EMAIL=your@email"
  echo
  echo "See https://github.com/tootsuite/documentation/blob/master/Running-Mastodon/List-of-Rake-tasks.md"
  echo "for a full list of Rake tasks."
}

do_setup() {
  docker-compose run --rm web bash -c "rake mastodon:setup; mv /mastodon/.env.production /mastodon/system/"
  echo
  echo "Please move (not copy!) public/system/.env.production into .docker/mastodon/"
}

do_update() {
  (docker-compose pull 2>&1 | grep --silent "Downloaded newer") && {
    docker-compose up -d

    docker-compose run --rm web rake db:migrate
    docker-compose run --rm web rake assets:precompile

    docker image prune -f
  }
}

do_cron() {
  docker-compose run -T --rm web rake mastodon:media:remove_remote
}

do_acme() {
  local DOMAIN
  read -s "Domain Name: " DOMAIN

  curl -sS https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh | INSTALLONLINE=1  sh

  docker-compose up -d nginx
  acme.sh --issue -d $DOMAIN -w $(pwd)/public --keylength ec-384
  acme.sh --install-cert -d $DOMAIN --cert-file $(pwd)/.docker/nginx/cert.pem --key-file $(pwd)/.docker/nginx/privkey.pem --fullchain-file $(pwd)/.docker/nginx/fullchain.pem --ecc --reloadcmd "$(command -v docker-compose) -f $(pwd)/docker-compose.yml stop nginx; $(command -v docker-compose) -f $(pwd)/docker-compose.yml up -d nginx"

  [ -e "$(pwd)/.docker/nginx/production.conf" ] && \
    rm "$(pwd)/.docker/nginx/nginx.conf" && \
    mv "$(pwd)/.docker/nginx/production.conf" "$(pwd)/.docker/nginx/nginx.conf"

  docker-compose stop nginx
}

do_backup() {
  if [ "$2" == "daily" ]; then
    find "$(pwd)/.docker/mastodon/backups" -type f -name postgres-daily.* -mtime +7 -delete
    docker-compose exec -T -u postgres db sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h db -d postgres -U postgres" > "$(pwd)/.docker/mastodon/backups/postgres-daily.$(date -Iseconds).pgsql"
  fi

  if [ "$2" == "hourly" ]; then
    find "$(pwd)/.docker/mastodon/backups" -type f -name postgres-hourly.* --min +360 -delete
    docker-compose exec -T -u postgres db sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h db -d postgres -U postgres" > "$(pwd)/.docker/mastodon/backups/postgres-hourly.$(date -Iseconds).pgsql"
  fi

  if [ "$2" == "restore" ]; then
    docker-compose run --rm db sh -c "/usr/local/bin/psql --set ON_ERROR_STOP=on -Fc -h db -d postgres -U postgres" < "$3"
  fi
}

do_rake() {
  docker-compose run --rm web rake mastodon:$1 ${@:2}
}

case "$1" in
  help|h|--help)
    do_help
    ;;
  setup)
    do_setup
    ;;
  acme)
    do_acme
    ;;
  update)
    do_update
    ;;
  cron)
    do_cron
    ;;
  backup)
    do_backup "$@"
    ;;
  *)
    do_rake "$@"
    ;;
esac
