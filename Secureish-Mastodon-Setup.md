# Secure-ish Mastodon Setup In A Box

Last Updated: April 9th, 2018.

## Step 1. Create a new VPS

#### Initial Server Creation

For the purposes of this guide, I'm doing this guide via assuming that you are setting up a [Vultr instance](https://www.vultr.com/?ref=7197930).

When logging into Vultr, navigate to Servers and then click the (+) button to set up a new VPS. For the following, I have these as my settings, but yours may vary:

* Server Location: New York (NJ)
* Server Type: Ubuntu 16.04 x64 (*18.04 when it comes out*)
* Server Size: 2GB memory (*or more*)
* Additional Features: *Enable IPv6*, *Enable Auto Backups*, *Block Storage Compatible*

(If you want to choose another location, don't worry about it there not being an option for Block Storage Compatible - it's only if your VPS runs out of SSD space and you need to add more.)

If you do not have an SSH key, I recommend generating an Ed25519 key by doing the following in Linux, Mac OS X or Windows Subsystem for Linux:

`$ ssh-keygen -t ed25519`

Afterwards, add a new SSH key, paste the contents of id_ed25519.pub to Vultr, and then select that as your SSH Key. Keep id_ed25519 to yourself and never give it out!

Your server hostname should be the domain name of the Mastodon instance you're creating. The server label can be anything (e.g.: mastodon).

It'll take around 3-5 minutes for the initial server setup to complete. When it does, click on the server you've just created, and make note of the root password. Go to "Settings" and make note of the IPv4 Address and the IPv6 Address.

#### Add your domain via DNS

Navigate to Servers, then DNS, and click "Add Domain" to add your domain. Make note of the IP address of your new instance.

You will be asked to enter in your domain name and IP address. Enter those, submit, and then you'll be at the Manage DNS Domain page.

Make a new IPv6 record by choosing "AAAA" under "Type", pasting the IPv6 address under "Data", and then hitting the + button under "Actions" to add a new one.

Make a new "CNAME" record as well by choosing CNAME, putting a star "*" under "Name", and under Data, type in your domain name e.g. `yourdomain.com`

With your domain registrar, add in the nameservers that are displayed under `NS` in the domain records. It may take awhile to propagate (up to 24-48 hours), but it depends on the DNS server you're using.

## Step 2. Set up the Server

#### Setting up a privileged account

Use SSH to connect to your new server by typing in the following command:

`$ ssh root@yourdomain.com`

Next, add a user that you will use to log in to SSH that is **not** the root user by adding another user (e.g. privacc, but can be something else):

`# adduser privacc`

Add sudo privileges:

`# usermod -aG sudo privacc`

Copy your SSH keys to the `privacc` account and make them owned by `privacc`:

`# cp -R ~/.ssh $(eval echo "~privacc") && chown -R privacc:privacc $(eval echo "~privacc")/.ssh`

Then exit by typing `exit`. Now try SSHing into your new account:

`$ ssh privacc@yourdomain.com`

#### Disable the root account

Now that we're logged in, we can disable password authentication to the `root` account.

`$ sudo nano /etc/ssh/sshd_config`

Find the following and replace it with this:

`RSAAuthentication yes` -> `RSAAuthentication no`

`PasswordAuthentication yes` -> `PasswordAuthentication no`

`PermitRootLogin yes` -> `PermitRootLogin no`

Restart our SSH server:

`$ sudo systemctl restart sshd`

#### Enable the firewall and update

Add OpenSSH to our firewall and start it:

```
$ sudo ufw allow OpenSSH
$ sudo ufw enable
```

Update our servers:

```
$ sudo apt update
$ sudo apt -y upgrade
$ sudo apt -y dist-upgrade
$ sudo apt -y autoremove
```

Install ntp (for up to date time):

`$ sudo apt install -y ntp`

Finally, install fail2ban:

`$ sudo apt install -y fail2ban`

#### Set up Docker and Docker Compose

Next, we're going to be setting up Docker and Docker Compose. Docker is a container software that allows us to run software easily from "images", and Docker Compose formats things for us in a way that would run Docker commands without being unnecessarily complicated.

Firstly, run:

`$ curl -fsSL https://get.docker.com -o get-docker.sh`

Now run:

`$ less get-docker.sh`

