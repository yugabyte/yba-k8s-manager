#!/usr/bin/env bash

while read var; do
  [ -z "${!var}" ] && { echo "Required parameter $var is empty or not set. Exiting."; exit 1; }
done << EOF
YDB_NS_BASENAME
YDB_REGION
YDB_STORAGECLASS
EOF

if [[ -z "${!YDB_AZ_*}" ]]; then
    echo "YDB_AZ_[x] is empty or not set. At least one AZ must be provided. Exiting."
    exit 1
fi

#Use defaults if optional vars are not set
YDB_REGISTRY="${YDB_REGISTRY:-quay.io/yugabyte/yugabyte}"
BASEDIR="${BASEDIR:-/tmp/yb-configs}"

#check if k8s server is provided or SA has rights to pull the info
if [ -z "$YDB_K8S_SERVER" ]; then
  TERM=dumb kubectl cluster-info
  if [ $? -eq 0 ]; then
  server=$(TERM=dumb kubectl cluster-info | awk '{print $7; exit}')
  else
    echo "YDB_K8S_SERVER is not set and yb-kubeconfig-puller doesn't have required premissions in kube-system to get Cluster IP. Check README.md for instructions. Exiting."
    exit 1
  fi
else
  server=$YDB_K8S_SERVER
fi

#TODO parameterize/add default value
export cluster_name="default"

#sets default kubeconfig to first az, as it's overridden, but still expected
read -a zone_field <<< "${!YDB_AZ_@}"
YDB_KUBECONFIG="$BASEDIR/yugabyte-${!zone_field[0]}-kubeconfig.yaml"

#start provider yaml template generation

cat << EOF > $BASEDIR/provider_template.yaml
---
name: $YDB_NS_BASENAME
kubeconfig_path: $YDB_KUBECONFIG
service_account_name: yugabyte-platform-universe-management
image_registry: $YDB_REGISTRY
EOF

if [ -n "$YDB_PULLSECRET" ]; then
  printf '%s\n' \
  "image_pull_secret_path: $YDB_PULLSECRET" >> $BASEDIR/provider_template.yaml
fi

cat << EOF >> $BASEDIR/provider_template.yaml
regions:
  # Must be one of the following regions:
  #  [us-west us-east south-asia new-zealand eu-west us-south us-north
  #   south-east-asia japan eu-east china brazil australia]
  - code: $YDB_REGION
    zone_info:
EOF
for zone in "${!YDB_AZ_@}"; do
  ns_name="${YDB_NS_BASENAME}-${!zone}"
  #adding zone config to provider_template
  # printf instead of heredoc due to bash indent limitations
  printf '%s\n' \
  "    - name: ${!zone}"\
  "      config:"\
  "        storage_class: $YDB_STORAGECLASS"\
  "        kubernetes_namespace: $ns_name"\
  "        overrides: |"\ >> $BASEDIR/provider_template.yaml
  if [ "${!YDB_NODESELECT_*}" ]; then
    #if any nodeSelectors defined, add nodeSelector section for masters and tservers
    printf '%s\n'\
    "           master:"\
    "             nodeSelector:"\ >> $BASEDIR/provider_template.yaml
    for kv in "${!YDB_NODESELECT_@}";do
      IFS=';'
      read  -a field <<< "${!kv}"
      key=${field[0]}
      value=${field[1]}
      printf '%s\n' \
      "               $key: $value"\ >> $BASEDIR/provider_template.yaml
      unset IFS
    done
    printf '%s\n'\
    "           tserver:"\
    "             nodeSelector:"\ >> $BASEDIR/provider_template.yaml
    for kv in "${!YDB_NODESELECT_@}";do
      IFS=';'
      read  -a field <<< "${!kv}"
      key=${field[0]}
      value=${field[1]}
      printf '%s\n' \
      "               $key: $value"\ >> $BASEDIR/provider_template.yaml
      unset IFS
    done
  else echo "No nodeSelector configured."
  fi

  if [ "${!YDB_TOLERATION_*}" ]; then
    #if any tolerations defined, add a tolerations section for masters and tservers
    printf '%s\n'\
    "           master:"\
    "             tolerations:"\ >> $BASEDIR/provider_template.yaml
    for toleration in "${!YDB_TOLERATION_@}";do
      IFS=';'
      read  -a field <<< "${!toleration}"
      key=${field[0]}
      operator=${field[1]}
      value=${field[2]}
      effect=${field[3]}
      printf '%s\n' \
      "             - key: \"$key\""\
      "               operator: \"$operator\""\
      "               value: \"$value\""\
      "               effect: \"$effect\"" >> $BASEDIR/provider_template.yaml
      unset IFS
    done
    printf '%s\n'\
    "           tserver:"\
    "             tolerations:"\ >> $BASEDIR/provider_template.yaml
    for toleration in "${!YDB_TOLERATION_@}";do
      IFS=';'
      read  -a field <<< "${!toleration}"
      key=${field[0]}
      operator=${field[1]}
      value=${field[2]}
      effect=${field[3]}
      printf '%s\n' \
      "             - key: \"$key\""\
      "               operator: \"$operator\""\
      "               value: \"$value\""\
      "               effect: \"$effect\"" >> $BASEDIR/provider_template.yaml
      unset IFS
    done
  else echo "No tolerations configured."
  fi
  #overriding kubeconfigs as we're namespace restricted
  printf '%s\n' \
  "        # Override global kubeconfig for this namespace"\
  "        kubeconfig_path: $BASEDIR/yugabyte-${!zone}-kubeconfig.yaml" >> $BASEDIR/provider_template.yaml

  #generating kubeconfigs
  secret_name=$(kubectl --namespace $ns_name get serviceAccount yugabyte-platform-universe-management -o jsonpath='{.secrets[0].name}')
  ca=$(kubectl --namespace $ns_name get secret/$secret_name -o jsonpath='{.data.ca\.crt}')
  token=$(kubectl --namespace $ns_name get secret/$secret_name -o jsonpath='{.data.token}' | base64 -d)
  printf '%s\n'\
  "---"\
  "apiVersion: v1"\
  "kind: Config"\
  "clusters:"\
  "  - name: ${cluster_name}"\
  "    cluster:"\
  "      certificate-authority-data: ${ca}"\
  "      server: ${server}"\
  "contexts:"\
  "  - name: yugabyte-platform-universe-management@${cluster_name}"\
  "    context:"\
  "      cluster: ${cluster_name}"\
  "      namespace: ${ns_name}"\
  "      user: yugabyte-platform-universe-management"\
  "users:"\
  "  - name: yugabyte-platform-universe-management"\
  "    user:"\
  "      token: ${token}"\
  "current-context: yugabyte-platform-universe-management@${cluster_name}" >> $BASEDIR/yugabyte-${!zone}-kubeconfig.yaml
done
