#!/bin/bash
#Deployment script for the CloudHP Application
#This script :
# -installs software required to manage the Swarm nodes (Openstack client and docker-machine)
# -generates a snapshot with Docker installed and the app images built (build once, run anywhere :) )
# -makes a Docker Swarm (1.12) cluster based on hosts created with Docker-machine using the snapshot
#
#Requirements :
# -A Bastion VM, accessible from the outside with a floating IP.
# -An Openstack private network (replace the NETWORK variable below with yours !)
# -An Ubuntu-based image, tested with 1404, should work with 1604. Replace SSH_USER if necessary.
# -A V2 OPENRC file. Get yours at "Access and Security -> API Access" on the Openstack dashboard.
# -Basically, the requirements are the same steps we followed during the 2nd or 3rd lab session
#  to set up the Bastion VM.
#
#Estimated duration : 20 to 30 minutes (75% of the duration is taken up by Docker setup).
#Depends on the network performance (many things are downloaded from internet)
#and whether the Parallel mode (-p option) is enabled. It makes docker-machine
#stuff a bit faster, but behaves strangely (rather rarely though).
#
#How to use :
# -Check that every requirement is met.
# -SCP the V2 OPENRC file into your Bastion VM.
# -SSH into Bastion VM.
# -clone the project : git clone https://github.com/3l3ktr0/CloudHP.git cloudHP
# -execute the command : cd cloudHP && sudo chmod +x init.sh
# -execute the command : ./init.sh -f <OPENRC FILE> -m <Number of managers> -w <Number of workers> [-p]
# -Have a coffee or play video games or browse funny stuff online for 20-30 minutes :)

MANAGERS=1
WORKERS=3

GIT_CLONE="git clone https://github.com/3l3ktr0/CloudHP.git cloudHP"

############ MODIFY THIS TO CONFORM WITH YOUR OPENSTACK INSTALLATION #############
FLAVOR="m1.small"
NETWORK="my-private-network"
SSH_USER="ubuntu"

help() {
  echo "Usage: init.sh -f <OPENRC file> [-m] [-w] [-p] [-h]"
  echo "-p: Parallel mode creates many VM instances at the same time. Faster, but maybe less reliable..."
  echo "-m: Number of manager nodes. Must be odd to perform leader election"
  echo "-w: Number of worker nodes."
  echo "-h: Print this help"
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
    "-w" )
    if [[ ($2 =~ ^[0-9]+$) && $2 -gt 1 ]]; then
      WORKERS=$2
      shift
    else
      echo "Argument to -n must be a number !"
      help
      exit 1
    fi
    ;;
    "-m" )
    if [[ ($2 =~ ^[0-9]+$) && $(($2 % 2)) -eq 1 ]]; then
      MANAGERS=$2
      shift
    else
      echo "Number of managers must be odd !"
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

NODES=$(($MANAGERS+$WORKERS))

echo "---STEP 1: OpenStack credentials---"
. "$SOURCE"
cd "$(dirname "$(realpath "$0")")";
echo "---STEP 1: DONE---"

#Install python3-pip and python-openstackclient
echo "---STEP 2: Installing requirements (python and jq)---"
sudo apt-get update
sudo apt-get install -y python3-pip jq
if ! which openstack >/dev/null; then
  pip3 install python-openstackclient python-heatclient
fi
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
if ! which docker-machine >/dev/null; then
  curl -L https://github.com/docker/machine/releases/download/v0.9.0-rc2/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine \
  && chmod +x /tmp/docker-machine \
  && sudo cp /tmp/docker-machine /usr/bin/docker-machine
fi
echo "---STEP 4: DONE---"

echo "---STEP 5: Creating Docker snapshot image---"
if openstack image list | grep -q -m 1 'docker-snapshotTEST'; then
  echo "Docker Snapshot found in image repository ! Using it..."
  #the command below retrieves the snapshot image name from the image list
  snapshot_name=$(openstack image list | grep -m 1 'docker-snapshot' | cut -d\| -f3 | tr -d ' ')
