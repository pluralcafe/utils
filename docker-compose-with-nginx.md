# Run docker-compose with nginx

## docker-compose.yml

Put your [.env.production](https://github.com/tootsuite/mastodon/blob/master/.env.production.sample) in the same directory where your docker-compose.yml is and modify the /path/to's with your own:

```
version: '3'
services:

  db:
    restart: always
    image: postgres:9-alpine
    networks:
      - db_network
    volumes:
      - ./.db:/var/lib/postgresql/data

  redis:
    restart: always
    image: redis:alpine
    networks:
      - redis_network
    volumes:
      - ./.redis:/data

#  es:
#    restart: always
#    image: docker.elastic.co/elasticsearch/elasticsearch-oss:6.1.3
#    environment:
#      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
#    networks:
#      - internal_network
#    volumes:
#      - ./elasticsearch:/usr/share/elasticsearch/data

  web:
    image: pluralcafe/mastodon:stable
    restart: always
    env_file: .env.production
    command: bundle exec rails s -p 3000 -b '0.0.0.0'
    networks:
      - db_network
      - web_network
      - redis_network
    depends_on:
      - db
      - redis
#      - es
    volumes:
      - ./public/system:/mastodon/public/system
      - /etc/localtime:/etc/localtime:ro

  streaming:
    image: pluralcafe/mastodon:stable
    restart: always
    env_file: .env.production
    command: yarn start
    networks:
      - db_network
      - streaming_network
      - redis_network
    depends_on:
      - db
      - redis

  sidekiq:
    image: pluralcafe/mastodon:stable
    restart: always
    env_file: .env.production
    command: bundle exec sidekiq -q default -q mailers -q pull -q push
    depends_on:
      - db
      - redis
    networks:
      - external_network
      - db_network
      - redis_network
    volumes:
      - ./public/system:/mastodon/public/system

  nginx:
    image: nginx:alpine
    restart: always
    environment:
      - NGINX_SERVER=example.com
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/site.template:ro
      - ./public:/var/www/html:ro
      - /var/log/nginx:/var/log/nginx
      - /var/cache/nginx:/var/cache/nginx
      - /path/to/letsencrypt/fullchain.pem:/etc/ssl/certs/fullchain.pem:ro
      - /path/to/letsencrypt/key.pem:/etc/ssl/private/key.pem:ro
      - /path/to/letsencrypt/cert.pem:/etc/ssl/certs/cert.pem:ro
      - /path/to/dhparam.pem:/etc/ssl/dhparam.pem:ro
    ports:
      - "80:80"
      - "443:443"
    networks:
      - external_network
      - web_network
      - streaming_network
    command: sh -c "(cat /etc/nginx/conf.d/site.template | sed 's|NGINX_SERVER|$NGINX_SERVER|g') > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"

networks:
  external_network:
  db_network:
    internal: true
  redis_network:
    internal: true
  web_network:
    internal: true
  streaming_network:
    internal: true
```

## nginx.conf (No Modifications)

```
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  listen [::]:80;
  
  server_name NGINX_SERVER;

  root /var/www/html;
  location /.well-known/acme-challenge/ { allow all; }
  location / { return 301 https://$host$request_uri; }
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;

  server_name NGINX_SERVER;
  server_tokens off;

  ssl_certificate /etc/ssl/certs/fullchain.pem;
  ssl_certificate_key /etc/ssl/private/key.pem;
  ssl_trusted_certificate /etc/ssl/certs/cert.pem;

  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers ECDHE+CHACHA20:AES256+EECDH:AES256+EDH:!aNULL;
  ssl_prefer_server_ciphers on;
  ssl_ecdh_curve secp521r1:secp384r1;
  ssl_session_cache shared:TLS:2m;
  ssl_session_timeout 10m;
  ssl_session_tickets off;
  ssl_stapling on;
  ssl_stapling_verify on;

  resolver 8.8.8.8 8.8.4.4 valid=300s;
  resolver_timeout 5s;

  ssl_dhparam /etc/ssl/dhparam.pem;

  keepalive_timeout 70;
  sendfile on;
  client_max_body_size 0;

  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header Referrer-Policy "same-origin";
  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
  add_header Content-Security-Policy "Content-Security-Policy: frame-ancestors 'none'; object-src 'none'; script-src 'self'; base-uri 'none';";
  add_header Access-Control-Allow-Origin https://NGINX_SERVER;
  add_header X-Cache-Status $upstream_cache_status;

  location / {
    try_files $uri @proxy;
  }

  location /sw.js {
    add_header Cache-Control "public, max-age=0";
    try_files $uri @proxy;
  }

  location ~ ^/(emoji|packs|system/accounts/avatars|system/media_attachments/files) {
    add_header Cache-Control "public, max-age=31536000, immutable";

    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    try_files $uri @proxy;
  }

  location @proxy {
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Proxy "";
    proxy_pass_header Server;

    proxy_pass http://web:3000;
    proxy_buffering on;
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    proxy_cache CACHE;
    proxy_cache_valid 200 7d;
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    proxy_cache_lock on;
    proxy_cache_revalidate on;

    tcp_nodelay on;
  }

  location /api/v1/streaming {
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Proxy "";

    proxy_pass http://streaming:4000;
    proxy_buffering off;
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    tcp_nodelay on;
  }

  error_page 403 /assets/403.html;
  error_page 404 /assets/404.html;
  error_page 410 /assets/410.html;
  error_page 422 /assets/422.html;
  error_page 500 501 502 503 504 /assets/500.html;
}

proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=CACHE:10m inactive=7d max_size=2g use_temp_path=off;
```
