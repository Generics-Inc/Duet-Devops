#!/bin/bash

export $(cat ./.env | grep -v ^# | xargs) >/dev/null

project_name="${PROJECT_NAME:-build}"
domains=("${DOMAIN} www.${DOMAIN}")
email=${EMAIL}
staging=${STAGING:-0}
data_path="./certbot"
rsa_key_size=4096
regex="([^www.].+)"

if [ "$EUID" -ne 0 ]; then echo "Please run $0 as root" && exit; fi

clear

if [ "$#" -eq 0 ]; then
  echo "Build HELP:"
  echo
  echo "init - first initial project"
  echo "start - up all containers"
  echo "restart - restart all docker containers"
  echo "clean - clear old build data"
  echo
  echo "db - options for operations with db"
  echo "rebuild - options for operations with builder containers"
  echo "logs - options for logs any running container"
  echo "cert - options for certificates control"
  exit
fi

function certificateBuilder {
  mkdir -p "$data_path"

  if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] && [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    echo "### Downloading recommended TLS parameters... ###"
    mkdir -p "$data_path/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  fi

  for domain in ${!domains[*]}; do
    domain_set=(${domains[$domain]})
    domain_name=`echo ${domain_set[0]} | grep -o -P $regex`
    mkdir -p "$data_path/conf/live/$domain_name"

    if [ ! -e "$data_path/conf/live/$domain_name/cert.pem" ]; then
      echo "### Creating dummy certificate for $domain_name domain... ###"
      path="/etc/letsencrypt/live/$domain_name"
      docker compose run --rm --entrypoint "openssl req -x509 -nodes -newkey rsa:1024 \
      -days 1 -keyout '$path/privkey.pem' -out '$path/fullchain.pem' -subj '/CN=localhost'" certbot
    fi
  done

  echo "### Starting nginx... ###"
  docker compose up -d nginx && docker compose restart nginx

  case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
  esac

  if [ $staging != "0" ]; then staging_arg="--staging"; fi

  for domain in ${!domains[*]}; do
    domain_set=(${domains[$domain]})
    domain_name=`echo ${domain_set[0]} | grep -o -P $regex`

    if [ -e "$data_path/conf/live/$domain_name/cert.pem" ]; then
      echo "Skipping $domain_name domain";
    else
      echo "### Deleting dummy certificate for $domain_name domain... ###"
      rm -rf "$data_path/conf/live/$domain_name"
      echo "### Requesting Let's Encrypt certificate for $domain_name domain... ###"

      domain_args=""
      for domain in "${domain_set[@]}"; do
        domain_args="$domain_args -d $domain"
      done

      mkdir -p "$data_path/www"
      docker compose run --rm --entrypoint "certbot certonly --webroot -w /var/www/certbot --cert-name $domain_name $domain_args \
      $staging_arg $email_arg --rsa-key-size $rsa_key_size --agree-tos --force-renewal --non-interactive" certbot
    fi
  done
}

if [ "$1" == "init" ]; then
  docker compose up -d
  docker exec -d "${project_name}-server" npm run db:push
  docker exec -d "${project_name}-server" npm run db:seed
  exit
fi
if [ "$1" == "start" ]; then
  docker compose up -d
  exit
fi
if [ "$1" == "restart" ]; then
  docker compose restart
  exit
fi
if [ "$1" == "clean" ]; then
  docker system prune
  exit
fi
if [ "$1" == "db" ]; then
  if [ "$#" -eq 1 ]; then
    echo "### DB HELP: "
    echo "  db push        - run db initialize"
    echo "  db push:force  - run db push with data delete"
    echo "  db migration   - run db migration"
    echo "  db seed        - run upload seed to db"
    exit
  fi

  if [ "$2" == "push" ]; then
    docker exec -d "${project_name}-server" npm run db:push
    exit
  fi
  if [ "$2" == "push:force" ]; then
    docker exec -d "${project_name}-server" npm run db:push:force
    exit
  fi
  if [ "$2" == "migration" ]; then
    docker exec -d "${project_name}-server" npm run db:migration
    exit
  fi
  if [ "$2" == "seed" ]; then
    docker exec -d "${project_name}-server" npm run db:seed
    exit
  fi

  echo "Unknown command! Exit...";
  exit
fi
if [ "$1" == "rebuild" ]; then
  if [ "$#" -eq 1 ]; then
    echo "### Rebuild HELP: "
    echo "  rebuild nginx    - rebuild only nginx container"
    echo "  rebuild web      - rebuild only web container"
    echo "  rebuild server   - rebuild only server container"
    echo "  rebuild full     - rebuild full app with remove db volume"
    exit
  fi

  if [ "$2" == "nginx" ]; then
    docker compose restart nginx
    exit
  fi
  if [ "$2" == "web" ]; then
    docker compose build web
    docker compose up -d web
    exit
  fi
  if [ "$2" == "server" ]; then
    docker compose build server
    docker compose up -d server
    exit
  fi
  if [ "$2" == "soft" ]; then
    docker compose down
    docker rmi "${project_name}-server"
    docker rmi "${project_name}-web"
    docker compose up -d
    exit
  fi
  if [ "$2" == "full" ]; then
    docker compose down
    docker rmi "${project_name}-server"
    docker rmi "${project_name}-web"
    docker volume rm "${project_name}-db"
    docker volume rm "${project_name}-minio"
    docker compose up -d
    exit
  fi

  echo "Unknown command! Exit...";
  exit
fi
if [ "$1" == "logs" ]; then
  if [ "$#" -eq 1 ]; then
    echo "### Logs HELP: "
    echo "  nginx    - nginx container logs"
    echo "  web      - web container logs"
    echo "  server   - server container logs"
    echo "  db       - db container logs"
    exit
  fi

  if [ "$2" == "nginx" ]; then
    docker logs "${project_name}-nginx"
    exit
  fi
  if [ "$2" == "web" ]; then
    docker logs "${project_name}-web"
    exit
  fi
  if [ "$2" == "server" ]; then
    docker logs "${project_name}-server"
    exit
  fi
  if [ "$2" == "db" ]; then
    docker logs "${project_name}-db"
    exit
  fi

  echo "Unknown command! Exit...";
  exit
fi
if [ "$1" == "cert" ]; then
  if [ "$#" -eq 1 ]; then
    echo "### Certificate HELP: "
    echo "  upsert  - create or update certificates"
    echo "  skip    - skip certificate creation and restart containers"
    echo "  delete  - delete certificates"
    exit
  fi

  if [ "$2" == "upsert" ]; then
    for domain in ${domains[@]}; do
      domain_name=$(echo $domain | grep -o -P $regex)
      if [ -d "$data_path/conf/live/$domain_name" ]; then
        echo "### Old certificates removed!"
        rm -rf "$data_path"
        echo "### The process of creating new certificates has been started..."
      fi
    done
    export INIT=1
    certificateBuilder
    export INIT=0
    echo "### Restart nginx... ###"
    docker compose up -d nginx && docker compose restart nginx
    exit
  fi
  if [ "$2" == "skip" ]; then
    for domain in ${domains[@]}; do
      domain_name=$(echo $domain | grep -o -P $regex)
      if [ ! -d "$data_path/conf/live/$domain_name" ]; then
        echo "### No certificates were found. First, create them!"
        exit
      fi
    done
    certificateBuilder
    exit
  fi
  if [ "$2" == "delete" ]; then
    for domain in ${domains[@]}; do
      domain_name=$(echo $domain | grep -o -P $regex)
      if [ -d "$data_path/conf/live/$domain_name" ]; then
        echo "### Certificates removed! Exit..."
        rm -rf "$data_path"
      else
        echo "### No certificates were found. First, create them!"
      fi
    done
    exit
  fi

  echo "Unknown command! Exit...";
  exit
fi