else
  #Create instance with Docker preinstalled
  stack_name=docker-stack-$(uuidgen)
  heat stack-create $stack_name -f heat_docker/installdocker.yaml
  #Wait until image creation is complete (poll every 30s)
  echo "Waiting for stack creation to complete (estimated duration: 10 to 20 minutes)..."
  until heat stack-show $stack_name 2>/dev/null | grep -m 1 status | grep -q "CREATE_COMPLETE"
  do
    sleep 30
  done
  #Retrieve output values
  instance_name=$(heat output-show $stack_name instance_name)
  #Snapshot the instance
  snapshot_name=docker-snapshot-$(uuidgen)
  openstack server stop $instance_name
  until openstack server list | grep $instance_name | grep -q "SHUTOFF"
  do
    sleep 10
  done
  nova image-create --poll $instance_name $snapshot_name
  #Cleanup
  sleep 10
  heat stack-delete -y $stack_name
fi
echo "---STEP 5: DONE---"

#Use docker-machine to create VM instances with Docker
#Done in parallel if -p given as parameter. Maybe less reliable (e.g apt update error)
echo "---STEP 6: Creating $NODES instances with Docker---"
echo "---STEP 6 Estimated duration: 2 minutes per instance (faster with -p)---"
swarmkey=swarm-key-$(uuidgen)
openstack keypair create $swarmkey > $swarmkey.pem
for ((i=1; i <= $NODES; i++)); do
  uuids[$i]=$(uuidgen)
  if [[ $i -eq 1 ]]; then
    nodes[$i]=swarm-master-${uuids[$i]}
  elif [[ $i -le $MANAGERS ]]; then
    nodes[$i]=swarm-manager-${uuids[$i]}
  else
    nodes[$i]=swarm-worker-${uuids[$i]}
  fi
  if [[ $PARALLEL -eq 1 ]]; then
    docker-machine create -d openstack --openstack-flavor-name="$FLAVOR" \
    --openstack-image-name="$snapshot_name" --openstack-keypair-name="$swarmkey"\
    --openstack-net-name="$NETWORK" --openstack-sec-groups="docker-secgroup" \
    --openstack-ssh-user="$SSH_USER" --openstack-private-key-file="./$swarmkey.pem" --openstack-insecure \
    ${nodes[$i]} &
    sleep 10
  else
    docker-machine create -d openstack --openstack-flavor-name="$FLAVOR" \
    --openstack-image-name="$snapshot_name" --openstack-keypair-name="$swarmkey"\
    --openstack-net-name="$NETWORK" --openstack-sec-groups="docker-secgroup" \
    --openstack-ssh-user="$SSH_USER" --openstack-private-key-file="./$swarmkey.pem" --openstack-insecure \
    ${nodes[$i]}
  fi
done
wait
echo "---STEP 6: DONE---"

#Initialize a Swarm
echo "---STEP 7: Initializing a Docker Swarm---"
MASTER_IP="$(docker-machine ip ${nodes[1]})"
docker-machine ssh ${nodes[1]} "sudo docker swarm init --advertise-addr $MASTER_IP"
#Retrieve swarm tokens
WORKER_TOKEN="$(docker-machine ssh ${nodes[1]} 'sudo docker swarm join-token -q worker')"
MANAGER_TOKEN="$(docker-machine ssh ${nodes[1]} 'sudo docker swarm join-token -q manager')"
echo "---STEP 7: DONE---"

#Add worker and manager nodes to swarm
echo "---STEP 8: Adding instances to Swarm---"
for ((i = 2; i <= $MANAGERS; i++)); do
  cmd="sudo docker swarm join --token $MANAGER_TOKEN $MASTER_IP:2377"
  docker-machine ssh ${nodes[$i]} "$cmd"
done
for ((i=1; i <= $WORKERS; i++)); do
  cmd="sudo docker swarm join --token $WORKER_TOKEN $MASTER_IP:2377"
  docker-machine ssh ${nodes[$MANAGERS + $i]} "$cmd"
done
echo "---STEP 8: DONE---"

echo "---STEP 9: Installing REX-Ray on the $NODES instances---"
cat << EOF > /tmp/config.yml
rexray:
  storageDrivers:
  - openstack
  volume:
    mount:
      preempt: true
    unmount:
      ignoreUsedCount: true
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
  docker-machine ssh ${nodes[$i]} << EOF
    sudo cp /tmp/config.yml /etc/rexray/config.yml
    sudo service rexray start
EOF
done
echo "---STEP 9: DONE---"


