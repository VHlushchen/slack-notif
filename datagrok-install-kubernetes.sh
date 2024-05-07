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


function Help() {
  echo "Script to deploy local kubernetes with datagrok."
  echo
  echo "Syntax: ./buildx_docker_image.sh [start/update/delete/purge]"
  echo "options:"
  echo ""
  echo "Command"
  echo "./datagrok-install-kubernetes.sh start"
  echo "Installing local kubernetes and deploying datagrok"
  echo "./datagrok-install-kubernetes.sh update"
  echo "Updating the current configuration associated with changes "
  echo "./datagrok-install-kubernetes.sh delete"
  echo "Removal of datagrok deployment"
  echo "./datagrok-install-kubernetes.sh purge"
  echo "Full clean up of the datagrok environment" 
  echo "                Services"
  echo "Deploying separate service"
  echo "--datagrok"
  echo "    Deploying only datagrok services"
  echo "--cvm"
  echo "    CVM services deployment only"
  echo "-jkg|--jupyter-kernel-gateway"
  echo "    'Jupyter Kernel Gateway deployment only"
  echo "-jn|--jupyter_notebook"
  echo  "    'Jupyter Notebook deployment only'"
  echo "-gc|--grok_compute"
  echo "    Grok Compute deployment only"
  echo "h2o|--h2o"
  echo "    h2o deployment only"
  echo ""
  echo "                Versions"
  echo "Default deployment uses the latest version for all services"
  echo "You can use flags to use a specific version"
  echo "-v|--datagrok-version <version>"
  echo "    set specific datagrok version"
  echo "    Config-file: datagrok_version"
  echo "    Default: latest"
  echo "-gc-v|--grok-compute-version <version>"
  echo "    Set specific datagrok-compute version."
  echo "    Config-file: grok_compute_version"
  echo "    Default: latest"
  echo "-jkg-v|--jupyter-kernel-gateway-version <version>"
  echo "    Set specific Jupyter Kernel Gateway version."
  echo "    Config-file: jkg_version"
  echo "    Default: latest"
  echo "-h2o-v|--h2o-version <version>"
  echo "    Set specific h2o version."
  echo "    Config-file: h2o_version"
  echo "    Default: latest"
  echo "-gn-v|--grok-connect-version <version>"
  echo "    Set specific datagrok connect version."
  echo "    Config-file: grok_connect_version"
  echo "    Default: latest"
  echo "-jn-v|--jupyter-notebook-version <version>"
  echo "    Set specific Jupyter Notebook version."
  echo "    Config-file: jupyter_notebook_version"
  echo "    Default: latest"
  echo "    Custom tags to apply to the image."
  echo "    Multiple options can be used during one script run."
  echo "    Default: empty"
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

function check_local_bin {
    if [[ ":$PATH:" == *":/usr/local/bin:"* ]]; then
        message "/usr/local/bin is in the PATH"
    else
        echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
        # Update the current session's PATH
        export PATH="/usr/local/bin:$PATH"
        message "/usr/local/bin has been added to the PATH"

    fi

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
    if [[ $(minikube status -o json | jq -r .Host) != "Running" || $(minikube status -o json | jq -r .Kubelet) != "Running"  || $(minikube status -o json | jq -r .APIServer) != "Running" ]]; then
        message "Starting minikube..."
        /usr/local/bin/minikube start
        echo "host.minikube.internal" | sudo tee -a /etc/hosts >/dev/null
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
        sleep 30
    else
        message "install Nginx Ingress controller"
        minikube addons enable ingress
        sleep 30
        kubectl get validatingwebhookconfigurations
        
    fi
    # sleep 10
}
check_any_pod_not_running() {
    local namespace=$1
    while read -r pod status; do
        if [[ "$status" != "Running" ]]; then
            return 0
        fi
    done < <(kubectl get pods -n $namespace --output=jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}')
    return 1
}
check_any_pod_not_ready() {
    local namespace=$1
    while read -r pod ready; do
        if [[ "$ready" != "True" ]]; then
            return 0
        fi
    done < <(kubectl get pods -n $namespace --output=jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{"\n"}{end}')
    return 1
}


function deploy_helm {
    datagrok_local_url="http://datagrok.datagrok.internal"
    helm_repo="datagrok-test"
    helm_deployment_name="datagrok"
    pvcs_list=("datagrok-data" "datagrok-cfg" "db-data-datagrok-db-0")

    local namespace="${1}"
    local cvm_only="$2"
    local core_only="$3"
    local jkg="$4"
    local h2o="$5"
    local jupyter_notebook="$6"
    local grok_compute="$7"
    local command="$8"
    local datagrok_version="$9"             #versions["datagrok"]
    local jkg_version="${10}"               #versions["jkg"]
    local h2o_version="${11}"               #versions["h2o"]
    local grok_connect_version=${12}        #versions["grok_connect"]
    local jupyter_notebook_version="${13}"  #versions["jupyter_notebook"]
    local grok_compute_version=${14}        #versions["grok_compute"]
    local verbose=${15}
    local browser=${16}
    local helm_version=${17}    
    local database_internal=${18}
    local dbServer=${19}                    #database_host
    local dbPort=${20}                      #database_port
    local db=${21}                          #database_name    
    local dbAdminLogin=${22}                #database_admin_username
    local dbAdminPassword=${23}             #database_admin_password
    local dbLogin=${24}                     #database_datagrok_username
    local dbPassword=${25}                  #database_datagrok_password
    
    if [[ $cvm_only == false && $core_only == false && $jkg == false && $h2o == false && $jupyter_notebook == false && $grok_compute == false ]]; then
        cvm_only=true
        core_only=true
    fi
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
                helm repo update $helm_repo
            else
                helm repo add $helm_repo https://vhlushchen.github.io/slack-notif/charts/
            fi
            if [[ $(helm list -n $namespace -o json | jq -r .[].name) == $helm_deployment_name ]]; then
                message "$helm_deployment_name is already deployed on the cluster. Run the <./datagrok-install-kubernetes.sh update> to update the datagrok"
            fi
            #helm install datagrok -n $namespace datagrok-test/datagrok-test \
            helm install datagrok -n $namespace datagrok-helm-chart -f datagrok-helm-chart/values.yaml \
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
            if [[ $verbose == true ]]; then
                echo ""
                message "|  NAME   |   STATUS  |   VOLUME  |   CAPACITY    |   ACCESS MODES    |   STORAGECLASS    |   VOLUMEATTRIBUTESCLASS   |   AGE   |"
                message "---------------------------------------------------------------------------------------------------------------------------------"
            fi
            for pvc in "${pvcs_list[@]}"; do
                if kubectl get pvc "$pvc" -n $namespace &>/dev/null; then
                   
                    if [[ $verbose == true ]]; then
                        kubectl get pvc "$pvc" -n $namespace | grep $pvc 
                    # else
                    #     message "$pvc pvc exist"
                    fi
                else
                    message "PVC $pvc does not exist."
                    pvc_exist_status=false
                    while [[ "$pvc_exist_status" != 'true' ]]; do
                        sleep 15
                        if kubectl get pvc "$pvc" -n $namespace &>/dev/null; then

                            pvc_exist_status=true
                        else
                            if [[ $verbose == true ]]; then 
                                kubectl get pvc "$pvc" -n $namespace | grep $pvc 
                            fi
                            message "PVC $pvc does not exist. Creating"
                            helm upgrade datagrok -n $namespace datagrok-helm-chart -f datagrok-helm-chart/values.yaml \
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
                    done
                    
                fi
            done
        fi
        if [ $command == "update" ]; then
            #helm upgrade datagrok -n $namespace datagrok-test/datagrok-test \
            helm upgrade datagrok -n $namespace datagrok-helm-chart -f datagrok-helm-chart/values.yaml \
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
        if [[ $command == "start" ]]; then
            if kubectl get namespace $namespace &> /dev/null; then
                message "Namespace $namespace exists."
            else
                message "Creating $namespace namespace"
                kubectl create namespace $namespace
            fi
            if [[ $(helm repo list -o json | jq --raw-output .[].name | grep $helm_repo) == $helm_repo ]]; then
                message "$helm_repo already exists with the same configuration, skipping"
                helm repo update
            else
                helm repo add $helm_repo https://vhlushchen.github.io/slack-notif/charts/
            fi
            if [[ $(helm list -n $namespace -o json | jq -r .[].name) == $helm_deployment_name ]]; then
                message "$helm_deployment_name is already deployed on the cluster. Run the <./datagrok-install-kubernetes.sh update> to update the datagrok"
            fi
            #helm install datagrok -n $namespace datagrok-test/datagrok-test \
            helm install datagrok -n $namespace datagrok-helm-chart -f datagrok-helm-chart/values.yaml \
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
            --set core.datagrok.grok_parameters.dbPort=$dbPort \
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
            if [[ $verbose == true ]]; then
                echo ""
                message "|  NAME   |   STATUS  |   VOLUME  |   CAPACITY    |   ACCESS MODES    |   STORAGECLASS    |   VOLUMEATTRIBUTESCLASS   |   AGE   |"
                message "---------------------------------------------------------------------------------------------------------------------------------"
            fi
            pvcs_list_db_external=("datagrok-data" "datagrok-cfg")
            for pvc in "${pvcs_list[@]}"; do
                if kubectl get pvc "$pvc" -n $namespace &>/dev/null; then
                   
                    if [[ $verbose == true ]]; then
                        kubectl get pvc "$pvc" -n $namespace | grep $pvc 
                    # else
                    #     message "$pvc pvc exist"
                    fi
                else
                    message "PVC $pvc does not exist."
                    pvc_exist_status=false
                    while [[ "$pvc_exist_status" != 'true' ]]; do
                        sleep 15
                        if kubectl get pvc "$pvc" -n $namespace &>/dev/null; then

                            pvc_exist_status=true
                        else
                            if [[ $verbose == true ]]; then 
                                kubectl get pvc "$pvc" -n $namespace | grep $pvc 
                            fi
                            message "PVC $pvc does not exist. Creating"
                            helm upgrade datagrok -n $namespace datagrok-helm-chart -f datagrok-helm-chart/values.yaml \
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
                    done
                    
                fi
            done
        fi
        if [[ $command == "update" ]]; then
            #helm upgrade datagrok -n $namespace datagrok-test/datagrok-test \
            helm upgrade datagrok -n $namespace datagrok-helm-chart -f datagrok-helm-chart/values.yaml \
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
            --set core.datagrok.grok_parameters.dbPort=$dbPort \
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
        fi
    fi
    
    start_time_running_state=$(date +%s)
    timeout_running_state=600
    sleep 100
    echo ""
    while check_any_pod_not_running $namespace; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time_running_state))
        if (( elapsed_time >= timeout_running_state )); then
            echo "Timeout reached. Not all pods are running."
            exit 1
        fi
        message "Not all pods are running. Waiting..."
        if [[ $verbose == true ]]; then
            kubectl get pods -n $namespace            
        fi
        sleep 30  # Adjust the delay as needed
    done
    message "All pods are running!"
    start_time_ready_state=$(date +%s)
    timeout_ready_state=120
    
    while check_any_pod_not_ready $namespace; do
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time_ready_state))
    if (( elapsed_time >= timeout_ready_state )); then
        message "Timeout reached. Not all pods are ready."
        exit 1
    fi
        message "Not all pods are ready. Waiting..."
        kubectl logs deployment/datagrok-1-18-4 -c datagrok -n datagrok-1-18-4
        kubectl logs deployment/datagrok-1-18-4 -c init-wait-for-db -n datagrok-1-18-4
        if [[ $verbose == true ]]; then
            kubectl get pods -n $namespace
        fi
        sleep 30  # Adjust the delay as needed
    done

    message "All pods are ready!"
    if [[ $verbose == true ]]; then
        kubectl get pods -n $namespace
        message "services status"
        kubectl get svc -n $namespace
    fi
    url="http://${datagrok_version//./-}.datagrok.internal"
    if [[ $core_only == true ]]; then
        if [[ $verbose == true ]]; then
            message "ingress status"
            kubectl get ingress -n $namespace
        fi
        response=$(curl -s -I "$url")
        if [[ $response == *"HTTP/1.1 200 OK"* ]]; then
            if [[ $verbose == true ]]; then
                message "The URL $url returned a 200 status code."
            fi
        fi
    fi
    
    
    
    
    if [[ $browser == true ]]; then
        timeout=10
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
        xdg-open $url
        message "If the browser hasn't open, use the following link: $url" 
        message "To extend Datagrok fucntionality, install extension packages on the 'Manage -> Packages' page"
    fi
  
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
        helm uninstall datagrok -n $namespace &> /dev/null
        message "release $namespace uninstalled"
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
    check_local_bin
    check_kubectl
    check_minikube
    check_helm
}

