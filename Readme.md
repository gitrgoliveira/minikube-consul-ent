# Consul Enterprise features demo
The idea of this repo is to demo Consul Enterprise features of a single cluster using k8s helm chart for Consul.

Please read the requirements before proceeding.

## Requirements
1. Helm3 cli
2. minikube (with hyperkit) & kubectl
3. Consul cli (v1.8+)
4. Consul helm chart.
   1. `git clone https://github.com/hashicorp/consul-helm.git`
5. A Consul Enterprise trial license
   1. This is setup *in line 12* of `00_deploy.sh`

## Setup steps
1. Run `00_deploy.sh` which will:
   1. Start minikube
   2. *In **line 12** it will setup the consul license*
   3. Install Consul Enterprise edition with ACLs bootstrapped and audit logs enabled
   4. Start `qlik/simple-oidc-provider` to mock SSO
   5. Configure SSO in Consul
      1. For usernames and passwords see `./oidc-config/users.json`

2. To access the Consul cluster you will need to `source helper.sh` from your terminal.

## Demos steps

### Consul Namespaces

1. Redirect DNS queries to Consul with:
   1. `kubectl port-forward svc/consul-server 8600:8600 &`

2. You can run queries on those services using:
   1. `dig @127.0.0.1 -p 8600 +tcp prometheus.service.ops-team.consul`
   2. `dig @127.0.0.1 -p 8600 +tcp fabulous_frontend.service.app-team.consul`
   3. `dig @127.0.0.1 -p 8600 +tcp consul.service.consul`

3. Clean up with `killall kubectl`

> *The first 2 queries will fail if you do them after the ACLs are applied*

### Snapshot Agent demo

1. Check for the existence of a lock on Consul UI KV store.
2. Check the snapshot agents are saving the snapshot, by exposing their logs.
   1. `kubectl get pods | grep snapshot | awk '{print "kubectl logs " $1}' | bash`

*Note: Consul Snapshot Agent does not work with Consul Enterprise embedded license.*

### SSO / OIDC
**!Use your browser in incognito mode!**
1. Setup your environment with `source helper.sh`
2. Access the UI using your browser in *incognito mode* and login as someone from Sales/Admin to see your login be refused
   1. For usernames and passwords see `./oidc-config/users.json`
3. Open a *new incognito window* and login as someone from engineering to see your login approved.
   1. This is a read-only login for services and nodes.
4. (optional) Run `consul login -type=oidc -method=simple-oidc -token-sink-file=./token` and see you have a new token file. (take care because simple-OIDC will remember you!)

### Audit logs
1. run `kubectl get pods -l component=server -o name | awk '{ print "kubectl exec "$1" -- grep -r Bootstrap /consul/data/audit/" }' |bash`
   1. This will allow you to quickly see where/when the bootstrap token was used
2. run `kubectl get pods -l component=server -o name | awk '{ print "kubectl exec "$1" -- grep -r OIDC /consul/data/audit/" }' |bash`
   1. This allows you to see when the OIDC method was used and the **accessor_id**
   2. Get the accessor ID and run `consul acl token read -id <accessor_id>` to see who logged in!

### Bonus Demo !
Tim Arenz was kind enough to share a script that sets up Consul OIDC to work with AzureAD.

To use it, you'll need to:
1. run `azure_AD_consul.sh`
2. login via UI or using `consul login -type=oidc -method=aad -token-sink-file=./token`

# Clean up
You can use the bash script `02_cleanup.sh`