If everything looks alright and you see stuff like `# This script is meant for a quick & easy install`, exit out by pressing Q and run this:

`$ chmod a+x get-docker.sh && sudo ./get-docker.sh && rm get-docker.sh`

Next, we're going to install the latest version of Docker Compose by running these commands:

```
$ COMPOSE_VERSION=`git ls-remote https://github.com/docker/compose | grep refs/tags | grep -oP "[0-9]+\.[0-9][0-9]+\.[0-9]+$" | tail -n 1`
$ sudo curl -sS https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
$ sudo chmod a+x /usr/local/bin/docker-compose
```

When we run this command, we should get versions that match (and the version could be higher):

```
privacc@yourdomain:~$ echo $COMPOSE_VERSION
1.20.1
privacc@yourdomain:~$ docker-compose --version
docker-compose version 1.20.1, build 5d8c71b
```

#### Set up a normal user for Mastodon and give them Docker privileges

For all intents and purposes, where we're running Mastodon should *not* have sudo privileges, but should be able to run Docker and Docker Compose commands. So for this, we will add a Mastodon user, e.g.:

`$ sudo useradd mastodon`

Add Docker privileges to the `mastodon` user:

`$ sudo usermod -aG docker mastodon`

Finally, we are going to allow port 80 (HTTP) and port 443 (HTTPS) traffic, but we have no firewall rules installed yet that we can point to. As a result, we are going to manually add TCP ports 80 and 443 to our firewall, like so:

```
$ sudo ufw allow 80/tcp
$ sudo ufw allow 443/tcp
```

## Step 3. Set up Let's Encrypt certificates

We have a few options for encrypting our web server. The original is usually by using Certbot, but I generally like [Acme.sh](https://github.com/Neilpang/acme.sh) for the fact that it's lightweight, doesn't require root, and can generate ECDSA certificates (which we'll get into in a bit). For this example, we'll be installing Acme.sh.

The first step is to log in to our `mastodon` account like so:

`$ sudo su - mastodon`

Once that's done, we can download Acme.sh and install like so:

`mastodon@yourdomain:~ $ curl -sS https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh | INSTALLONLINE=1  sh`

Our main problem here is that we don't have a web server to confirm that we're really who we are, so we have two options on how we can solve this:

1. We can create a temporary web-server in our Nginx container, or
2. We can use Vultr API to verify us via DNS.

We can also set up our skeleton files:

```
$ mkdir -p .docker/nginx
$ mkdir -p .docker/mastodon
$ touch .docker/mastodon/.env.production
$ mkdir public
```

**Why is Acme.sh not running in a container?** We need some way of rebooting Nginx whenever Acme.sh fetches new certificates automatically, and there is no present way to do this if Acme is running isolated from everything else. This might be a little more risky, but this is the only software that you're installing out of Docker (if you choose option 1).

#### Option 1: Temporary Nginx in a Container

With a text editor of your choice (i.e. `nano docker-compose.yml`), make a new file named `docker-compose.yml`:

```
version: '2.1'
services:

  nginx:
    image: nginx:mainline
    volumes:
      - ./public:/usr/share/nginx/html
    ports:
      - "80:80"
    networks:
      - external_network

networks:
  external_network:
```

Next, let's bring up our `nginx` container and make sure nothing is wrong:

`$ docker-compose up nginx`

If everything boots up and looks fine, that means our webserver is running and serving contents. Hit `CTRL-C` to stop the container, and then let's run `nginx` as a daemon by doing:

`$ docker-compose up -d nginx`

The next step is to run Acme.sh and tell it to both issue certificates and point it to a place where we can store temporary text files needed for it.

First off, let's issue the certificates:

`$ acme.sh --issue -d yourdomain.com -d mail.yourdomain.com -w $(pwd)/public --keylength ec-384`

We're telling Let's Encrypt to issue a certificate to `yourdomain.com` (which you should replace) and `mail.yourdomain.com` (for your mailserver) and if you want to add subdomains, just add `-d subdomainone.yourdomain.com -d subdomaintwo.yourdomain.com` etc.

**Note:** If you are interested in using SendGrid or Mailgun for mail sending, you can leave off `-d mail.yourdomain.com`

Why `ec-384`? RSA certificates are increasingly vulnerable to being compromised, which is the default. As we're going for a secure install, issuing certificates under `ECDSA secp384r1` means that we have the equivalent of a `RSA 3072-bit key`.

Finally, let's generate `pem` files for use in Nginx, and tell Acme.sh to restart Nginx each time a certificate renewal is requested:

```
$ acme.sh --install-cert --ecc -d yourdomain.com -d mail.yourdomain.com \
   --cert-file $(pwd)/.docker/nginx/tls_cert.pem \
   --key-file $(pwd)/.docker/nginx/tls_key.pem \
   --fullchain-file $(pwd)/.docker/nginx/tls_fullchain.pem \
   --reloadcmd "$(command -v docker-compose) -f $(pwd)/docker-compose.yml stop nginx; $(command -v docker-compose) -f $(pwd)/docker-compose.yml up -d nginx"
