# Mastodon Secure-ish Setup in a Box

Step 1: Git clone this repository.

Step 2: Replace `example.com` in `docker-compose.yml` with your server name.

Step 3: Run `./mastodon.sh setup` and afterwards, move `public/system/.env.production` to the `.docker/mastodon/` folder.

Step 4: Run `./mastodon.sh acme` to set up Let's Encrypt. Make sure that port 80 is allowed by the firewall.

Step 5: Run `docker-compose up -d` to start all services. Verify with `docker-compose ps` that they're up, and if there's errors, `docker-compose logs -f`.

Step 6: Register on the instance.

Step 7: Run `./mastodon.sh make_admin USERNAME=yourusername` (replace "yourusername" with your username).

Step 8: Set a cron job to run `./mastodon.sh cron` daily via inserting `@daily /path/to/mastodon.sh cron` into `crontab -e`.

Step 9: Optionally, set a daily cron to run `./mastodon.sh backup daily` and an hourly cron for `./mastodon.sh backup hourly`.

Step 10: Enjoy! Don't forget to set up your OS's firewall.
