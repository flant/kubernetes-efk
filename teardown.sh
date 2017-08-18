#!/bin/bash

if [ -z "${NAMESPACE}" ]; then
    NAMESPACE=kube-logging
fi

kctl() {
    kubectl --namespace "$NAMESPACE" "$@"
}

kctl delete -f manifests/es-master
kctl delete -f manifests/es-client
kctl delete -f manifests/es-data
kctl delete -f manifests/es-curator
kctl delete -f manifests/fluentd
kctl delete -f manifests/kibana
