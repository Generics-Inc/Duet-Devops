if [ "$#" -eq 0 ];
  then
  echo "HELP:"
  echo "init - first initial project"
  echo "start - up all containers"
  echo "db push - run db initialize"
  echo "db migration - run db migration"
  echo "db seed - run upload seed to db"
  echo "restart - restart docker containers"
  echo "rebuild nginx - rebuild only nginx container"
  echo "rebuild server - rebuild only server container"
  echo "rebuild full - rebuild full app with remove db volume"
  echo "logs nginx - nginx container logs"
  echo "logs server - server container logs"
  echo "logs db - db container logs"
fi

set -a
source .env
set +a
env

PROJECT_NAME="${PROJECT_NAME:-build}"

cleanNone() {
  images=$(docker images --filter "dangling=true" -q --no-trunc);

  if [ -n "$images" ]; then
      docker rmi $images
  else
      echo "There are no images to clean up";
  fi
}

if [ "$1" == "init" ];
  then
  docker compose up -d
  docker exec -d ${PROJECT_NAME}-server npm run db:push
  docker exec -d ${PROJECT_NAME}-server npm run db:seed

fi
if [ "$1" == "start" ];
  then
  docker compose up -d
fi
if [ "$1" == "restart" ];
  then
  docker compose restart
fi
if [ "$1" == "db" ];
  then
  if [ "$2" == "push" ];
    then
    docker exec -d ${PROJECT_NAME}-server npm run db:push
  fi
  if [ "$2" == "migration" ];
    then
    docker exec -d ${PROJECT_NAME}-server npm run db:migration
  fi
  if [ "$2" == "seed" ];
    then
    docker exec -d ${PROJECT_NAME}-server npm run db:seed
  fi

fi
if [ "$1" == "rebuild" ];
  then
  if [ "$2" == "nginx" ];
    then
    docker compose restart nginx
  fi
  if [ "$2" == "server" ];
    then
    docker compose build server
    docker compose up -d server
  fi
  if [ "$2" == "soft" ];
    then
    docker compose down
    docker rmi ${PROJECT_NAME}-server
    docker rmi ${PROJECT_NAME}-client
    docker compose up -d
  fi
  if [ "$2" == "full" ];
    then
    docker compose down
    docker rmi ${PROJECT_NAME}-server
    docker rmi ${PROJECT_NAME}-client
    docker volume rm ${PROJECT_NAME}-db
    docker compose up -d
  fi
fi
if [ "$1" == "logs" ];
  then
  if [ "$2" == "nginx" ];
    then
    docker logs ${PROJECT_NAME}-nginx
  fi
  if [ "$2" == "server" ];
    then
    docker logs ${PROJECT_NAME}-server
  fi
  if [ "$2" == "db" ];
    then
    docker logs ${PROJECT_NAME}-db
  fi
fi
if [ "$1" == "clean" ];
  then
  cleanNone
fi
