#!/bin/bash

[ -z "$YML_LOC" ] && YML_LOC="$HOME"
cd $YML_LOC

echo "Setting up the instance..."
echo

curl -fsSL https://raw.githubusercontent.com/tootsuite/mastodon/master/.env.production.sample -o "$YML_LOC/.docker/mastodon/.env.production"

MUID="$(docker-compose run --rm mstweb id -u 2>/dev/null)"
SECRET_KEY_BASE=$(hexdump -vn 64 -e ' /1 "%02x"' /dev/urandom)
OTP_SECRET=$(hexdump -vn 64 -e ' /1 "%02x"' /dev/urandom)

sed -i 's|REDIS_HOST=redis|REDIS_HOST=mstredis|' $YML_LOC/.docker/mastodon/.env.production
sed -i 's|DB_HOST=db|DB_HOST=mstdb|' $YML_LOC/.docker/mastodon/.env.production
sed -i 's|ES_HOST=es|ES_HOST=mstes|' $YML_LOC/.docker/mastodon/.env.production
sed -i "s|SECRET_KEY_BASE=|SECRET_KEY_BASE=$SECRET_KEY_BASE|" $YML_LOC/.docker/mastodon/.env.production
sed -i "s|OTP_SECRET=|OTP_SECRET=$OTP_SECRET|" $YML_LOC/.docker/mastodon/.env.production

docker-compose run --rm mstweb rake db:migrate
(openssl dhparam -rand /dev/urandom -out $YML_LOC/.docker/nginx/dhparam.pem 4096 2>&1 >/dev/null) & pid=$!

echo
echo "Mostly set up. Modify .docker/mastodon/.env.production settings and then"
echo "you can do a 'docker-compose up -d' on this instance. OpenSSL is still"
echo "running, so wait a bit for it to finish too."