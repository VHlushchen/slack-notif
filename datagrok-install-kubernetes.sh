#!/bin/bash

# This script automates the Datagrok local installation and running
# To see additional actions, run "./datagrok-install-local help"

set -o errexit

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'
timeout=30

function message() {
    echo -e "${YELLOW}$1${RESET}"
}

function error() {
    echo -e "${RED}!!!$1!!!${RESET}"
}


function count_down() {
    echo -n "Waiting:"
    for ((i = ${1}; i > 0; i--)); do
        echo -n " $i"
        sleep 1
    done
    echo " 0"
}

function check_docker() {
    if [ ! -x "$(command -v docker)" ]; then
        error "Docker engine is not installed"
        message "Please install Docker and Docker Compose plugin by manual: https://docs.docker.com/engine/install/"
        exit 255
    fi
}

function check_docker_daemon() {
    docker info >/dev/null || {
        error "Docker daemon is not running"
        message "Please launch Docker Desktop application"
        exit 255
    }
}

function check_kubectl() {
    if ! [ -x "$(command -v kubectl)" ]; then
        message "Installing kubectl..."
        curl -LO https://dl.k8s.io/release/`curl -LS https://dl.k8s.io/release/stable.txt`/bin/linux/amd64/kubectl
        chmod +x ./kubectl
        sudo mv ./kubectl /usr/local/bin/kubectl
        message "Check kubectl version"
        kubectl version --client
    else
        message "kubectl is already installed"
    fi
}

function check_minikube() {

    if ! [ -x "$(command -v minikube)" ]; then
        message "Installing minikube..."
        curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        chmod +x minikube
        sudo cp minikube /usr/local/bin/
        rm minikube

        message "Configuring minikube..."
        minikube config set driver docker

    else
        message "minikube is already installed"
    fi
    if [[ $(minikube status -o json | jq -r .Host) != "Running" ]]; then

        message "Starting minikube..."
        /usr/local/bin/minikube start
    else
        message "minikube is already up and running"
    fi
    message "Check context"
    if [ $(kubectl config current-context) != 'minikube' ]; then
        kubectl config use-context minikube
    else
        message "kubectl already uses the minikube context"
    fi

    if [[ $(minikube addons list -o json | jq --raw-output .ingress.Status) == "enabled" ]]; then 
        message "Nginx Ingress controller installed"
    else
        message "install Nginx Ingress controller"
        minikube addons enable ingress
    fi
    sleep 10
}