# === Main part of the script starts from here ===

helm_version="1.0.2"
namespace=""
host=""

#database 



start=false
update=false
delete=false
purge=false
browser=true
auto_tests=false
verbose=false

database_internal=true
cvm_only=false
core_only=false
jkg=false
h2o=false
jupyter_notebook=false
grok_compute=false
update=false
command=""

#config
config_file=false
config_status=""
config_file_path=""

declare -A versions=(
    ["datagrok"]="latest"
    ["jkg"]="latest"
    ["h2o"]="latest"
    ["grok_compute"]="latest"
    ["grok_connect"]="latest"
    ["jupyter_notebook"]="latest"
)
declare -A db_creds=(
    ["database_host"]=""
    ["database_port"]=""
    ["database_name"]="" 
    ["database_admin_username"]="" 
    ["database_admin_password"]="" 
    ["database_datagrok_username"]="" 
    ["database_datagrok_password"]="" 
    )
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
        help) Help;;
        --help) Help;;
        -n|--namespace) shift; namespace="$1";;
        --config) shift; config_file=true config_file_path="$1";;
        -jkg-v|--jupyter-kernel-gateway-version) shift; versions["jkg"]="$1";;
        -h2o-v|--h2o-version) shift; versions["h2o"]="$1";;
        -gc-v|--grok-compute-version) shift; versions["grok_compute"]="$1";;
        -gn-v|--grok-connect-version) shift; versions["grok_connect"]="$1";;
        -jn-v|--jupyter-notebook-version) shift; versions["jupyter_notebook"]="$1";;
        -v|--datagrok-version) shift; versions["datagrok"]="$1";;
        --bleeding-edge) versions["datagrok"]="bleeding-edge";;
        --host) shift; host="$1";;
        --helm-version) shift; helm_version="$1";;
        --cvm) cvm_only=true;;
        --auto-tests) auto_tests=true;;
        --datagrok) core_only=true;;
        --verbose) verbose=true;;
        -jkg|--jupyter-kernel-gateway) jkg=true;;
        -jn|--jupyter_notebook) jupyter_notebook=true;;
        -gc|--grok_compute) grok_compute=true;;
        -h2o|--h2o) h2o=true;;
        *) message "Unknown parameter passed: $1" && Help; exit 1;;
        # purge) datagrok_purge ;;
        help | "--help")
            echo "usage: $script_name install|start|stop|update|reset|purge" >&2
            exit 1
            ;;
    esac
    shift
