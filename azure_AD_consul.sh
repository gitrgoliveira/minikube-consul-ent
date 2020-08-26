#!/bin/sh

export AUTH_SP_NAME=ric-consul-oidc
export AUTH_CLIENT_SECRET=MyConsulTestPasswordChangeMe
export AUTH_TENANT=$(az account show |jq -r '.tenantId')

export AUTH_REDIRECT_URL1=http://localhost:8550/oidc/callback
export AUTH_REDIRECT_URL2=$(minikube service consul-ui --https --url)/ui/oidc/callback

az ad app create --display-name ${AUTH_SP_NAME} --password ${AUTH_CLIENT_SECRET} --reply-urls ${AUTH_REDIRECT_URL1} ${AUTH_REDIRECT_URL2} --output none
export AUTH_CLIENT_ID=$(az ad app list --display-name ${AUTH_SP_NAME} |jq -r '.[0].appId')

source helper.sh

cat <<EOF > auth.json
  {
    "Name": "aad",
    "Type": "oidc",
    "Description": "azuread",
    "MaxTokenTTL": "60m",
    "Config": {
        "AllowedRedirectURIs": [
            "${AUTH_REDIRECT_URL1}",
            "${AUTH_REDIRECT_URL2}"
        ],
        "BoundAudiences": [
            "${AUTH_CLIENT_ID}"
        ],
        "ClaimMappings": {
          "sub": "sub",
          "email": "email"
         },
         "ListClaimMappings": {
            "roles": "groups"
        },
        "OIDCClientID": "$AUTH_CLIENT_ID",
        "OIDCClientSecret": "$AUTH_CLIENT_SECRET",
        "OIDCDiscoveryURL": "https://login.microsoftonline.com/${AUTH_TENANT}/v2.0",
        "VerboseOIDCLogging": true
    }
  }
EOF

curl --insecure --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" ${CONSUL_HTTP_ADDR}/v1/acl/auth-method -X PUT --data @auth.json | jq

consul acl binding-rule create
  -bind-name=admin \
  -bind-type=role \
  -method=aad \
  -selector='list.groups is empty'

consul acl role create -name admin -policy-name global-management

# consul login -type=oidc -method=aad -token-sink-file=./token