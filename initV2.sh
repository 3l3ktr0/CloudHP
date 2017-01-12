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
echo "---STEP 2: Installing requirements (python and jq)---"
sudo apt-get update
sudo apt-get install -y python3-pip jq
pip3 install python-openstackclient
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

#Use docker-machine to create VM instances with Docker
#Done in parallel
#TODO:parameters
echo "---STEP 5: Creating $NODES instances with Docker---"
echo "---STEP 5 Estimated duration: 5 to 10 minutes---"
swarmkey=swarm-key-$(uuidgen)
openstack keypair create $swarmkey > $swarmkey.pem
for ((i=1; i <= $NODES; i++)); do
  uuids[$i]=$(uuidgen)
  if [[ $i -eq 1 ]]; then
    nodes[$i]=swarm-master-${uuids[$i]}
  else
    nodes[$i]=swarm-worker-${uuids[$i]}
  fi
  docker-machine create -d openstack --openstack-flavor-name="m1.small" \
  --openstack-image-name="ubuntu1404" --openstack-keypair-name="$swarmkey"\
  --openstack-net-name="my-private-network" --openstack-sec-groups="docker-secgroup" \
  --openstack-ssh-user="ubuntu" --openstack-private-key-file="./$swarmkey.pem" --openstack-insecure \
  ${nodes[$i]} >/dev/null &
  sleep 60
done
wait
echo "---STEP 5: DONE---"

#Initialize a Swarm
echo "---STEP 6: Initializing a Docker Swarm---"
MANAGER_IP="$(docker-machine ip ${nodes[1]})"
docker-machine ssh ${nodes[1]} "sudo docker swarm init --advertise-addr $MANAGER_IP"
#Retrieve swarm token
TOKEN="$(docker-machine ssh ${nodes[1]} 'sudo docker swarm join-token -q worker')"
echo "---STEP 6: DONE---"

#Add worker nodes to swarm
echo "---STEP 7: Adding worker instances to Swarm---"
for ((i=2; i <= $NODES; i++)); do
  cmd="sudo docker swarm join --token $TOKEN $MANAGER_IP:2377"
  docker-machine ssh ${nodes[$i]} "$cmd"
done
echo "---STEP 7: DONE---"

#Cloning repository on every instance
echo "---STEP 8: Cloning repository on the $NODES instances---"
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh ${nodes[$i]} "$GIT_CLONE" >/dev/null &
done
wait
echo "---STEP 8: DONE---"

echo "---STEP 9: Installing REX-Ray on the $NODES instances---"
cat << EOF > /tmp/config.yml
rexray:
  storageDrivers:
    - openstack
volume:
  mount:
    prempt: true
openstack:
  authUrl: $OS_AUTH_URL
  username: $OS_USERNAME
  password: $OS_PASSWORD
  tenantID: $OS_TENANT_ID
  regionName: $OS_REGION_NAME
EOF
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh ${nodes[$i]} 'curl -sSL https://dl.bintray.com/emccode/rexray/install | sh -s -- stable 0.3.3'
  docker-machine scp /tmp/config.yml ${nodes[$i]}:/tmp/config.yml
  docker-machine ssh ${nodes[$i]} 'sudo cp /tmp/config.yml /etc/rexray/config.yml && sudo service rexray start'
done
echo "---STEP 9: DONE---"

#Build the Docker images on every instance
#(add other services when ready)
echo "---STEP 10: Build Docker images on every host---"
echo "---STEP 10 Estimated duration: about 5 minutes---"
cmd="sudo docker build ./webserver -t cloudhp_webserver && \
sudo docker build ./db_i -t db_i && \
sudo docker build ./db_s -t db_s && \
sudo docker build ./microservices/i -t cloudhp_i && \
sudo docker build ./microservices/b -t cloudhp_b && \
sudo docker build ./microservices/s -t cloudhp_s"
for ((i=1; i <= $NODES; i++)); do
  docker-machine ssh ${nodes[$i]} "cd ./cloudHP && $cmd" >/dev/null &
done
wait
echo "---STEP 10: DONE---"

# #Create Swarm networking
echo "---STEP 11: Creating the Swarm networks---"
cmd="sudo docker network create -d overlay swarm_services && \
sudo docker network create -d overlay swarm_db_i && \
sudo docker network create -d overlay swarm_db_s && \
sudo docker network create -d overlay swarm_proxy"
docker-machine ssh ${nodes[1]} "$cmd"
echo "---STEP 11: DONE---"

#And finally, launch the services !
echo "---STEP 12: Starting services---"
cmd="sudo docker service create --name web --network swarm_services,swarm_proxy cloudhp_webserver && \
sudo docker service create --name db_i --network swarm_db_i \
--mount type=volume,volume-driver=rexray,volume-opt=size=1,src=mysqldb_i,dst=/var/lib/mysql db_i && \
sudo docker service create --name db_s --network swarm_db_s \
--mount type=volume,volume-driver=rexray,volume-opt=size=1,src=mysqldb_s,dst=/var/lib/mysql db_s && \
sudo docker service create --name i --network swarm_services,swarm_db_i cloudhp_i && \
sudo docker service create --name s --network swarm_services,swarm_db_s cloudhp_s && \
sudo docker service create --name b --network swarm_services cloudhp_b && \
sudo docker service create --name haproxy -p 80:80 -p 8080:8080 --network swarm_proxy \
-e MODE=swarm --constraint 'node.role == manager' vfarcic/docker-flow-proxy && \
curl 'localhost:8080/v1/docker-flow-proxy/reconfigure?serviceName=web&servicePath=/&port=5000'"

#Execute commands remotely on manager
docker-machine ssh ${nodes[1]} "$cmd"
echo "---STEP 12: DONE---"

echo "---STEP 13: Allocating and associating floating IP---"
pubip=$(openstack floating ip create -f json external-network | jq .floating_ip_address | sed 's/"//g')
openstack server add floating ip ${nodes[1]} $pubip
echo "---step 13: DONE---"

echo "---Application deployed succesfully !---"
echo "---Launch it by going to http://$pubip/index.html?id=<ID> on your browser---"
echo "---Consider waiting 2-3 minutes to let DBs init processes finish---"
