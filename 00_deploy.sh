#! /usr/bin/env bash
# The tool used to generate manifests is helm.
set -e
set -o pipefail

# If using minikube
minikube start --vm=true --driver=hyperkit --cpus=4

if kubectl get secret consul-license 2>/dev/null ; then
    kubectl delete secret consul-license
fi
kubectl create secret generic consul-license --from-file=license=consul_v2lic.hclic

## Writing all of the configuration
if kubectl get secret consul-gossip-encryption-key 2>/dev/null ; then
    kubectl delete secret consul-gossip-encryption-key
fi
kubectl create secret generic consul-gossip-encryption-key --from-literal=key=$(consul keygen)

if kubectl get secret snapshot-agent-config 2>/dev/null ; then
    kubectl delete secret snapshot-agent-config
fi
kubectl create secret generic snapshot-agent-config  --from-file=./snaphshot_agent.json

CONSUL_HELM_VERSION=0.24.1
helm repo add hashicorp https://helm.releases.hashicorp.com

if helm status consul > /dev/null; then
helm upgrade consul hashicorp/consul \
    --version $CONSUL_HELM_VERSION  \
    -f values.yaml \
    --force \
    --atomic \
    --wait
else
helm install consul hashicorp/consul \
    --version $CONSUL_HELM_VERSION \
    -f values.yaml \
    --wait
fi

#------------------------------
# to check what consul-helm applies to the cluster.
# rm -rf manifests
# mkdir manifests
# helm template consul hashicorp/consul \
#     --version $CONSUL_HELM_VERSION \
#     -f values.yaml  \
#     --output-dir ./manifests > /dev/null

source helper.sh

echo "--> Waiting for Consul leader"
while [ -z "$(curl -s -k $CONSUL_HTTP_ADDR/v1/status/leader)" ]; do
  sleep 3
done

### Creating the namespaces and registering services
consul namespace write namespaces/namespace_ops-team.json
consul namespace write namespaces/namespace_app-team.json
consul services register namespaces/svc*
consul acl token create \
      -namespace app-team \
      -description "App Team Administrator" \
      -policy-name "namespace-management"

consul acl token create \
      -namespace ops-team \
      -description "Ops Team Administrator" \
      -policy-name "namespace-management"

# Updating the anonymous policy to allow namespace search
consul acl policy update  -name anonymous-token-policy -rules=- <<EOF
namespace_prefix "" {
  node_prefix "" {
    policy = "read"
  }
  service_prefix "" {
    policy = "read"
  }
}
EOF

### setting up OIDC
consul acl policy create -name eng-ro \
   -rules='namespace_prefix "" {service_prefix "" { policy="read" } node_prefix "" { policy="read" }}' || true
consul acl role create -name eng-ro -policy-name eng-ro || true


HOST_IP=$(ipconfig getifaddr en0)
export OIDCDiscoveryURL="http://$HOST_IP:9000"
export REDIRECT_URI1=$(minikube service consul-ui --https --url)/ui/oidc/callback
export REDIRECT_URI2=http://localhost:8550/oidc/callback
source simple-oidc-provider.sh

echo "Setting up OIDC"
tee auth_config.json <<EOF
{
    "VerboseOIDCLogging": true,
    "OIDCDiscoveryURL": "$OIDCDiscoveryURL",
    "OIDCClientID": "foo",
    "OIDCClientSecret": "bar",
    "BoundAudiences": [ "foo" ],
    "AllowedRedirectURIs": [
       "$REDIRECT_URI1",
       "$REDIRECT_URI2"
    ],
    "ClaimMappings": {
       "name": "first_name",
       "email": "email"
    },
    "ListClaimMappings": {
        "groups": "groups"
    }
}
EOF
consul acl auth-method create -type oidc \
    -name=simple-oidc \
    -max-token-ttl=5m \
    -config=@auth_config.json || true

# resetting bind rules
consul acl binding-rule list -method=simple-oidc -format=json | jq -r .[].ID | awk '{ print "consul acl binding-rule delete -id " $1}' | bash || true

consul acl binding-rule create \
    -method=simple-oidc \
    -bind-type=role \
    -bind-name=eng-ro \
    -selector='engineering in list.groups' || true

consul acl binding-rule create \
    -method=simple-oidc \
    -bind-type=service \
    -bind-name='eng-${value.first_name}' \
    -selector='engineering in list.groups' || true

minikube service list
echo "Consul UI $(minikube service consul-ui --https --url)"
echo "Login token $(kubectl get secrets consul-bootstrap-acl-token -o json | jq -r .data.token | base64 -D )"

## Namespace Demo
# Using Consul pod
# kubectl exec -it consul-server-0 -- apk add bind-tools
# kubectl exec -it consul-server-0 -- dig @127.0.0.1 -p 8600 prometheus.service.ops-team.consul
# kubectl exec -it consul-server-0 -- dig fabulous_frontend.service.app-team.consul

# Using port forwarding
# kubectl port-forward svc/consul-server 8600:8600 &
# dig @127.0.0.1 -p 8600 +tcp prometheus.service.ops-team.consul
# dig @127.0.0.1 -p 8600 +tcp fabulous_frontend.service.app-team.consul
# dig @127.0.0.1 -p 8600 +tcp consul.service.consul

## Snapshot agent logs to see snapshots being taken
# kubectl get pods | grep snapshot | awk '{print "kubectl logs " $1}' | bash

## SSO login command
# consul login -type=oidc -method=simple-oidc -token-sink-file=./token
# cat token

## Audit logs
# kubectl get pods -l component=server -o name | awk '{ print "kubectl exec "$1" -- grep -ri <search word> /consul/data/audit/" }' |bash
# kubectl get pods -l component=server -o name | awk '{ print "kubectl exec "$1" -- grep -ri bootstrap /consul/data/audit/" }' |bash
# kubectl get pods -l component=server -o name | awk '{ print "kubectl exec "$1" -- grep -r OIDC /consul/data/audit/" }' |bash


### useful shortcuts ###
# kubectl get pods | grep <pod name> | awk '{print $1}' | xargs kubectl delete pod
# kubectl get pods | grep consul-server-b- | awk '{print $1}' | xargs kubectl delete pod
# consul acl binding-rule list -method=<oidc-method> -format=json | jq -r .[].ID | awk '{ print "consul acl binding-rule delete -id " $1}' | bash
# consul acl binding-rule list -method=simple-oidc -format=json | jq -r .[].ID | awk '{ print "consul acl binding-rule delete -id " $1}' | bash
# consul acl binding-rule list -method=aad -format=json | jq -r .[].ID | awk '{ print "consul acl binding-rule delete -id " $1}' | bash