```

With our Let's Encrypt certificates and Acme.sh being on a cron job to automatically renew them and restart our Nginx container, that part should be set up. So now we should `$ docker-compose down` to stop and remove our Nginx container, and `$ rm docker-compose.yml`

#### Option 2: Verify via DNS

Acme.sh can also verify by setting DNS records. However, there is no way for Acme.sh itself to set DNS records via the Vultr API, so we're going to have to grant it access by a program named [Lexicon](https://github.com/AnalogJ/lexicon).

The first step is to `exit` out of our `mastodon` user back into our `privacc` user. Next, we're going to have to install Pip, a package manager for the system-installed Python 3, and a few dependencies to support Pip, like so:

`$ sudo apt install -y python3-pip build-essential libssl-dev libffi-dev python3-dev`

Come back to the `mastodon` user like so:

`$ sudo su - mastodon`

Install Lexicon with extras:

`$ pip install setuptools wheel dns-lexicon`

Verify that Lexicon works:

`$ ./.local/bin/lexicon --version`

Now, go back to the Vultr Control Panel. Navigate to Account, then API. Copy the Personal Access Token to somewhere safe for now, and add your VPS to Access Control on both IPv4 and IPv6.

So, let's say your VPS's IPv4 is 207.148.123.123. Your VPS's IPv6 is 2001:19f0:...etc. Add your IPv4 address under Access Control and in the field to the right of the slash (/), enter in 32. Add the IPv4. Do the same for IPv6, except for instead of 32, enter in 128. Click Add. This whitelists our VPS to contact Vultr via Lexicon via Acme.sh.

Back in our handy dandy SSH terminal, run the following (replacing `inserttokenhere` with the token you copied):

```
$ export PATH="$PATH:$(pwd)/.local/bin"
$ export PROVIDER=vultr
$ export LEXICON_VULTR_TOKEN='inserttokenhere'
$ acme.sh --issue -d yourdomain.com -d mail.yourdomain.com --dns dns_lexicon --keylength ec-384
```

**Note:** Later in the guide, we're going to be setting up a mailserver as a part of this. If you plan on using SendGrid, Mailgun, or an external SMTP, just leave out `-d mail.yourdomain.com`.

After about 4 minutes, everything should be verified by Vultr.

Why `ec-384`? RSA certificates are increasingly vulnerable to being compromised, which is the default. As we're going for a secure install, issuing certificates under `ECDSA secp384r1` means that we have the equivalent of a `RSA 3072-bit key`.

Finally, let's generate `pem` files for use in Nginx, and tell Acme.sh to restart Nginx each time a certificate renewal is requested:

```
$ acme.sh --install-cert --ecc -d yourdomain.com -d mail.yourdomain.com \
   --cert-file $(pwd)/.docker/nginx/tls_cert.pem \
   --key-file $(pwd)/.docker/nginx/tls_key.pem \
   --fullchain-file $(pwd)/.docker/nginx/tls_fullchain.pem \
   --reloadcmd "$(command -v docker-compose) -f $(pwd)/docker-compose.yml stop nginx; $(command -v docker-compose) -f $(pwd)/docker-compose.yml up -d nginx"
