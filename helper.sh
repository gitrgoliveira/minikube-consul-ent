#! /usr/bin/env bash

export CONSUL_HTTP_ADDR=$(minikube service consul-ui --https --url)
export CONSUL_HTTP_TOKEN=$(kubectl get secrets consul-bootstrap-acl-token -o json | jq -r .data.token | base64 -D )
echo -n | openssl s_client -connect ${CONSUL_HTTP_ADDR//https:\/\/}  | \
    sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > cluster-1.cert
export CONSUL_CACERT=cluster-1.cert
export CONSUL_TLS_SERVER_NAME=127.0.0.1


function consul1 {
    CONSUL_HTTP_ADDR=$(minikube service consul-ui --https --url)
    CONSUL_HTTP_TOKEN=$(kubectl get secrets consul-bootstrap-acl-token -o json | jq -r .data.token | base64 -D )
    echo -n | openssl s_client -connect ${CONSUL_HTTP_ADDR//https:\/\/}  | \
        sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > cluster-1.cert

    echo "consul $1 -http-addr=$CONSUL_HTTP_ADDR -token=$CONSUL_HTTP_TOKEN -ca-file=cluster-1.cert -tls-server-name=127.0.0.1 $2" | bash
    rm -f cluster-1.cert
}