function deploy_helm {
    timeout=60
    datagrok_local_url="http://datagrok.datagrok.internal"
    helm_repo="datagrok-test"
    helm_deployment_name="datagrok"

    local namespace="${1}"
    local cvm_only="$2"
    local core_only="$3"
    local jkg="$4"
    local h2o="$5"
    local jupyter_notebook="$6"
    local grok_compute="$7"
    local command="$8"
    local datagrok_version="$9"
    local jkg_version="${10}"
    local h2o_version="${11}"
    local grok_connect_version=${12}
    local jupyter_notebook_version="${13}"
    local grok_compute_version=${14}
    local helm_version=${15}    
    local database_internal=${16}
    local dbServer=${17}
    local db=${18}      
    local dbAdminLogin=${19}
    local dbAdminPassword=${20}
    local dbLogin=${21}
    local dbPassword=${22}





    

    if [[ $cvm_only == false && $core_only == false && $jkg == false && $h2o == false && $jupyter_notebook == false && $grok_compute == false ]]; then
        cvm_only=true
        core_only=true
    fi
    echo $database_internal
    if [[ $database_internal == true ]]; then
        if [ $command == "start" ]; then
            if kubectl get namespace $namespace &> /dev/null; then
                message "Namespace $namespace exists."
            else
                message "Creating $namespace namespace"
                kubectl create namespace $namespace
            fi
            if [[ $(helm repo list -o json | jq --raw-output .[].name | grep $helm_repo) == $helm_repo ]]; then
                message "$helm_repo already exists with the same configuration, skipping"
            else
                helm repo add $helm_repo https://vhlushchen.github.io/slack-notif/charts/
            fi
            # helm install datagrok -n $namespace datagrok-test/datagrok-test \
            if [[ $(helm list -n $namespace -o json | jq -r .[].name) == $helm_deployment_name ]]; then
                message "$helm_deployment_name is already deployed on the cluster. Run the <./datagrok-install-kubernetes.sh update> to update the datagrok"
            fi
            helm upgrade --install $helm_deployment_name datagrok-helm-chart -n $namespace -f datagrok-helm-chart/values.yaml \
            --version $helm_version \
            --set cvm.enabled=$cvm_only \
            --set core.enabled=$core_only \
            --set cvm.jkg.enabled=$jkg \
            --set cvm.h2o.enabled=$h2o \
            --set cvm.jupyter_notebook.enabled=$jupyter_notebook \
            --set cvm.grok_compute.enabled=$grok_compute \
            --set core.datagrok.container.tag=$datagrok_version \
            --set core.grok_connect.container.tag=$grok_connect_version \
            --set cvm.jkg.container.tag=$jkg_version \
            --set cvm.jupyter_notebook.container.tag=$jupyter_notebook_version \
            --set cvm.grok_compute.container.tag=$grok_compute_version \
            --set cvm.h2o.container.tag=$h2o_version
            if grep -q "$(minikube ip) ${datagrok_version//./-}.datagrok.internal" /etc/hosts; then 
                message "${datagrok_version//./-}.datagrok.internal already added to hosts"
            else
            message "add ${datagrok_version//./-}.datagrok.internal to hosts"
            echo "$(minikube ip) ${datagrok_version//./-}.datagrok.internal"| sudo tee -a /etc/hosts >/dev/null
            fi
        fi
        if [ $command == "update" ]; then
            # helm upgrade datagrok -n $namespace datagrok-test/datagrok-test \
            helm upgrade $helm_deployment_name datagrok-helm-chart -n $namespace -f datagrok-helm-chart/values.yaml \
            --version $helm_version  \
            --set cvm.enabled=$cvm_only \
            --set core.enabled=$core_only \
            --set cvm.jkg.enabled=$jkg \
            --set cvm.h2o.enabled=$h2o \
            --set cvm.jupyter_notebook.enabled=$jupyter_notebook \
            --set cvm.grok_compute.enabled=$grok_compute \
            --set core.datagrok.container.tag=$datagrok_version \
            --set core.grok_connect.container.tag=$grok_connect_version \
            --set cvm.jkg.container.tag=$jkg_version \
            --set cvm.jupyter_notebook.container.tag=$jupyter_notebook_version \
            --set cvm.grok_compute.container.tag=$grok_compute_version \
            --set cvm.h2o.container.tag=$h2o_version
        fi
    else
        echo $db
        if [ $command == "start" ]; then
            if kubectl get namespace $namespace &> /dev/null; then
                message "Namespace $namespace exists."
            else
                message "Creating $namespace namespace"
                kubectl create namespace $namespace
            fi
            if [[ $(helm repo list -o json | jq --raw-output .[].name | grep $helm_repo) == $helm_repo ]]; then
                message "$helm_repo already exists with the same configuration, skipping"
            else
                helm repo add $helm_repo https://vhlushchen.github.io/slack-notif/charts/
            fi
            # helm install datagrok -n $namespace datagrok-test/datagrok-test \
            if [[ $(helm list -n $namespace -o json | jq -r .[].name) == $helm_deployment_name ]]; then
                message "$helm_deployment_name is already deployed on the cluster. Run the <./datagrok-install-kubernetes.sh update> to update the datagrok"
            fi
            echo "inside $db"
            helm upgrade --install $helm_deployment_name datagrok-helm-chart -n $namespace -f datagrok-helm-chart/values.yaml \
            --version $helm_version \
            --set cvm.enabled=$cvm_only \
            --set core.enabled=$core_only \
            --set cvm.jkg.enabled=$jkg \
            --set cvm.h2o.enabled=$h2o \
            --set cvm.jupyter_notebook.enabled=$jupyter_notebook \
            --set cvm.grok_compute.enabled=$grok_compute \
            --set core.datagrok.container.tag=$datagrok_version \
            --set core.grok_connect.container.tag=$grok_connect_version \
            --set cvm.jkg.container.tag=$jkg_version \
            --set cvm.jupyter_notebook.container.tag=$jupyter_notebook_version \
            --set cvm.grok_compute.container.tag=$grok_compute_version \
            --set cvm.h2o.container.tag=$h2o_version \
            --set core.database.enabled=$database_internal \
            --set core.datagrok.grok_parameters.dbServer=$dbServer \
            --set core.datagrok.grok_parameters.db=$db \
            --set core.datagrok.grok_parameters.dbAdminLogin=$dbAdminLogin \
            --set core.datagrok.grok_parameters.dbAdminPassword=$dbAdminPassword \
            --set core.datagrok.grok_parameters.dbLogin=$dbLogin \
            --set core.datagrok.grok_parameters.dbPassword=$dbPassword \
            --set cvm.jkg.grok_parameters.dbServer=$dbServer \
            --set cvm.jkg.grok_parameters.db=$db \
            --set cvm.jkg.grok_parameters.dbPort=$dbPort \
            --set cvm.jkg.grok_parameters.dbLogin=$dbLogin \
            --set cvm.jkg.grok_parameters.dbPassword=$dbPassword
            
            if grep -q "$(minikube ip) ${datagrok_version//./-}.datagrok.internal" /etc/hosts; then 
                message "${datagrok_version//./-}.datagrok.internal already added to hosts"
            else
            message "add ${datagrok_version//./-}.datagrok.internal to hosts"
            echo "$(minikube ip) ${datagrok_version//./-}.datagrok.internal"| sudo tee -a /etc/hosts >/dev/null
            fi
        fi
        if [ $command == "update" ]; then
            # helm upgrade datagrok -n $namespace datagrok-test/datagrok-test \
            helm upgrade $helm_deployment_name datagrok-helm-chart -n $namespace -f datagrok-helm-chart/values.yaml \
            --version $helm_version  \
            --set cvm.enabled=$cvm_only \
            --set core.enabled=$core_only \
            --set cvm.jkg.enabled=$jkg \
            --set cvm.h2o.enabled=$h2o \
            --set cvm.jupyter_notebook.enabled=$jupyter_notebook \
            --set cvm.grok_compute.enabled=$grok_compute \
            --set core.datagrok.container.tag=$datagrok_version \
            --set core.grok_connect.container.tag=$grok_connect_version \
            --set cvm.jkg.container.tag=$jkg_version \
            --set cvm.jupyter_notebook.container.tag=$jupyter_notebook_version \
            --set cvm.grok_compute.container.tag=$grok_compute_version \
            --set cvm.h2o.container.tag=$h2o_version
        fi
    fi
    sleep 10
    message "pods status"
    kubectl get pods -n $namespace
    message "services status"
    kubectl get svc -n $namespace
    if [[ $core_only == true ]]; then
        message "ingress status"
        kubectl get ingress -n $namespace
    fi
    message "Waiting while the Datagrok server is starting"
    echo "When the browser opens, use the following credentials to log in:"
    echo "------------------------------"
    echo -ne "${GREEN}"
    echo "Login:    admin"
    echo "Password: admin"
    echo -ne "${RESET}"
    echo "------------------------------"
    echo "If you see the message 'Datagrok server is unavaliable' just wait for a while and reload the web page "
    count_down ${timeout}
    message "Running browser"
    xdg-open http://${datagrok_version//./-}.datagrok.internal 
    message "If the browser hasn't open, use the following link: http://${datagrok_version//./-}.datagrok.internal" 
    message "To extend Datagrok fucntionality, install extension packages on the 'Manage -> Packages' page"
  
}
function check_helm() {
    if ! [ -x "$(command -v helm)" ]; then
        message "Installing helm..."
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod 700 get_helm.sh
        ./get_helm.sh   
    fi    
}

