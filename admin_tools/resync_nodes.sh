#!/bin/bash
for node in $(docker-machine ls -q --filter state=Running)
do
  docker-machine ssh $node << EOF &
    cd ./cloudHP
    sudo git pull
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
    sudo docker rm -v $(sudo docker ps -a -q -f status=exited)
    sudo docker rmi $(sudo docker images -f "dangling=true" -q)
EOF
done
wait

for node in $(docker-machine ls -q --filter name=swarm-master-.*)
do
  docker-machine ssh $node << EOF &
    cd ./cloudHP
    sudo docker service update --image cloudhp_webserver:latest web
    sudo docker service update --image cloudhp_i:latest i
    sudo docker service update --image cloudhp_s:latest s
    sudo docker service update --image cloudhp_b:latest b
    sudo docker service update --image cloudhp_p:latest p
    sudo docker service update --image db_i:latest db_i
    sudo docker service update --image db_s:latest db_s
EOF
done
wait