done
if [[ $auto_tests == true && $update == false && $delete == false ]]; then 
    start=true
    browser=false
    datagrok_install
fi
if [[ $auto_tests == true && $update == true ]]; then
    update=true
    browser=false
fi

if [[ "${versions["datagrok"]}" == "bleeding-edge" && ($start == true || $update == true) ]]; then
    message "Version of all services changed to bleeding-edge"
    versions=(
        ["datagrok"]="bleeding-edge"
        ["jkg"]="bleeding-edge"
        ["h2o"]="bleeding-edge"
        ["grok_compute"]="bleeding-edge"
        ["grok_connect"]="bleeding-edge"
        ["jupyter_notebook"]="bleeding-edge"
    )
fi

if [[ $config_file == true ]]; then
    if grep -q "database_" $config_file_path; then
        database_internal=false
        for key in "${!db_creds[@]}"; do
                if [ $(jq --arg key "$key" 'has($key)' $config_file_path) == true ]; then
                    db_creds[$key]=$(jq .$key $config_file_path)
                else
                    message "!!! $key does not exist. Please add to config file"
                    config_status="Failed"
                    exit 1
                fi
        done
    fi
    for key in "${!versions[@]}"; do
        if [ $(jq --arg key "${key}_version" 'has($key)' $config_file_path) == true ]; then
            versions[$key]=$(jq ".${key}_version" $config_file_path)
            if [[ $delete == false ]]; then
                message ">>> Version changed for service $key to ${versions[${key}]}"
            fi
        else
            message "== ${key}_version is not specified in the config file, the version of $key has not changed"
            message "== Version of the ${key} is ${versions[$key]}"
        fi
    done  
