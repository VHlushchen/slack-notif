#!/bin/bash

# Define the namespace
namespace="datagrok-1-18-0"

# Get the list of pods in the specified namespace
pvcs=$(kubectl get pvc -n $namespace --output=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}')

# Loop through each PVC and print its name and status
echo "PVC Name   Status"
echo "--------------------"
while IFS=$'\t' read -r pvc status; do
    
    if [[ $status == 'Bound' ]]; then
        echo "$pvc   $status"
    else
        echo "$pvc   $status"
        exit 1
    fi
done <<< "$pvcs"