```

We should be good to go now. If there are `docker-compose` errors, just ignore them for now. We need to have Acme.sh restart Nginx whenever it fetches new certificates.

## Step 4. Install Server Necessities

We will now try and configure the necessities for Mastodon to run.

#### Set up docker-compose.yml

First up, open up `$ nano docker-compose.yml` (or instead of `nano`, use `vim` or `emacs` or whatever you prefer) and paste the following, replacing `yourdomain.com` with your domain name:

```
version: '2.1'
services:

  nginx:
    restart: always
    image: nginx:mainline
    volumes:
      - ./public:/var/www/html:ro
      - ./.docker/nginx/nginx.conf:/tmp/nginx.conf:ro
      - ./.docker/nginx/tls_cert.pem:/etc/ssl/cert.pem:ro
      - ./.docker/nginx/tls_key.pem:/etc/ssl/key.pem:ro
      - ./.docker/nginx/tls_fullchain.pem:/etc/ssl/fullchain.pem:ro
      - /etc/localtime:/etc/localtime:ro
    environment:
      - NGINX_HOST=yourdomain.com
      - TLS_PROTOCOLS="TLSv1.3 TLSv1.2"
      - TLS_CIPHERS="ECDHE+CHACHA20:AES256+EECDH:AES256+EDH:!aNULL"
      - TLS_ECDH_CURVE="X25519:secp521r1:secp384r1"
    ports:
      - "80:80"
      - "443:443"
    command: sh -c "envsubst \"`env | awk -F = '{printf \" $$%s\", $$1}'`\" < /tmp/nginx.conf > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
    networks:
      - external_network
      - rails_network
      - rainloop_network
      - streaming_network

  rainloop:
    image: hardware/rainloop
    restart: unless-stopped
    depends_on:
      - mail
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./.docker/rainloop:/rainloop/data
    networks:
      - rainloop_network

  mail:
    image: tvial/docker-mailserver:latest
    restart: always
    hostname: mail
    domainname: yourdomain.com
    container_name: mail
    cap_add:
      - NET_ADMIN
    ports:
      - "25:25"
      - "143:143"
      - "587:587"
      - "993:993"
      - "4190:4190"
    environment:
      - ENABLE_SPAMASSASSIN=1
      - ENABLE_CLAMAV=1
      - ENABLE_FAIL2BAN=1
      - ENABLE_POSTGREY=1
      - ONE_DIR=1
      - DMS_DEBUG=0
      - ENABLE_MANAGESIEVE=1
      - SSL_TYPE=manual
      - SSL_CERT_PATH=/etc/ssl/cert.pem
      - SSL_KEY_PATH=/etc/ssl/key.pem
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./.docker/mail/data:/var/mail
      - ./.docker/mail/state:/var/mail-state
      - ./.docker/mail/config:/tmp/docker-mailserver/
      - ./.docker/nginx/tls_cert.pem:/etc/ssl/cert.pem:ro
      - ./.docker/nginx/tls_key.pem:/etc/ssl/key.pem:ro
      - ./.docker/nginx/tls_fullchain.pem:/etc/ssl/fullchain.pem:ro
    networks:
      - rainloop_network
      - external_network

  db:
    restart: always
    image: postgres:10.3-alpine
    networks:
      - db_network
    volumes:
      - ./.docker/mastodon/db:/var/lib/postgresql/data

  redis:
    restart: always
    image: redis:4-alpine
    networks:
      - redis_network
    volumes:
      - ./.docker/mastodon/redis:/data
  
#### OPTIONAL AND REQUIRES A LOT OF MEMORY AND CPU ####
#  es:
#    image: docker.elastic.co/elasticsearch/elasticsearch-oss:6.2.3
#    restart: always
#    environment:
#      - bootstrap.memory_lock=true
#      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
#    ulimits:
#      memlock:
#        soft: -1
#        hard: -1
#    networks:
#      - es_network
#    volumes:
#      - ./.docker/mastodon/es:/usr/share/elasticsearch/data

  rails:
    image: tootsuite/mastodon:latest
    restart: always
    env_file: ./.docker/mastodon/.env.production
    environment:
      - WEB_CONCURRENCY=2
      - MAX_THREADS=15
    command: bash -c "rake db:migrate; rm -f /mastodon/tmp/pids/server.pid; bundle exec rails s -p 3000 -b '0.0.0.0'"
    networks:
      - db_network
      - redis_network
#      - es_network
      - rails_network
    depends_on:
      - db
      - redis
