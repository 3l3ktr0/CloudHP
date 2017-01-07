#!/bin/bash
NODES=3
GIT_CLONE="git clone https://github.com/3l3ktr0/CloudHP.git cloudHP"

help() {
  echo "Usage: init.sh -f <OPENRC file> [-n <Number of instances>] [-h (Help)]"
}

#Parse args
SOURCE=
while [[ "$#" -ne 0 ]]; do
  case "$1" in
    "-f" )
    if [[ -f "$2" ]]; then
      SOURCE="$2"
      shift
    else
      echo "Provide a valid OpenStack OPENRC file to init deployment"
      help
      exit 1
    fi
    ;;
    "-n" )
    if [[ $2 =~ ^[0-9]+$ ]]; then
      NODES=$2
      shift
    else
      echo "Argument to -n must be a number !"
      help
      exit 1
    fi
    ;;
    "-h" )
    help
    ;;
    *)
    echo "Invalid parameters"
    help
    exit 1
    ;;
  esac
  shift
done

if [[ -z $SOURCE ]]; then
  echo "Provide a valid OpenStack OPENRC file to init deployment"
  help
  exit 1
fi

echo "---STEP 1: OpenStack credentials---"
. "$SOURCE"
cd "$(dirname "$(realpath "$0")")";
echo "---STEP 1: DONE---"

#Install python3-pip and python-openstackclient
echo "---STEP 2: Installing python requirements---"
sudo apt-get update
sudo apt-get install -y python3-pip
pip3 install python-openstackclient
echo "---STEP 2: DONE---"

#Add TCP 80:80 rule to allow connection on the webserver (on bastion for now)
echo "---STEP 3: Allowing HTTP connection from outside---"
nova secgroup-add-rule default tcp 80 80 0.0.0.0/0
echo "---STEP 3: DONE---"

#Install Docker on Bastion VM
echo "---STEP 4: Installing Docker---"
echo "---STEP 4 Estimated duration: < 5 minutes---"
curl -sSL https://get.docker.com/ | sh
echo "---STEP 4: DONE---"
#Install Docker-machine on Bastion VM
echo "---STEP 5: Installing Docker-machine---"
curl -L https://github.com/docker/machine/releases/download/v0.9.0-rc2/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine \
&& chmod +x /tmp/docker-machine \
&& sudo cp /tmp/docker-machine /usr/bin/docker-machine
echo "---STEP 5: DONE---"

#Use docker-machine to create VM instances with Docker
#Done in parallel
#TODO:parameters
echo "---STEP 6: Creating $NODES instances with Docker---"
echo "---STEP 6 Estimated duration: 5 to 10 minutes---"
for ((i=1; i <= $NODES; i++)); do
  uuids[$i]=$(uuidgen)
  sleep 5
  docker-machine create -d openstack --openstack-flavor-name="m1.small" \
  --openstack-image-name="ubuntu1404" --openstack-keypair-name="TP_Cloud_maxime"\
  --openstack-net-name="my-private-network" --openstack-sec-groups="default" \
  --openstack-ssh-user="ubuntu" --openstack-private-key-file="./cloud.key" --openstack-insecure \
  swarm-${uuids[$i]} >/dev/null &
  sleep 5
done
wait
echo "---STEP 6: DONE---"

#Initialize a Swarm
echo "---STEP 6: Initializing a Docker Swarm---"
BASTION_IP="$(ifconfig | grep -A 1 'ens3' | tail -1 | cut -d ':' -f 2 | cut -d ' ' -f 1)"
sudo docker swarm init --advertise-addr $BASTION_IP
#Retrieve swarm token
TOKEN="$(sudo docker swarm join-token -q worker)"
echo "---STEP 6: DONE---"

#Add worker nodes to swarm
echo "---STEP 7: Adding $NODES instances to Swarm---"
for ((i=1; i <= $NODES; i++)); do
  #eval "$(docker-machine env swarm-${uuids[$i]})"
  cmd="sudo docker swarm join --token $TOKEN $BASTION_IP:2377"
  docker-machine ssh swarm-${uuids[$i]} "$cmd"
done
echo "---STEP 7: DONE---"
#eval "$(docker-machine env -u)"

#Cloning repository on every instance
echo "---STEP 8: Cloning repository on the $NODES instances---"
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh swarm-${uuids[$i]} "$GIT_CLONE && cd ./cloudHP && git checkout heat_test" >/dev/null &
done
wait
echo "---STEP 8: DONE---"

#Build the Docker images on every host (including Bastion)
#(add other services when ready)
echo "---STEP 9: Build Docker images on every host---"
echo "---STEP 9 Estimated duration: about 5 minutes---"
cmd="sudo docker build ./webserver -t cloudhp_webserver && \
sudo docker build ./db_i -t db_i && \
sudo docker build ./db_s -t db_s && \
sudo docker build ./microservices/i -t cloudhp_i && \
sudo docker build ./microservices/s -t cloudhp_s"
eval "$cmd" &
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh swarm-${uuids[$i]} "cd ./cloudHP && $cmd" >/dev/null &
done
wait
echo "---STEP 9: DONE---"

#Create Swarm networking
echo "---STEP 10: Creating the Swarm networks---"
sudo docker network create -d overlay swarm_services #for (i,s,b,w,p,web)
sudo docker network create -d overlay swarm_db_i #for (i, db_i)
sudo docker network create -d overlay swarm_db_s #for (s, db_s)
echo "---STEP 10: DONE---"

#And finally, launch the services !
echo "---STEP 11: Starting services---"
sudo docker service create --name web -p 80:5000 --network swarm_services \
--constraint 'node.role == manager' cloudhp_webserver
sudo docker service create --name db_i --network swarm_db_i db_i
sudo docker service create --name db_s --network swarm_db_s db_s
sudo docker service create --name i --network swarm_services,swarm_db_i cloudhp_i
sudo docker service create --name s --network swarm_services,swarm_db_s cloudhp_s
echo "---STEP 11: DONE---"

echo "---Application deployed succesfully !---"
echo "---Launch it by going to http://$BASTION_IP on your browser---"
echo "---Consider waiting 1-2 minutes to let DBs init processes finish---"
