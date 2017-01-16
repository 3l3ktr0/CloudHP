#!/bin/bash
for node in $(docker-machine ls -q --filter state=Running)
do
  docker-machine ssh $node << EOF &
    cd ./cloudHP
    git pull
    sudo docker build ./webserver -t cloudhp_webserver
    sudo docker build ./microservices -t b_p_common
    sudo docker build ./db_i -t db_i
    sudo docker build ./db_s -t db_s
    sudo docker build ./microservices/i -t cloudhp_i
    sudo docker build ./microservices/b -t cloudhp_b
    sudo docker build ./microservices/p -t cloudhp_p
    sudo docker build ./microservices/s -t cloudhp_s
    wait
    #perform some cleanup
    sudo docker rm -v $(docker ps -a -q -f status=exited)
    sudo docker rmi $(docker images -f "dangling=true" -q)
EOF
done
wait

for node in $(docker-machine ls -q --filter name=swarm-master-.*)
do
  docker-machine ssh $node << EOF &
    cd ./cloudHP
    sudo docker service rm \$(sudo docker service list -q)

    sudo docker service create --name db_i --replicas 2 --network swarm_db_i db_i
    sudo docker service create --name db_s --network swarm_db_s
    --constraint "node.hostname == ${nodes[1]}" \
    --mount type=volume,volume-driver=rexray,volume-opt=size=1,src=mysqldb,dst=/var/lib/mysql db_s
    sudo docker service create --name i --network swarm_services,swarm_db_i cloudhp_i
    sudo docker service create --name s --network swarm_services,swarm_db_s cloudhp_s
    sudo docker service create --name w --network swarm_services \
    --constraint 'node.role != manager' --replicas $WORKERS cloudhp_w
    sudo docker service create --name b --network swarm_services, swarm_db_s \
    -e OS_AUTH_URL=$OS_AUTH_URL -e OS_USERNAME=$OS_USERNAME -e OS_TENANT_NAME=$OS_TENANT_NAME \
    -e OS_PASSWORD=$OS_PASSWORD cloudhp_b
    sudo docker service create --name p --network swarm_services \
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
    --label com.df.port=5000 cloudhp_webserver
EOF
done
wait
