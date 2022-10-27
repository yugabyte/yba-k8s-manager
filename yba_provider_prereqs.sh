#!/usr/bin/env bash

#Provider name and base name for the namespace(s)
export YDB_NS_BASENAME="yb-test"
export YDB_REGION="us-east"

#add required zones, following the YDB_AZ_[x] naming convention. At least one is required.
export YDB_AZ_1="us-east1-b"
export YDB_AZ_2="us-east1-c"
export YDB_AZ_3="us-east1-d"

while read var; do
  [ -z "${!var}" ] && { echo "$var is empty or not set. Exiting."; exit 1; }
done << EOF
YDB_NS_BASENAME
YDB_REGION
EOF

if [[ -z "${!YDB_AZ_*}" ]]; then
    echo "YDB_AZ_[x] is not set. At least one AZ must be provided. Exiting."
    exit 1
fi

#this SA can be deleted after provider creation – used to generate kubeconfig files for each namespace
kubectl create sa yb-kubeconfig-puller -n yb-platform
kubectl create role yb-kubeconfig-puller-role -n yb-platform --verb=get,list --resource=secrets,serviceaccounts
kubectl create rolebinding yb-kubeconfig-puller-RB -n yb-platform --role=yb-kubeconfig-puller-role --serviceaccount=yb-platform:yb-kubeconfig-puller

#This needs to be enabled if YDB_K8S_SERVER is not going to be set – allows the SA to get the required info.
#kubectl create role yb-kubeconfig-puller-role -n kube-system --verb=get,list --resource=services
#kubectl create rolebinding yb-kubeconfig-puller-RB -n kube-system --role=yb-kubeconfig-puller-role --serviceaccount=yb-platform:yb-kubeconfig-puller

for zone in "${!YDB_AZ_@}"; do
  ns_name="${YDB_NS_BASENAME}-${!zone}"
  kubectl create ns $ns_name
  kubectl apply -f https://raw.githubusercontent.com/yugabyte/charts/master/rbac/yugabyte-platform-universe-management-sa.yaml -n $ns_name
  curl -s https://raw.githubusercontent.com/yugabyte/charts/master/rbac/platform-namespaced.yaml | sed "s/namespace: <SA_NAMESPACE>/namespace: $ns_name"/g > ns_$ns_name.yaml
  kubectl apply -f ns_$ns_name.yaml -n $ns_name
  kubectl create role yb-kubeconfig-puller-role -n $ns_name --verb=get,list --resource=secrets,serviceaccounts
  kubectl create rolebinding yb-kubeconfig-puller-RB -n $ns_name --role=yb-kubeconfig-puller-role --serviceaccount=yb-platform:yb-kubeconfig-puller

done