#Create Swarm networking
echo "---STEP 10: Creating the Swarm networks---"
docker-machine ssh ${nodes[1]} << EOF
  sudo docker network create -d overlay swarm_services
  sudo docker network create -d overlay swarm_db_i
  sudo docker network create -d overlay swarm_db_s
  sudo docker network create -d overlay swarm_proxy
EOF
echo "---STEP 10: DONE---"

# echo "---STEP 11: Building w image...---"
# for ((i = 1; i <= $WORKERS; i++)); do
#   docker-machine ssh ${nodes[$MANAGERS + $i]} << EOF &
#     cd ./cloudHP
#     sudo docker build ./microservices/w -t cloudhp_w
# EOF
# done
# wait
#echo "---STEP 11: DONE---"

#And finally, launch the services !
echo "---STEP 11: Starting services---"
docker-machine ssh ${nodes[1]} << EOF
  sudo docker service create --name db_i --replicas 2 --network swarm_db_i db_i
  sudo docker service create --name db_s --network swarm_db_s \
  --constraint "node.hostname == ${nodes[1]}" \
  --mount type=volume,volume-driver=rexray,volume-opt=size=1,src=mysqldb,dst=/var/lib/mysql db_s
  sudo docker service create --name i --replicas $WORKERS --network swarm_services,swarm_db_i cloudhp_i
  sudo docker service create --name s --replicas $WORKERS --network swarm_services,swarm_db_s cloudhp_s
  sudo docker service create --name w --network swarm_services \
  --constraint 'node.role != manager' --replicas $WORKERS cloudhp_w
  sudo docker service create --name b --replicas $WORKERS --network swarm_services,swarm_db_s \
  -e OS_AUTH_URL=$OS_AUTH_URL -e OS_USERNAME=$OS_USERNAME -e OS_TENANT_NAME=$OS_TENANT_NAME \
  -e OS_PASSWORD=$OS_PASSWORD cloudhp_b
  sudo docker service create --name p --replicas $WORKERS --network swarm_services \
  -e OS_AUTH_URL=$OS_AUTH_URL -e OS_USERNAME=$OS_USERNAME -e OS_TENANT_NAME=$OS_TENANT_NAME \
  -e OS_PASSWORD=$OS_PASSWORD cloudhp_p

  sudo docker service create --name swarm-listener --network swarm_proxy \
  --mount "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock" \
  -e DF_NOTIF_CREATE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/reconfigure \
  -e DF_NOTIF_REMOVE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/remove \
  --constraint 'node.role == manager' vfarcic/docker-flow-swarm-listener

  sudo docker service create --name proxy -p 80:80 --network swarm_proxy \
  -e MODE=swarm -e LISTENER_ADDRESS=swarm-listener \
  --replicas $MANAGERS --constraint 'node.role == manager' vfarcic/docker-flow-proxy

  sudo docker service create --name web --mode global --network swarm_services,swarm_proxy \
  --label com.df.notify=true --label com.df.distribute=true --label com.df.servicePath=/ \
  --label com.df.port=80 cloudhp_webserver
EOF

#'Workaround' for a Cinder bug which gives a wrong device name
docker-machine ssh ${nodes[1]} << EOF
  dir_in_cinder=\$(journalctl -u rexray|grep -o -m 1 'open /dev/.*: no such file or directory'|cut -d: -f1|cut -c6-)
  actual_dir=\$(readlink -f /dev/disk/by-id/*)
  if [[ "\$dir_in_cinder" != "\$actual_dir" ]]; then
    sudo cp actual_dir dir_in_cinder
  fi
EOF
echo "---STEP 11: DONE---"

echo "---STEP 12: Allocating and associating floating IPs to manager nodes---"
for (( i = 1; i <= $MANAGERS; i++ )); do
  pubip[$i]=$(openstack floating ip create -f json external-network | jq .floating_ip_address | sed 's/"//g')
  openstack server add floating ip ${nodes[$i]} ${pubip[$i]}
done
echo "---step 12: DONE---"

echo "---Application deployed succesfully !---"
echo "---Launch it by going to http://${pubip[1]}/index.html?id=<ID> on your browser---"
for (( i = 2; i <= $MANAGERS; i++ )); do
  echo "Or at the address : http://${pubip[$i]}/index.html?id=<ID>"
done
echo "---Consider waiting 2 to 5 minutes to let DBs init processes finish---"
