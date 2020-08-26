#! /usr/bin/env bash

minikube delete
rm -f cluster-1.cert
docker-compose down -v