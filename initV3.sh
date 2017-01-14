#!/bin/bash
NODES=3
GIT_CLONE="git clone https://github.com/3l3ktr0/CloudHP.git cloudHP"

##MODIFY THIS TO CONFORM WITH YOUR OPENSTACK INSTALLATION##
FLAVOR="m1.small"
#IMAGE="ubuntu1404"
NETWORK="my-private-network"
SSH_USER="ubuntu"

help() {
  echo "Usage: init.sh -f <OPENRC file> [-n <Number of instances>] [-h (Help)] [-p (Parallel)]"
  echo "Parallel mode creates many VM instances at the same time. Faster, but maybe less reliable..."
}

#Parse args
SOURCE=
PARALLEL=0
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
    "-p" )
    PARALLEL=1
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
echo "---STEP 2: Installing requirements (python and jq)---"
sudo apt-get update
sudo apt-get install -y python3-pip jq
pip3 install python-novaclient python-heatclient
echo "---STEP 2: DONE---"

echo "---STEP 3: Creating Docker security group---"
if ! nova secgroup-list | grep -q 'docker-secgroup'; then
  nova secgroup-create docker-secgroup "Groupe de sécurité pour Docker Swarm"
  nova secgroup-add-group-rule docker-secgroup default tcp 1 65535 #Allow all from bastion
  nova secgroup-add-group-rule docker-secgroup default udp 1 65535
  #The following rules are for enabling swarm communications
  nova secgroup-add-group-rule docker-secgroup docker-secgroup tcp 2377 2377
  nova secgroup-add-group-rule docker-secgroup docker-secgroup tcp 7946 7946
  nova secgroup-add-group-rule docker-secgroup docker-secgroup udp 7946 7946
  nova secgroup-add-group-rule docker-secgroup docker-secgroup tcp 4789 4789
  nova secgroup-add-group-rule docker-secgroup docker-secgroup udp 4789 4789
  nova secgroup-add-rule docker-secgroup tcp 80 80 0.0.0.0/0 #Allow connection to webserver from outside
fi
echo "---STEP 3: DONE---"

#Install Docker-machine on Bastion VM
echo "---STEP 4: Installing Docker-machine---"
curl -L https://github.com/docker/machine/releases/download/v0.9.0-rc2/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine \
&& chmod +x /tmp/docker-machine \
&& sudo cp /tmp/docker-machine /usr/bin/docker-machine
echo "---STEP 4: DONE---"

echo "---STEP 5: Creating Docker snapshot image---"
#Create instance with Docker and Rex-Ray preinstalled
stack_name=docker-stack-$(uuidgen)
heat stack-create $stack_name -f heat_test/test2.yaml \
-P "openstack_auth=$OS_AUTH_URL;openstack_user=$OS_USERNAME;openstack_pwd=$OS_PASSWORD;openstack_tenant=$OS_TENANT_ID;openstack_region=$OS_REGION_NAME"

#Wait until image creation is complete (poll every minute)
echo "Waiting for stack creation to complete (estimated duration: 10 to 15 minutes)..."
until heat stack-show $stack_name | grep -m 1 status | grep -q "CREATE_COMPLETE"
do
  sleep 60
done

#Retrieve output values
instance_name=$(heat output-show $stack_name instance_name)
#Snapshot the instance
snapshot_name=docker-snapshot-$(uuidgen)
openstack server stop $instance_name
nova image-create --poll $instance_name $snapshot_name
openstack server delete $instance_name
heat stack-delete -y $stack_name
echo "---STEP 5: DONE---"

#Use docker-machine to create VM instances with Docker
#Done in parallel if -p given as parameter. Maybe less reliable (e.g apt update error)
echo "---STEP 6: Creating $NODES instances with Docker---"
echo "---STEP 6 Estimated duration: 1 minute per instance---"
swarmkey=swarm-key-$(uuidgen)
openstack keypair create $swarmkey > $swarmkey.pem
for ((i=1; i <= $NODES; i++)); do
  uuids[$i]=$(uuidgen)
  if [[ $i -eq 1 ]]; then
    nodes[$i]=swarm-master-${uuids[$i]}
  else
    nodes[$i]=swarm-worker-${uuids[$i]}
  fi
  if [[ $PARALLEL -eq 1 ]]; then
    docker-machine create -d openstack --openstack-flavor-name="$FLAVOR" \
    --openstack-image-name="$snapshot_name" --openstack-keypair-name="$swarmkey"\
    --openstack-net-name="$NETWORK" --openstack-sec-groups="docker-secgroup" \
    --openstack-ssh-user="$SSH_USER" --openstack-private-key-file="./$swarmkey.pem" --openstack-insecure \
    ${nodes[$i]} >/dev/null &
    sleep 60
  else
    docker-machine create -d openstack --openstack-flavor-name="$FLAVOR" \
    --openstack-image-name="$snapshot_name" --openstack-keypair-name="$swarmkey"\
    --openstack-net-name="$NETWORK" --openstack-sec-groups="docker-secgroup" \
    --openstack-ssh-user="$SSH_USER" --openstack-private-key-file="./$swarmkey.pem" --openstack-insecure \
    ${nodes[$i]} >/dev/null
  fi
done
wait
echo "---STEP 6: DONE---"

