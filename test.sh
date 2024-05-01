            # for pvc in "${pvcs_list[@]}"; do
            #     if  then
            #        kubectl get pvc "$pvc" -n $namespace | grep $pvc 
            #     else
            #         message "PVC $pvc does not exist."
            #         helm upgrade datagrok -n $namespace datagrok-helm-chart -f datagrok-helm-chart/values.yaml \
            #         --set cvm.enabled=$cvm_only \
            #         --set core.enabled=$core_only \
            #         --set cvm.jkg.enabled=$jkg \
            #         --set cvm.h2o.enabled=$h2o \
            #         --set cvm.jupyter_notebook.enabled=$jupyter_notebook \
            #         --set cvm.grok_compute.enabled=$grok_compute \
            #         --set core.datagrok.container.tag=$datagrok_version \
            #         --set core.grok_connect.container.tag=$grok_connect_version \
            #         --set cvm.jkg.container.tag=$jkg_version \
            #         --set cvm.jupyter_notebook.container.tag=$jupyter_notebook_version \
            #         --set cvm.grok_compute.container.tag=$grok_compute_version \
            #         --set cvm.h2o.container.tag=$h2o_version
            #     fi
            # done
pvc="datagrok-cfg"
namespace="datagrok-bleeding-edge"
status=$()
echo $status
status_check=""
if kubectl get pvc "$pvc" -n $namespace &>/dev/null; then
    status_check=true
    echo "status true"
else
    status_check=false
fi
echo $status_check
while [[ "$status_check" != 'true' ]]; do
    if kubectl get pvc "$pvc" -n $namespace &>/dev/null; then
        status_check=true
        echo "status true"
    else
        status_check=false
    fi
    sleep 5
done