function datagrok_delete {

    local namespace="$1"
    if helm list -n $namespace | grep datagrok &> /dev/null; then
        helm uninstall datagrok -n $namespace
        # kubectl delete namespace $namespace
    else
        message "$namespace is not installed"
    fi
}

function datagrok_purge {
    
    local namespace="$1"

    if [ $(minikube status -o json | jq -r .Host) != "Running" ]; then
        message "minikube is not running"
    else  
        datagrok_delete
        if kubectl get namespace "$namespace" &> /dev/null; then
            kubectl delete namespace $namespace
        else
            message "namespace $namespace is not installed"
        fi
        if grep -q "$(minikube ip) datagrok.datagrok.internal" /etc/hosts; then 
            sudo sed -i "s/$(minikube ip) ${datagrok_version//./-}.datagrok.internal//g" /etc/hosts
            message "datagrok.datagrok.internal deleted from hosts"

        else
            message "datagrok.datagrok.internal is not added to hosts" 
        fi
        message "Stopping minikube..."
        /usr/local/bin/minikube stop
        /usr/local/bin/minikube delete
        sudo rm /usr/local/bin/minikube
        
    fi


}

function datagrok_install {
    check_docker
    check_docker_daemon
    check_kubectl
    check_minikube
    check_helm
}

# === Main part of the script starts from here ===
datagrok_version="latest"
jkg_version="latest" 
h2o_version="latest"
grok_compute_version="latest"
jupyter_notebook_version="latest"
grok_connect_version="latest"
helm_version="1.0.1"
namespace=""