#Initialize a Swarm
echo "---STEP 7: Initializing a Docker Swarm---"
MANAGER_IP="$(docker-machine ip ${nodes[1]})"
docker-machine ssh ${nodes[1]} "sudo docker swarm init --advertise-addr $MANAGER_IP"
#Retrieve swarm token
TOKEN="$(docker-machine ssh ${nodes[1]} 'sudo docker swarm join-token -q worker')"
echo "---STEP 7: DONE---"

#Add worker nodes to swarm
echo "---STEP 8: Adding worker instances to Swarm---"
for ((i=2; i <= $NODES; i++)); do
  cmd="sudo docker swarm join --token $TOKEN $MANAGER_IP:2377"
  docker-machine ssh ${nodes[$i]} "$cmd"
done
echo "---STEP 8: DONE---"

#Cloning repository on every instance
echo "---STEP 9: Cloning repository on the $NODES instances---"
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh ${nodes[$i]} "$GIT_CLONE" >/dev/null &
done
wait
echo "---STEP 9: DONE---"

#Create Swarm networking
echo "---STEP 10: Creating the Swarm networks---"
cmd="sudo docker network create -d overlay swarm_services && \
sudo docker network create -d overlay swarm_db_i && \
sudo docker network create -d overlay swarm_db_s && \
sudo docker network create -d overlay swarm_proxy"
docker-machine ssh ${nodes[1]} "$cmd"
echo "---STEP 10: DONE---"

#And finally, launch the services !
echo "---STEP 11: Starting services---"
# cmd="sudo docker service create --name web --network swarm_services,swarm_proxy cloudhp_webserver && \
# sudo docker service create --name db_i --network swarm_db_i \
# --mount type=volume,volume-driver=rexray,volume-opt=size=1,src=mysqldb_i,dst=/var/lib/mysql db_i && \
# sudo docker service create --name db_s --network swarm_db_s \
# --mount type=volume,volume-driver=rexray,volume-opt=size=1,src=mysqldb_s,dst=/var/lib/mysql db_s && \
# sudo docker service create --name i --network swarm_services,swarm_db_i cloudhp_i && \
# sudo docker service create --name s --network swarm_services,swarm_db_s cloudhp_s && \
# sudo docker service create --name b --network swarm_services cloudhp_b && \
# sudo docker service create --name haproxy -p 80:80 -p 8080:8080 --network swarm_proxy \
# -e MODE=swarm --constraint 'node.role == manager' vfarcic/docker-flow-proxy && \
# curl 'localhost:8080/v1/docker-flow-proxy/reconfigure?serviceName=web&servicePath=/&port=5000'"

# 'workaround' needed to get persistant Cinder storage to work... a better solution would be nice
# but we don't have much time anymore.
# We don't really need persistant storage for DB_I... so we don't use it.
cmd="sudo docker service create --name web --mode global --network swarm_services,swarm_proxy cloudhp_webserver && \
sudo docker service create --name db_i --network swarm_db_i db_i && \
sudo docker service create --name db_s --network swarm_db_s --constraint 'node.role == manager' \
--mount type=volume,volume-driver=rexray,volume-opt=size=1,src=mysqldb_s,dst=/var/lib/mysql db_s && \
sudo docker service create --name i --network swarm_services,swarm_db_i cloudhp_i && \
sudo docker service create --name s --network swarm_services,swarm_db_s cloudhp_s && \
sudo docker service create --name b --network swarm_services \
-e OS_AUTH_URL=$OS_AUTH_URL -e OS_USERNAME=$OS_USERNAME -e OS_TENANT_NAME=$OS_TENANT_NAME \
-e OS_PASSWORD=$OS_PASSWORD cloudhp_b && \
sudo docker service create --name p --network swarm_services \
-e OS_AUTH_URL=$OS_AUTH_URL -e OS_USERNAME=$OS_USERNAME -e OS_TENANT_NAME=$OS_TENANT_NAME \
-e OS_PASSWORD=$OS_PASSWORD cloudhp_p && \
sudo docker service create --name haproxy -p 80:80 -p 8080:8080 --network swarm_proxy \
-e MODE=swarm --constraint 'node.role == manager' vfarcic/docker-flow-proxy && \
sleep 10 && curl 'localhost:8080/v1/docker-flow-proxy/reconfigure?serviceName=web&servicePath=/&port=5000'"

#'Workaround' for a Cinder bug which gives a wrong device name (todo)
#journalctl -u rexray | grep -o -m 1 'open /dev/.*: no such file or directory' | cut -d: -f1 | cut -c6-
#readlink -f /dev/disk/by-id/*
#si différent, sudo mv pour le bon

#Execute commands remotely on manager
docker-machine ssh ${nodes[1]} "$cmd"
echo "---STEP 11: DONE---"

echo "---STEP 12: Allocating and associating floating IP---"
pubip=$(openstack floating ip create -f json external-network | jq .floating_ip_address | sed 's/"//g')
openstack server add floating ip ${nodes[1]} $pubip
echo "---step 12: DONE---"

echo "---Application deployed succesfully !---"
echo "---Launch it by going to http://$pubip/index.html?id=<ID> on your browser---"
echo "---Consider waiting 2-3 minutes to let DBs init processes finish---"
