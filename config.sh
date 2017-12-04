#!/bin/bash
#------------------------------------------------------------
# Script: config.sh
# Author: Swift@IBM
# -----------------------------------------------------------

set -e

VERSION="1.0"
BUILD_DIR=".build-linux"
BRIDGE_APP_NAME="containerbridge"
DATABASE_NAME="TodoListCloudantDatabase"
REGISTRY_URL="registry.eu-gb.bluemix.net"
DATABASE_TYPE="cloudantNoSQLDB"
DATABASE_LEVEL="Lite"
INSTANCE_NAME="todolist-couchdb"
NAME_SPACE="todolist_space"
LOGIN_URL="api.eu-gb.bluemix.net"

function help {
    cat <<-!!EOF
    Usage: $CMD [ build | run | push-docker ] [arguments...]
    Where:
    install_tools                                   Installs necessary tools for config, like Cloud Foundry CLI
    login                                           Logs into Bluemix and Container APIs
    setup <clusterName>                             Sets up the clusters
    build <dockerName>                              Builds Docker container from Dockerfile
    run <dockerName>                                Runs Docker container, ensuring it was built properly
    stop <dockerName>                               Stops Docker container, if running
    push <dockerName>                               Tags and pushes Docker container to IBM Cloud
    create_db <clusterName> <instanceName>          Creates database service
    get_ip <clusterName> <instanceName>             Get the public IP
    deploy <appName> <instanceName>                 Binds everything together (app, db, container) through container group
    populate_db <appURL> <username> <password>      Populates database with initial data
    delete <clusterName> <instanceName>             Delete the created service and cluster if possible
    all <clusterName> <instanceName>                Combines all necessary commands to deploy an app to IBM Cloud in a Docker container.
!!EOF
}

install_tools () {
    curl -sL https://ibm.biz/idt-installer | bash
    bx plugin install container-service -r Bluemix
}

login () {
    echo "Setting api and login tools."
    bx login -a $LOGIN_URL
    bx target --cf
}

setup () {
    if [ -z "$1" ]
    then
        echo "Error: setup failed, cluster name not provided."
        return
    fi

    bx cr login
    bx cs cluster-create --name $1
    bx cr namespace-add $NAME_SPACE
    bx cs workers $1
    bx cs cluster-config $1 --export
}

build_docker () {
    if [ -z "$1" ]
    then
        echo "Error: run failed, docker name not provided."
        return
    fi

    docker build -t $1 --force-rm .
}

run_docker () {
    if [ -z "$1" ]
    then
        echo "Error: run failed, docker name not provided."
        return
    fi

    docker run --name $1 -d -p 8080:8080 $1
}

stop_docker () {
    if [ -z "$1" ]
    then
        echo "Error: clean failed, docker name not provided."
        return
    fi

    docker rm -fv $1 || true
}

push_docker () {
    if [ -z "$1" ]
    then
        echo "Error: clean failed, docker name not provided."
        return
    fi

    bx cr login

    docker tag $1 $REGISTRY_URL/$NAME_SPACE/$1
    docker push $REGISTRY_URL/$NAME_SPACE/$1
    docker ps
    bx cr images
}

deploy_container () {
    if [ -z "$1" ] || [ -z "$2" ]
    then
        echo "Error: Deploying container failed, app name and service instance name not provided."
        return
    fi

    kubectl run $1 --image=$REGISTRY_URL/$NAME_SPACE/$2
}

create_database () {
    if [ -z "$1" ] || [ -z "$2" ]
    then
        echo "Error: Creating bridge application failed, cluster name and service instance name not provided."
        return
    fi

    bx service create cloudantNoSQLDB Lite $2
    bx cs cluster-service-bind $1 $NAME_SPACE $2
}

get_ip () {
    if [ -z "$1" ] || [ -z "$2" ]
    then
        echo "Error: Getting IP failed, cluster name and service instance name not provided."
        return
    fi

    ip_addr=$(bx cs workers $1 | grep normal | awk '{ print $1 }')
    port=$(kubectl get services | grep $2 | sed 's/.*:\([0-9]*\).*/\1/g')
    echo "You may view the application at: http://$ip_addr:$port"
}

populate_db () {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
    then
        echo "Error: Could not populate db with sample data. App URL, username, and password not provided."
        return
    fi

    curl -u $2:$3 -X PUT -H "Content-Type: application/json" -d '{ "title": "Wash the car", "order": 0, "completed": false }' $1
    curl -u $2:$3 -X PUT -H "Content-Type: application/json" -d '{ "title": "Walk the dog", "order": 2, "completed": true }' $1
    curl -u $2:$3 -X PUT -H "Content-Type: application/json" -d '{ "title": "Clean the gutters", "order": 1, "completed": false }' $1
}

delete () {
    if [ -z "$1" ] || [ -z "$2" ]
    then
        echo "Error: Could not delete container group and service, cluster name and service instance name not provided."
        return
    fi

    bx cs cluster-service-unbind $1 $NAME_SPACE $2
    bx cs cluster-rm $1
    bx service delete $2
}

all () {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
    then
        echo "Error: Could not complete entire deployment process, cluster name, service instance name, and docker name not provided."
        return
    fi

    install_tools
    login
    setup $1
    build_docker $3
    push_docker $3
    deploy_container $1 $2
    create_database $1 $2
    get_ip $1 $2
}

#----------------------------------------------------------
# MAIN
# ---------------------------------------------------------

ACTION="$1"

[[ -z $ACTION ]] && help && exit 0

# Initialize the SwiftEnv project environment
eval "$(swiftenv init -)"


case $ACTION in
"install_tools")         install_tools;;
"login")                 login;;
"setup")                 setup "$2";;
"build")                 build_docker "$2";;
"run")                   run_docker "$2";;
"stop")                  stop_docker "$2";;
"push")                  push_docker "$2";;
"create_db")             create_database "$2" "$3";;
"get_ip")                get_ip "$2" "$3";;
"deploy")                deploy_container "$2" "$3";;
"populate_db")           populate_db "$2" "$3" "$4";;
"delete")                delete "$2" "$3";;
"all")                   all "$2" "$3";;
*)                       help;;
esac