#database 

dbServer=""
dbPort=""
db=""
dbLogin=""
dbPassword=""
dbAdminLogin=""
dbAdminPassword=""

start=false
update=false
delete=false
purge=false

database_internal=true
cvm_only=false
core_only=false
jkg=false
h2o=false
jupyter_notebook=false
grok_compute=false
update=false
command=""

if [[ "$#" -eq 0 ]]; then
    datagrok_install
    start=true
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        install) datagrok_install ;;
        purge) purge=true ;;
        start) start=true ;;
        delete) delete=true ;;
        update) update=true ;;
        -n|--namespace) shift; namespace="$1";;
        -db|--database) database_internal=false;;
        -jkg-v|--jupyter-kernel-gateway-version) shift; jkg_version="$1";;
        -h2o-v|--h2o-version) shift; h2o_version="$1";;
        -gc-v|--grok-compute-version) shift; grok_compute_version="$1";;
        -gn-v|--grok-connect-version) shift; grok_connect_version="$1";;
        -jn-v|--jupyter-notebook-version) shift; jupyter_notebook_version="$1";;
        -v|--datagrok-version) shift; datagrok_version="$1";;
        --helm-version) shift; helm_version="$1";;
        --cvm) cvm_only=true,;;
        --datagrok) core_only=true;;
        -jkg|--jupyter-kernel-gateway) jkg=true;;
        -jn|--jupyter_notebook) jupyter_notebook=true;;
        -gc|--grok_compute) grok_compute=true;;
        -h2o|--h2o) h2o=true;;
        *) echo "Unknown parameter passed: $1"; exit 1;;
        # purge) datagrok_purge ;;
        help | "-h" | "--help")
            echo "usage: $script_name install|start|stop|update|reset|purge" >&2
            exit 1
            ;;
    esac
    shift
done


if [[ $namespace == "" ]]; then
    namespace_gen="datagrok-$datagrok_version"
    namespace=${namespace_gen//./-}
fi
if [[ $database_internal == false ]]; then
    read -p read -p "Please enter the database host: " dbServer
    message "You entered the database host as: $dbServer"
    read -p read -p "Please enter the database host: " dbPort
    message "You entered the database port as: $dbPort"
    read -p read -p "Please enter the database host: " db
    message "You entered the database name as: $db"
    read -p read -p "Please enter the database host: " dbAdminLogin
    message "You entered the database admin username as: $dbAdminLogin"
    read -p read -p "Please enter the database host: " dbAdminPassword
    message "You entered the database admin password as: $dbAdminPassword"
    read -p read -p "Please enter the database username: " dbLogin
    message "You entered the database host as: $dbLogin"
    read -p read -p "Please enter the database pasword: " dbPassword
    message "You entered the database host as: $dbPassword"

fi

if [[ $start == true ]]; then
    command="start"
    deploy_helm \
    $namespace \
    $cvm_only \
    $core_only \
    $jkg \
    $h2o \
    $jupyter_notebook \
    $grok_compute \
    $command \
    $datagrok_version \
    $jkg_version \
    $h2o_version \
    $grok_connect_version \
    $jupyter_notebook_version \
    $grok_compute_version \
    $helm_version \
    $database_internal \
    $dbServer \
    $db \
    $dbAdminLogin \
    $dbAdminPassword \
    $dbLogin \
    $dbPassword \
    
fi

if [[ $update == true ]]; then
    command="update"
    deploy_helm \
    $namespace \
    $cvm_only \
    $core_only \
    $jkg \
    $h2o \
    $jupyter_notebook \
    $grok_compute \
    $command \
    $datagrok_version \
    $jkg_version \
    $h2o_version \
    $grok_connect_version \
    $jupyter_notebook_version \
    $grok_compute_version \
    $helm_version
    # echo $helm_version 
fi
if [[ $delete == true ]]; then
    datagrok_delete $namespace
fi
if [[ $purge == true ]]; then
    datagrok_purge $namespace
fi