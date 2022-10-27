# Yugabyte Anywhere Manager for k8s

Containerization and tooling for [yugaware-client](https://github.com/yugabyte/yb-tools/tree/main/yugaware-client)

---
This is a set of wrappers for the [yugaware-client](https://github.com/yugabyte/yb-tools/tree/main/yugaware-client) cli tool that allows it to run in automated and containerized fashion. `job-yamls` directory also contains the k8s job yaml files to run with a CI system.

## Usage

Default behavior for this tool is to assume the most restricted deployment scenario – [Namespace Restricted](https://docs.yugabyte.com/preview/yugabyte-platform/configure-yugabyte-platform/set-up-cloud-provider/kubernetes/#service-account), when Platform SA has no admin privileges and the least amount of privileges possible in the required Universe namespace(s). This leads to a prerequisite step of running a `yba_provider_prereqs` script when creating a Provider, which will take care of creating the required namespaces, SAs and configuring RBAC. All other steps are performed inside the job pod/container – including the Kubeconfig generation. Due to current limitations (present for YugabyteDB Anywhere version `2.15.2`) each availability zone in multi-AZ setup needs to be located in a separate namespace, so the prerequisites script is taking care of those.

Variables prefixed with `YW_` are generally the ones used directly by the [yugaware-client](https://github.com/yugabyte/yb-tools/tree/main/yugaware-client), while the `YDB_` ones are used by the wrappers.

### Preparation – building the images

There are two Docker images used by the Kubernetes yamls: `yba-k8s-manager-cfgbuilder` and `yugaware-client`.
Build the images and push them to the registry of choice, then substitute the parameter in the k8s yaml files.
```
docker build -t <yourrepo>/yba-k8s-manager-cfgbuilder -f Dockerfile-cfgbuilder
git clone https://github.com/yugabyte/yb-tools.git
docker build -t <yourrepo>/yugaware-client -f Dockerfile-ywclient
```

### Registering the platform

Edit the required variables and container images in the k8s YAML definition and apply it.
```
kubectl apply -f job-yamls/job-register-user.yaml
```

#### Required variables

 - `YW_HOSTNAME` :           Hostname/IP address of the Platform host;

 - `YW_FULL_NAME` :          Full name of the Yugabyte Platform Admin user;

 - `YW_EMAIL` :              Email of the Yugabyte Platform Admin user;

 - `YW_PASSWORD`:            Password for the Yugabyte Platform user.

#### Optional variables

- `YW_GENERATE_API_TOKEN`:   Whether the tool should generate the API token to control the Yugabyte Platform. *Note: even though this is an optional variable, the tool requires an API token to connect to the Platform. It can be obtained either by using this flag and parsing the output or by getting it from the Platform UI.*


### Creating a provider

#### Prerequisites script

Edit the required variables in the `yba_provider_prereqs` script and run it (or supply in the container, if dockerized). *Please note: when dockerized, kubeconfig would need to be mounted to the container as a volume for it to function properly, as this script relies on `kubectl`. Docker option would look as follows:`-v /path/to/your/kube/config:/.kube/config`*
```
chmod +x yba_provider_prereqs.sh
./yba_provider_prereqs.sh
```
##### Required variables

- `YDB_NS_BASENAME` :        Desired provider name. Will act as a base name for Universe namespace(s);

- `YDB_REGION` :             Region to deploy your Universe to;

- `YDB_AZ_[x]` :             Availability zone(s) to deploy your Universe to. To setup multiAZ configuration, provide several variables, following the `YDB_AZ_[x]` naming convention,where `[x]` is either a number or a name. At least one is required.\
Example:
```
export YDB_AZ_1="us-east1-b"
export YDB_AZ_2="us-east1-c"
export YDB_AZ_3="us-east1-d"
```

#### Provider creation job

This job consists of two containers – config generator (`yba-k8s-manager-cfgbuilder`) and the `yugaware-client` container. First one prepares required configuration files to pass them to the second. Edit the required variables and container images in the k8s YAML definition and apply it.
```
kubectl apply -f job-yamls/job-provider-create.yaml
```

##### Required variables - config generator container

- `YDB_NS_BASENAME` :        Desired provider name. Will act as a base name for Universe namespace(s);

- `YDB_REGION` :             Region to deploy your Universe to;

- `YDB_STORAGECLASS` :       Storage class for the Universe to use. *Note: you need a `StorageClass` with its `VolumeBindingMode` set to `WaitForFirstConsumer`;*

- `YDB_AZ_[x]` :             Availability zone(s) to deploy your Universe to. To setup multiAZ configuration, provide several variables, following the `YDB_AZ_[x]` naming convention, where `[x]` is either a number or a name. At least one is required.\
Example:
```
env:
 - name: YDB_AZ_1
   value: "us-east1-b"
 - name: YDB_AZ_2
   value: "us-east1-c"
 - name: YDB_AZ_3
   value: "us-east1-d"
```


##### Optional variables – config generator container


- `YDB_REGISTRY` :           Address of a private container registry to pull the Yugabyte Anywhere image from. Defaults to `quay.io/yugabyte/yugabyte`;

- `YDB_K8S_SERVER` :         Server address of the Kubernetes cluster. This must be set or `yb_kubeconfig_puller` SA needs to have `get,list` permissions on `services` in `kube-system` namespace to obtain it.

- `YDB_KUBECONFIG` :         Path to a Kubeconfig file for the provider configuration. *Note: in current version of toolkit this kubeconfig, even if supplied, is overridden by per-zone kubeconfigs;*

- `YDB_PULLSECRET` :         Path to a Pull Secret file for accessing the Yugabyte Anywhere repo / private registry. Don't set if a pull secret is not required;

- `YDB_TOLERATION_[x]` :     Description of a k8s taint toleration(s) to apply to your Universe's pods. Tolerations format: `key;operator;value;effect` . Naming convention same as in AZs.\
Example:
```
env:
 - name: YDB_TOLERATION_1
   value: "node.kubernetes.io/test;Equal;yugabyte;NoSchedule"
```

- `YDB_NODESELECT_[x]` :     Description of a NodeSelector(s) to use for your Universe's pods.  NodeSelectors format: `key;value` Naming convention same as in AZs.\
Example:
```
env:
 - name: YDB_NODESELECT_1
   value: "cloud.google.com/gke-nodepool;yugabyte"
```

##### Required variables -  `yugaware-client` container

- `YW_HOSTNAME` :            Hostname/IP address of the Platform host;

- `YW_API_TOKEN` :           API token that's been generated during the registration or through Platform UI;

### Creating a Universe

Edit the required variables and container images in the k8s YAML definition and apply it.
```
kubectl apply -f job-yamls/job-universe-create.yaml
```
#### Required variables

- `YW_HOSTNAME` :            Hostname/IP address of the Platform host;

- `YW_API_TOKEN` :           API token that's been generated during the registration or through Platform UI;

- `YDB_NS_BASENAME` :        Desired provider name. ;

- `YDB_REGION` :             Region to deploy your Universe to;

- `YDB_UNIVERSE_NAME` :      Desired name for the new Universe;


#### Optional variables

- `YW_INSTANCE_TYPE` :       Desired Pod size for the new Universe. `small` is the default size.

- `YW_ASSIGN_PUBLIC_IP` :    Assign a public IP address to the cluster;

- `YW_DISABLE_YSQL` :        Disable ysql;

- `YW_ENABLE_ENCRYPTION` :   Enable node-to-node and client-to-node encryption on the cluster;

- `YW_NODE_COUNT` :          Number of nodes to deploy (default 3);

- `YW_REPLICATION_FACTOR` :  Replication factor for the cluster (default 3);

- `YW_STATIC_PUBLIC_IP`      Assign a static public IP to the cluster;

- `YW_VERSION` :             The version of Yugabyte to deploy (defaults to yugaware version);

- `YW_VOLUME_SIZE` :         Volume size to use for cluster nodes.