fi

if [[ $namespace == "" ]]; then
    namespace_gen="datagrok-${versions["datagrok"]//\"/}"
    namespace=${namespace_gen//./-}
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
    ${versions["datagrok"]//\"/} \
    ${versions["jkg"]//\"/} \
    ${versions["h2o"]//\"/} \
    ${versions["grok_connect"]//\"/} \
    ${versions["jupyter_notebook"]//\"/} \
    ${versions["grok_compute"]//\"/} \
    $verbose \
    $browser \
    $helm_version \
    $database_internal \
    ${db_creds["database_host"]//\"/} \
    ${db_creds["database_port"]//\"/} \
    ${db_creds["database_name"]//\"/} \
    ${db_creds["database_admin_username"]//\"/} \
    ${db_creds["database_admin_password"]//\"/} \
    ${db_creds["database_datagrok_username"]//\"/} \
    ${db_creds["database_datagrok_password"]//\"/} 
    
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
    ${versions["datagrok"]//\"/} \
    ${versions["jkg"]//\"/} \
    ${versions["h2o"]//\"/} \
    ${versions["grok_connect"]//\"/} \
    ${versions["jupyter_notebook"]//\"/} \
    ${versions["grok_compute"]//\"/} \
    $verbose \
    $browser \
    $helm_version \
    $database_internal \
    ${db_creds["database_host"]//\"/} \
    ${db_creds["database_port"]//\"/} \
    ${db_creds["database_name"]//\"/} \
    ${db_creds["database_admin_username"]//\"/} \
    ${db_creds["database_admin_password"]//\"/} \
    ${db_creds["database_datagrok_username"]//\"/} \
    ${db_creds["database_datagrok_password"]//\"/} 
fi
if [[ $delete == true ]]; then
    datagrok_delete $namespace
fi
if [[ $purge == true ]]; then
    datagrok_purge $namespace
fi