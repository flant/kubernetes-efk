#!/bin/bash

if [ -z "${NAMESPACE}" ]; then
    NAMESPACE=kube-logging
fi

kubectl create namespace "$NAMESPACE"

kctl() {
    kubectl --namespace "$NAMESPACE" "$@"
}

kctl apply -f manifests/es-master

printf "Waiting for es-master"
until kctl get deploy es-master > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get svc elasticsearch-discovery > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get svc elasticsearch > /dev/null 2>&1; do sleep 1; printf "."; done
echo "Done!"

kctl apply -f manifests/es-client
kctl apply -f manifests/es-data

printf "Waiting for es-client and es-data"
until kctl get deploy es-client > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get statefulset es-data > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get deploy es-master > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get svc elasticsearch-data > /dev/null 2>&1; do sleep 1; printf "."; done
echo "Done!"

echo "Deploying es-curator"
kctl apply -f manifests/es-curator

echo "Deploying fluentd"
kctl apply -f manifests/fluentd

echo "Deploying kibana"
kctl apply -f manifests/kibana
