#!/bin/bash

# Function to check if the operator is ready
check_operator_status() {

    while true; do
        pods=$(oc get pods -n openshift-gitops --field-selector=status.phase!=Running --no-headers)

        if [[ -z "$pods"  ]]; then
            echo "Operator openshift-gitops is ready."
            break
        else
            echo "Operator openshift-gitops is not ready. Waiting..."
            sleep 30
        fi
    done
}

# Check if both username and password are provided as arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <username> <password> <apiserver>"
    exit 1
fi

username=$1
password=$2
api_server=$3

echo "======================================"
echo "Logging into Openshift"
echo "======================================"
oc login -u $username -p $password --server=$api_server


echo "Installing Openshift GitOps operator"
oc apply -f argocd-installation.yaml

# approve new installplan
sleep 1m
installPlan=$(oc -n openshift-gitops-operator get subscriptions.operators.coreos.com -o jsonpath='{.items[0].status.installPlanRef.name}')
oc -n openshift-gitops-operator patch installplan "${installPlan}" --type=json -p='[{"op":"replace","path": "/spec/approved", "value": true}]'
check_operator_status

echo "Waiting until argocd instance is available"
status=$(oc -n openshift-gitops get argocd openshift-gitops -o jsonpath='{ .status.phase }')
while [[ "${status}" != "Available" ]]; do
    sleep 5;
    status=$(oc -n openshift-gitops get argocd openshift-gitops -o jsonpath='{ .status.phase }')
done

# annotate it to enable SSA
oc -n openshift-gitops annotate --overwrite argocd/openshift-gitops argocd.argoproj.io/sync-options=ServerSideApply=true

echo "Creating workshop resources"
oc apply -f ./gitops/appofapp-char.yaml
sleep 30

status=$(oc get application.argoproj.io argocd-app-of-app -n openshift-gitops -o jsonpath='{ .status.health.status }')
while [[ "${status}" != "Healthy" ]]; do
  sleep 5;
  status=$(oc get application.argoproj.io argocd-app-of-app -n openshift-gitops -o jsonpath='{ .status.health.status }')
done


echo "Waiting until redhat-ods-applications are running"
sleep 1 
./ns-pods-running.sh redhat-ods-applications
sleep 30
./ns-pods-running.sh redhat-ods-applications
sleep 30
./ns-pods-running.sh redhat-ods-applications

echo "Workshop installation has finished"

echo "ArgoCD route:"
printf "https://$(oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}')\n\n"

echo "Admin ArgoCD password:"
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-

echo "RHAI dashboard:"
printf "https://$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}')\n\n"