#      - es
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./public/assets:/mastodon/public/assets
      - ./public/packs:/mastodon/public/packs
      - ./public/system:/mastodon/public/system

  streaming:
    image: tootsuite/mastodon:latest
    restart: always
    env_file: ./.docker/mastodon/.env.production
    command: yarn start
    networks:
      - db_network
      - redis_network
      - streaming_network
    depends_on:
      - db
#      - es
      - redis
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./public/system:/mastodon/public/system

  sidekiq:
    image: tootsuite/mastodon:latest
    restart: always
    env_file: ./.docker/mastodon/env.production
    environment:
      - DB_POOL=10
    command: bundle exec sidekiq -q default -q mailers -q pull -q push
    depends_on:
      - db
#      - es
      - redis
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./public/assets:/mastodon/public/assets
      - ./public/packs:/mastodon/public/packs
      - ./public/system:/mastodon/public/system
    networks:
      - external_network
      - db_network
#      - es_network
      - redis_network

networks:
  external_network:
    driver: bridge
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: 172.18.0.0/16
        - subnet: 2600:1234:1234:1234::/64
  db_network:
    internal: true
#  es_network:
#    internal: true
  redis_network:
    internal: true
  streaming_network:
    internal: true
  rails_network:
    internal: true
  rainloop_network:
    internal: true
```

Now, there are a few explanations to this:

1. Because we're running Mastodon and Nginx in a container, there are several components to this. As we're segmenting the network, none of the things listening on any of the servers are broadcasting to the outside world, in fact, it's not even broadcasting to your server.
2. We're bridging to separate networks in separate containers based on what we need. Nginx cannot contact the Postgres container directly, but Redis can't contact Postgres either. In fact, the only three that can see the outside world are Nginx, Mailserver and Sidekiq.
3. We don't need Elasticsearch - unless your server has a LOT of RAM and can handle the CPU load. If you think your server is powerful enough, you can uncomment the ES-specific lines above.

There's also something that you have to do: get your IPv6 subnet. Go to your Vultr control panel, head to Servers, click on your server, go to Settings, and then IPv6. Make a note of "Network" under "Public IPv6 Network". What you want to do is replace "2600:1234:1234:1234::" above in `docker-compose.yml` with that network address. That is provided to you by Vultr.

Pull all of the images related to the software above by running:

`$ docker-compose pull`

#### Set up the Mailserver

As noted, we're going to try setting up a mailserver for Mastodon to both send and receive emails. As a result, we use `docker-mailserver` as kind of a mail server in a box type of deal. (**Note:** If you do not require a mailserver and want to use something like Sendgrid or Mailgun, skip this step, and erase "rainloop" and "mail" containers from `docker-compose.yml`)

The next step in setting up `docker-mailserver` is to download the included `setup.sh` to help us set up and manage our mailserver. Run these commands first:

```
$ mkdir -p .docker/mail
$ docker-compose up -d mail
$ curl -o .docker/mail/setup.sh https://raw.githubusercontent.com/tomav/docker-mailserver/master/setup.sh
$ chmod a+x ./.docker/mail/setup.sh
```

Check to see that things are alright, not tampered with, etc. if paranoid:

`$ less .docker/mail/setup.sh # (Hit Q if alright)`

Now, we can create our admin account, by running:

`$ cd .docker/mail; ./setup.sh add admin@yourdomain.com`

Enter in a secure password. Next, set up DKIM and SPF. Run:

`$ ./setup.sh config dkim 4096`

Paste the domain records into the Vultr DNS that was explained in step 1. This is a way to sign and verify the mails that are coming and going from your domain.

Finally, let's start our mailserver:

`$ cd ../..; docker-compose stop mail; docker-compose up -d mail`

The server may lag as ClamAV updates and you may have to let it sit for a bit to gather updates. That's fine.

Exit out of the `mastodon` account back into `privacc` and run the following to allow the mail ports:

```
$ sudo ufw allow 25/tcp
$ sudo ufw allow 143/tcp
$ sudo ufw allow 587/tcp
$ sudo ufw allow 993/tcp
$ sudo ufw allow 4190/tcp
```

Then come back to `mastodon`:

`$ sudo su - mastodon`

#### Set up Nginx (again)

The next step is to set up the web server. As you've already set up `docker-compose.yml`, now you'll need to run:

`$ nano .docker/nginx/nginx.conf`

and insert the following:

