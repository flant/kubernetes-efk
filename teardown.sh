#!/bin/bash

if [ -z "${NAMESPACE}" ]; then
    NAMESPACE=kube-logging
fi

kctl() {
    kubectl --namespace "$NAMESPACE" "$@"
}

kctl delete -f manifests/elasticsearch/es-master
kctl delete -f manifests/elasticsearch/es-client
kctl delete -f manifests/elasticsearch/es-data
kctl delete -f manifests/elasticsearch/es-curator
kctl delete -f manifests/fluentd
kctl delete -f manifests/kibana
