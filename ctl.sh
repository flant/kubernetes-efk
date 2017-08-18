#!/usr/bin/env bash

set -e

! read -rd '' HELP_STRING <<"EOF"
Usage: ctl.sh [OPTION]... --type [aws|haproxy]
Install nginx ingress controller to Kubernetes cluster.
Mandatory arguments:
  -i, --install                install into 'kube-nginx-ingress' namespace
  -u, --upgrade                upgrade existing installation, will reuse password and host names
  -d, --delete                 remove everything, including the namespace
  -t, --type                   load balancer type, either 'aws' or 'haproxy'
Optional arguments:
  -h, --help                   output this message
      --ingress-replicas       set ingress controller replicas count
EOF

RANDOM_NUMBER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)
TMP_DIR="/tmp/prometheus-ctl-$RANDOM_NUMBER"
WORKDIR="$TMP_DIR/kubernetes-nginx-ingress"

FIRST_INSTALL="true"
STORAGE_CLASS_NAME="rbd"
STORAGE_SIZE="20Gi"

TEMP=$(getopt -o i,u,d,n:,h --long namespace:,help,install,upgrade,delete,retention:,storage-class-name:,storage-size:,memory-usage: \
             -n 'ctl.sh' -- "$@")

eval set -- "$TEMP"

while true; do
  case "$1" in
    -i | --install )
      MODE=install; shift ;;
    -u | --upgrade )
      MODE=upgrade; shift ;;
    -d | --delete )
      MODE=delete; shift ;;
    --replicas )
      INGRESS_CONTROLLER_REPLICAS="$2"; shift 2;;
    -t | --type )
      TYPE="$2"; shift 2;;
    -h | --help )
      echo "$HELP_STRING"; exit 0 ;;
    -- )
      shift; break ;;
    * )
      break ;;
  esac
done

case $TYPE in 
  aws) 
    TYPE="aws";;
  haproxy)
    TYPE="haproxy";;
  *)
    echo "Load balancer type is invalid. Please, consult with the '-h' option output."
    exit 1
    ;;
esac 

type git >/dev/null 2>&1 || { echo >&2 "I require git but it's not installed.  Aborting."; exit 1; }
type kubectl >/dev/null 2>&1 || { echo >&2 "I require kubectl but it's not installed.  Aborting."; exit 1; }
type jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed.  Aborting."; exit 1; }

mkdir -p "$TMP_DIR"
cd "$TMP_DIR"
git clone --depth 1 https://github.com/flant/kubernetes-nginx-ingress.git
cd "$WORKDIR"


function install {
  kubectl create ns kube-nginx-ingress
  # set ingress controller replicas count secret
  sed -i -e "s%##INGRESS_CONTROLLER_REPLICAS##%$INGRESS_CONTROLLER_REPLICAS%g" manifests/ingress-controller/nginx.yaml
  kctl apply -Rf manifests/ingress-controller/
  kctl apply -Rf manifests/$TYPE/
}

function upgrade {
  # get current replica count and load balancer type
  if $(kctl get deploy nginx > /dev/null 2>/dev/null); then
    INGRESS_CONTROLLER_REPLICAS=$(kctl get deploy nginx -o json | jq -r '.spec.replicas')
  else
    INGRESS_CONTROLLER_REPLICAS=3
  fi
  # set ingress controller replicas count secret
  sed -i -e "s%##INGRESS_CONTROLLER_REPLICAS##%$INGRESS_CONTROLLER_REPLICAS%g" manifests/ingress-controller/nginx.yaml

  if [[ $(kctl get svc default-http-backend -o json | jq -r '.spec.clusterIP') != "None" ]] ; then
    kctl delete svc default-http-backend
  fi

  kctl apply -Rf manifests/ingress-controller/
  if $(kctl get ds/nginx > /dev/null 2>/dev/null); then
    kctl delete ds/nginx --grace-period=1
  fi
  kctl apply -Rf manifests/$TYPE/
  if $(kctl get cm/nginx-template > /dev/null 2>/dev/null); then
    kctl delete cm/nginx-template
  fi
}

if [ "$MODE" == "install" ]
then
  kubectl get ns kube-nginx-ingress >/dev/null 2>&1 && FIRST_INSTALL="false"
  if [ "$FIRST_INSTALL" == "true" ]
  then
    install
  else
    echo "Namespace kube-nginx-ingress exists. Please, delete or run with the --upgrade option it to avoid shooting yourself in the foot."
  fi
elif [ "$MODE" == "upgrade" ]
then
  upgrade
elif [ "$MODE" == "delete" ]
then
  kubectl delete clusterrolebinding/kube-nginx-ingress || true
  kubectl delete clusterrole/kube-nginx-ingress || true
  kubectl delete ns kube-nginx-ingress || true
fi

function cleanup {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