```
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80 default_server;
  listen [::]:80 default_server;

  server_name $NGINX_HOST;
  root /var/www/html;

  location /.well-known/acme-challenge/ {
      allow all;
      default_type "text/plain";
  }

  location / {
      return 301 https://$host$request_uri;
  }
}

# Remove this section if no mailserver
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;

  server_name mail.$NGINX_HOST;
  server_tokens off;

  ssl_protocols $TLS_PROTOCOLS;

  ssl_ciphers $TLS_CIPHERS;
  ssl_ecdh_curve $TLS_ECDH_CURVE;
  ssl_prefer_server_ciphers on;

  ssl_session_cache shared:TLS:2m;
  ssl_session_timeout 10m;
  ssl_session_tickets off;

  ssl_stapling on;
  ssl_stapling_verify on;

  keepalive_timeout 70;
  sendfile on;
  client_max_body_size 0;

  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header Referrer-Policy "same-origin";
  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
  add_header Access-Control-Allow-Origin "https://$host";

  ssl_certificate /etc/ssl/fullchain.pem;
  ssl_certificate_key /etc/ssl/key.pem;
  ssl_trusted_certificate /etc/ssl/cert.pem;

  resolver 1.1.1.1 1.0.0.1 [2606:4700:4700::1111] [2606:4700:4700::1001] valid=300s;
  resolver_timeout 5s;

  root /var/www/html;

  location / {
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Proxy "";
    proxy_pass_header Server;

    proxy_pass http://rainloop:8888;
    proxy_buffering off;
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    tcp_nodelay on;
  }
}

server {
  listen 443 ssl http2 default_server;
  listen [::]:443 ssl http2 default_server;

  server_name $NGINX_HOST;
  server_tokens off;

  ssl_protocols $TLS_PROTOCOLS;

  ssl_ciphers $TLS_CIPHERS;
  ssl_ecdh_curve $TLS_ECDH_CURVE;
  ssl_prefer_server_ciphers on;

  ssl_session_cache shared:TLS:2m;
  ssl_session_timeout 10m;
  ssl_session_tickets off;

  ssl_stapling on;
  ssl_stapling_verify on;

  keepalive_timeout 70;
  sendfile on;
  client_max_body_size 0;

  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header Referrer-Policy "same-origin";
  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
  add_header Access-Control-Allow-Origin "https://$host";
  add_header X-Cache-Status $upstream_cache_status;

  ssl_certificate /etc/ssl/fullchain.pem;
  ssl_certificate_key /etc/ssl/key.pem;
  ssl_trusted_certificate /etc/ssl/cert.pem;

  resolver 1.1.1.1 1.0.0.1 [2606:4700:4700::1111] [2606:4700:4700::1001] valid=300s;
  resolver_timeout 5s;

  root /var/www/html;

  location / {
    try_files $uri @proxy;
  }

  location /sw.js {
    add_header Cache-Control "public, max-age=0";
    try_files $uri @proxy;
  }

  location ~ ^/(emoji|packs|sounds|system/media_attachments|system/preview_cards) {
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

    proxy_pass http://rails:3000;
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

You should be good to go.

## Step 5. Install Mastodon

We're now ready to install Mastodon.

#### Go through the Setup Guide

Mastodon has a built in setup wizard that we can use.

*Optional:* Rake commands to modify Mastodon via the command-line usually begin with `docker-compose run --rm rails rake`, so I generally shorthand this for myself by doing:

```
$ echo "alias mastorake='$(command -v docker-compose) -f $(pwd)/docker-compose.yml run --rm rails rake'" >> ~/.bashrc
$ . ~/.bashrc
```

For the purposes of the rest of the tutorial if you don't want to do this, `mastorake` will be a shorthand for `docker-compose run --rm rails rake`, but it's entirely up to you.

**Note:** There are many times where Mastodon will try running what's known as Webpack to compile all assets into a few files. This frequently takes up a LOT of RAM and CPU, and will fail. If you feel like you don't have a lot of RAM free, you can enable swap space for now. Exit out of the `mastodon` account via `$ exit` and in your `privacc` user, run the following:

```
$ sudo fallocate -l 1G /swapfile
$ sudo chmod 600 /swapfile
$ sudo mkswap /swapfile
$ sudo swapon /swapfile
```

Then simply come back to the `mastodon` user via:

`$ sudo su - mastodon`

With that being said, run the following:

`$ mastorake mastodon:setup`

Go through every step. Domain name, Single user mode. When it asks you if you're using Docker to run Mastodon, say yes. The PostgreSQL host, port, name and username and password should all be default (aka, just hit Enter). Same for Redis.

Mastodon will then prompt you if you want to store uploaded files in the cloud. If you've already got something ready, go ahead, otherwise hit no. (There is also a way to choose Amazon S3 if you ever change your mind.)

**If you set up the mailserver:** You will also be asked if you want to send emails from localhost. Choose No. The SMTP server should be `mail` with a port of `587` and the username and password should be what you have provided when doing `./setup.sh email add`. For SMTP authentication, choose `starttls`. SMTP OpenSSL verify mode should be set to `none`.

At the end, Mastodon will print out a configuration file between `Below is your configuration, save it to an .env.production file outside Docker:` and `It is also saved within this container so you can proceed with this wizard.`. Copy all of this, paste it into a Notepad for later. **You will need this.**

The next step will create the database. Just sit back for a couple of minutes.

The final step is creating CSS/JS assets via Webpack. This is the one that's going to be heavy on CPU and RAM, and also going to take anywhere from 5 to 30 minutes.

**If you get "That failed! Maybe you need swap space?"**: See the comments above on setting up a swapfile via `privacc`. You're not doomed, but you're going to have to run `$ mastorake assets:precompile` right after you exit the Setup wizard.

When you get the `Compiled all packs in /mastodon/public/packs` message, you can breathe easy. If you did the swapfile instructions above, you can disable it by exiting out of your `mastodon` account and running this as `privacc`:

```
$ sudo swapoff /swapfile
$ sudo rm /swapfile
```

And then coming back to the `mastodon` user:

`$ sudo su - mastodon`

If, however, you got a "Compiled all packs" message, opt to create an admin user straight away.

Open up `.docker/mastodon/.env.production` via `nano` and paste what the setup wizard gave you earlier.

#### Start Everything

Now that Mastodon is set up, just simply run:

`$ docker-compose down`

Then:

`$ docker-compose up -d`

Navigate to https://yourdomain.com/ and you should be presented with a login prompt. If everything works well, consider submitting your new instance to the [HSTS Preload List](https://hstspreload.org/).

**Note:** If you installed the mailserver, navigate to https://mail.yourdomain.com/?admin and log in with the credentials "admin" and password "12345". (Please change them asap!) Navigate to Domains, delete all existing domains and then add your mail domain. The IMAP and SMTP server should be just "mail", but leave the ports be. The methods should all be "STARTTLS".

## (Optional) Set up Unattended Upgrades for Ubuntu

Want to automatically fetch and apply server updates? Ubuntu comes with a tool named `unattended-upgrades` that allows just that.

Exit out of the `mastodon` user. As `privacc`, enter in:

`$ sudo nano /etc/apt/apt.conf.d/50unattended-upgrades`

Uncomment everything in the `Allowed-Origins` block.

Find `Remove-Unused-Dependencies`, uncomment the `//` and set it to `true`

