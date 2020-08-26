#! /usr/bin/env bash
source helper.sh

# echo "--> Waiting for Consul leader"
# while [ -z "$(curl -s -k $CONSUL_HTTP_ADDR/v1/status/leader)" ]; do
#   sleep 3
# done

# HOST_IP=$(ipconfig getifaddr en0)
# export OIDCDiscoveryURL="http://$HOST_IP:9000"
# export REDIRECT_URI1=$(minikube service consul-ui --https --url)/ui/oidc/callback
# export REDIRECT_URI2=http://localhost:8550/oidc/callback

echo "Setting up oidc-config"
tee oidc-config/config.json <<EOF
{
  "idp_name": "$OIDCDiscoveryURL",
  "port": 9000,
  "client_config": [
    {
      "client_id": "foo",
      "client_secret": "bar",
      "redirect_uris": [
        "$REDIRECT_URI1",
        "$REDIRECT_URI2"
      ]
    }
  ],
  "claim_mapping": {
    "openid": [ "sub" , "groups", "name" ],
    "email": [ "email", "email_verified" ],
    "profile": [ "name", "nickname" ],
    "groups": [ "groups" ]
  }
}
EOF
docker-compose up --force-recreate --remove-orphans -d
sleep 3
echo "--> Waiting for oidc"
while [ -z "$(curl -s -k $OIDCDiscoveryURL/.well-known/openid-configuration)" ]; do
  sleep 3
done