#!/bin/sh
#Install Docker
sudo curl -sSL https://get.docker.com/ | sh
sudo sh -c 'curl -L https://github.com/docker/compose/releases/download/1.9.0/docker-compose-`uname -s`-`uname -m` > /usr/bin/docker-compose'

#Clone repo in ~ dir
cd
git clone https://github.com/3l3ktr0/CloudHP.git CloudHP

case "$service" in
   "i" ) COMPOSE_DIR=./CloudHP/microservices/i
   ;;
   "s" ) COMPOSE_DIR=./CloudHP/microservices/s
   ;;
   "db-i" ) COMPOSE_DIR=./CloudHP/db-i
   ;;
   "db-s" ) COMPOSE_DIR=./CloudHP/db-s
   ;;
   "webpage" ) COMPOSE_DIR=./CloudHP/webserver
   ;;
esac
sudo docker-compose up -f "$COMPOSE_DIR"