Find `Automatic-Reboot`, uncomment, and set it to `true`

Find `Automatic-Reboot-Time`, uncomment, and set it to a time in 24-hour UTC that your instance will receive the least traffic.

Exit out, save, and then run:

`$ sudo nano /etc/apt/apt.conf.d/20auto-upgrades`

Paste the following:

```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
```

Exit out and save. To apply all of this, restart the server like so:

`$ sudo shutdown -r now`

## (Optional) Automatically update Docker Compose

Run the following as `privacc`:

`$ sudo nano /etc/cron.weekly/compose-upgrade && sudo chmod +x /etc/cron.weekly/compose-upgrade`

Paste the following:

```
#!/bin/bash

COMPOSE_VERSION=`git ls-remote https://github.com/docker/compose | grep refs/tags | grep -oP "[0-9]+\.[0-9][0-9]+\.[0-9]+$" | tail -n 1`
sh -c "curl -L https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose" >/dev/null 2>&1
chmod a+x /usr/local/bin/docker-compose
sh -c "curl -L https://raw.githubusercontent.com/docker/compose/${COMPOSE_VERSION}/contrib/completion/bash/docker-compose > /etc/bash_completion.d/docker-compose" >/dev/null 2>&1
```

Exit and save.

## (Optional) Backup Scripts

Courtesy of @rtucker, there's a backup script that I use to backup the PostgreSQL database and export it in such a way that my backup system will pick it up:

`$ mkdir $(pwd)/backups`

then, as `backup.sh`:

```
#!/bin/bash

