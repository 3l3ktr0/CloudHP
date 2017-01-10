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
    if [[ ($2 =~ ^[0-9]+$) && $2 -gt 1 ]]; then
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

echo "---STEP 3: Creating Docker security group---"
nova secgroup-create docker-secgroup "Groupe de sécurité pour Docker Swarm"
nova secgroup-add-group-rule docker-secgroup default tcp 22 22 #Allow SSH from bastion
#The following rules are for enabling swarm communications
nova secgroup-add-group-rule docker-secgroup docker-secgroup tcp 7946 7946
nova secgroup-add-group-rule docker-secgroup docker-secgroup udp 7946 7946
nova secgroup-add-group-rule docker-secgroup docker-secgroup tcp 4789 4789
nova secgroup-add-group-rule docker-secgroup docker-secgroup udp 4789 4789
nova secgroup-add-rule docker-secgroup tcp 80 80 0.0.0.0/0 #Allow connection to webserver from outside
echo "---STEP 3: DONE---"

#Install Docker on Bastion VM (not necessary anymore)
# echo "---STEP 4: Installing Docker---"
# echo "---STEP 4 Estimated duration: < 5 minutes---"
# curl -sSL https://get.docker.com/ | sh
# echo "---STEP 4: DONE---"

#Install Docker-machine on Bastion VM
echo "---STEP 3: Installing Docker-machine---"
curl -L https://github.com/docker/machine/releases/download/v0.9.0-rc2/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine \
&& chmod +x /tmp/docker-machine \
&& sudo cp /tmp/docker-machine /usr/bin/docker-machine
echo "---STEP 3: DONE---"

#Use docker-machine to create VM instances with Docker
#Done in parallel
#TODO:parameters
echo "---STEP 4: Creating $NODES instances with Docker---"
echo "---STEP 4 Estimated duration: 5 to 10 minutes---"
for ((i=1; i <= $NODES; i++)); do
  uuids[$i]=$(uuidgen)
  if [[ $i -eq 1 ]]; then
    nodes[$i]=swarm-master-${uuids[$i]}
  else
    nodes[$i]=swarm-worker-${uuids[$i]}
  fi
  sleep 10
  docker-machine create -d openstack --openstack-flavor-name="m1.small" \
  --openstack-image-name="ubuntu1404" --openstack-keypair-name="TP_Cloud_maxime"\
  --openstack-net-name="my-private-network" --openstack-sec-groups="docker-secgroup" \
  --openstack-ssh-user="ubuntu" --openstack-private-key-file="./cloud.key" --openstack-insecure \
  ${nodes[$i]} >/dev/null &
  sleep 10
done
wait
echo "---STEP 4: DONE---"

#Initialize a Swarm
echo "---STEP 5: Initializing a Docker Swarm---"
MANAGER_IP="$(docker-machine ip ${nodes[1]})"
docker-machine ssh ${nodes[1]} "docker swarm init --advertise-addr $MANAGER_IP"
#Retrieve swarm token
TOKEN="$(docker-machine ssh ${nodes[1]} 'sudo docker swarm join-token -q worker')"
echo "---STEP 5: DONE---"

#Add worker nodes to swarm
echo "---STEP 6: Adding worker instances to Swarm---"
for ((i=2; i <= $NODES; i++)); do
  #eval "$(docker-machine env swarm-${uuids[$i]})"
  cmd="sudo docker swarm join --token $TOKEN $MANAGER_IP:2377"
  docker-machine ssh ${nodes[$i]} "$cmd"
done
echo "---STEP 6: DONE---"
#eval "$(docker-machine env -u)"

#Cloning repository on every instance
echo "---STEP 7: Cloning repository on the $NODES instances---"
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh ${nodes[$i]} "$GIT_CLONE" >/dev/null &
done
wait
echo "---STEP 7: DONE---"

#Build the Docker images on every instance
#(add other services when ready)
echo "---STEP 8: Build Docker images on every host---"
echo "---STEP 8 Estimated duration: about 5 minutes---"
cmd="sudo docker build ./webserver -t cloudhp_webserver && \
sudo docker build ./db_i -t db_i && \
sudo docker build ./db_s -t db_s && \
sudo docker build ./microservices/i -t cloudhp_i && \
sudo docker build ./microservices/s -t cloudhp_s"
eval "$cmd" &
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh ${nodes[$i]} "cd ./cloudHP && $cmd" >/dev/null &
done
wait
echo "---STEP 8: DONE---"

# #Create Swarm networking
echo "---STEP 9: Creating the Swarm networks---"
cmd1="sudo docker network create -d overlay swarm_services && \
sudo docker network create -d overlay swarm_db_i && \
sudo docker network create -d overlay swarm_db_s && \
sudo docker network create -d overlay swarm_proxy"
echo "---STEP 9: DONE---"

#And finally, launch the services !
echo "---STEP 10: Starting services---"
cmd2="sudo docker service create --name web -p 80:5000 --network swarm_services cloudhp_webserver && \
sudo docker service create --name db_i --network swarm_db_i db_i && \
sudo docker service create --name db_s --network swarm_db_s \
--constraint 'node.hostname == ${nodes[2]}' --mount type=volume,src=mysqldata,dst=/var/lib/mysql db_s && \
sudo docker service create --name i --network swarm_services,swarm_db_i cloudhp_i && \
sudo docker service create --name s --network swarm_services,swarm_db_s cloudhp_s && \
sudo docker service create --name haproxy -p 80:80 -p 8080:8080 --network swarm_proxy \
-e MODE=swarm --constraint 'node.role == manager' vfarcic/docker-flow-proxy && \
curl 'localhost:8080/v1/docker-flow-proxy/reconfigure?serviceName=web&servicePath=/&port=5000'"

#Execute commands remotely on manager
docker-machine ssh ${nodes[1]} "$cmd1 && $cmd2"
echo "---STEP 10: DONE---"


echo "---Application deployed succesfully !---"
echo "---Launch it by going to http://$MANAGER_IP on your browser---"
echo "---Consider waiting 1-2 minutes to let DBs init processes finish---"