[ -z "$BACKUP_LOC" ] && BACKUP_LOC="$HOME/backups"
[ ! -e "$BACKUP_LOC" ] && mkdir -p $BACKUP_LOC

[ -z "$COMPOSE" ] && COMPOSE="$(command -v docker-compose)"
[ -z "$COMPOSE" ] && COMPOSE="/usr/local/bin/docker-compose"

[ -z "$YML_LOC" ] && YML_LOC="$HOME/docker-compose.yml"

COMPOSE="$COMPOSE -f $YML_LOC"

if [ "$1" == 'daily' ]; then
  find $BACKUP_LOC -type f -name postgres-daily.* -mtime +7 -delete
  $COMPOSE exec -T -u postgres db sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h db -d postgres -U postgres" > "$BACKUP_LOC/postgres-daily.$(date -Iseconds).pgsql"
  $COMPOSE run -T --rm rails rake mastodon:media:remove_remote
fi

if [ "$1" == 'hourly' ]; then
  find $BACKUP_LOC -type f -name postgres-hourly.* -mmin +360 -delete
  $COMPOSE exec -T -u postgres db sh -c "umask 0377 && /usr/local/bin/pg_dump -Fc -h db -d postgres -U postgres" > "$BACKUP_LOC/postgres-hourly.$(date -Iseconds).pgsql"
fi
```

Then just run `chmod +x backup.sh`. Finally, just insert these entries into `crontab -e` below:

```
0 * * * * /path/to/your/backup.sh hourly
0 0 * * * /path/to/your/backup.sh daily
```

You can also prepend `COMPOSE_LOC=/path/to/docker-compose`, `YML_LOC=/path/to/my/docker-compose.yml`, `BACKUP_LOC=/home/mastodon/backups` to each command to specify somewhere else.

## Addendum: Updating Mastodon

You can update individual containers by calling `docker-compose pull CONTAINERNAME` (e.g. `CONTAINERNAME` being `nginx`, `rails`, etc.) and then re-creating the container and starting it with a `docker-compose up -d CONTAINERNAME`

To update and restart everything, just omit `CONTAINERNAME` from above.

The Docker Compose script should take care of checking to see if there are database updates before booting up the web service container. Regardless, you will need to run `mastorake assets:precompile` (aka `docker-compose run --rm rails rake assets:precompile`) each time that the Mastodon containers download an update.

#### Hard Mode (advanced users)

If you want to push the job of compiling all CSS/JS assets onto Docker Hub:

1. Fork the Mastodon repository on GitHub, 
2. Open up `Dockerfile`, find `ENTRYPOINT`,
3. Add before that line: `RUN OTP_SECRET=_ SECRET_KEY_BASE=_ rake assets:precompile`
4. Remove `/mastodon/public/assets` and `/mastodon/public/packs` from the `VOLUME` command.
5. Commit the changes.
6. Head to Docker Hub, sign up, and head to Create > Create Automated Build.
7. Select your GitHub username, and the Mastodon repository you forked and committed to.
8. On the new Docker image you've created, press "Trigger" on the build.
9. Wait about an hour.
10. In your `docker-compose.yml` file, replace `tootsuite/mastodon` with `dockerhubusername/mastodon` (with `dockerhubusername` being the username you used for Docker Hub). Remove the references to mounting `./public/assets` to `/mastodon/public/assets`, same with `public/packs`.
11. Do a `docker-compose pull` followed by `docker-compose up -d` to re-create the containers.
12. Enjoy almost-zero-downtime deployment.

Caveat is that you'll have to keep up with merging commits from upstream, but that should trigger builds automatically each time. There might also be other images with pre-built assets (vulpineclub/mastodon and pluralcafe/mastodon), but those are specific to those instances and use any images that aren't tootsuite's at your own risk.

## Questions?

Contact @isatis@vulpine.club or @KT@plural.cafe with any questions, comments or suggestions.
