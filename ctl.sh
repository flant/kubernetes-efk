#!/bin/bash

set -e

! read -rd '' HELP_STRING <<"EOF"
Usage: ctl.sh [OPTION]... [-i|--install] KIBANA_HOST
   or: ctl.sh [OPTION]...

Install EFK (ElasticSearch, Fluentd, Kibana) stack to Kubernetes cluster.

Mandatory arguments:
  -i, --install                install into 'monitoring' namespace, override with '-n' option
  -u, --upgrade                upgrade existing installation, will reuse password and host names
  -d, --delete                 remove everything, including the namespace
  --storage-class-name         name of the storage class
  --storage-size               storage size with optional IEC suffix
  --memory-usage               java RSS limit

Optional arguments:
  -h, --help                   output this message
EOF

RANDOM_NUMBER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)
TMP_DIR="/tmp/prometheus-ctl-$RANDOM_NUMBER"
WORKDIR="$TMP_DIR/kubernetes-efk"
DEPLOY_SCRIPT="deploy.sh"
TEARDOWN_SCRIPT="teardown.sh"

MODE=""
USER=admin
USER_BASE64=$(echo -n "$USER" | base64 -w0)
NAMESPACE="kube-logging"
FIRST_INSTALL="true"
STORAGE_CLASS_NAME="rbd"
STORAGE_SIZE="20Gi"
MEMORY_USAGE="8192m"


TEMP=$(getopt -o i,u,d,h --long help,install,upgrade,delete,storage-class-name:,storage-size:,memory-usage: \
             -n 'ctl' -- "$@")

eval set -- "$TEMP"

while true; do
  case "$1" in
    -i | --install )
      MODE=install; shift ;;
    -u | --upgrade )
      MODE=upgrade; shift ;;
    -d | --delete )
      MODE=delete; shift ;;
    --storage-class-name )
      STORAGE_CLASS_NAME="$2"; shift 2;;
    --storage-size )
      STORAGE_SIZE="$2"; shift 2;;
    --memory-usage )
      MEMORY_USAGE="$2"; shift 2;;
    -h | --help )
      echo "$HELP_STRING"; exit 0 ;;
    -- )
      shift; break ;;
    * )
      break ;;
  esac
done

if [ -z "$MODE" ]; then echo "Mode of operation not provided. Use '-h' to print proper usage."; exit 1; fi

type curl >/dev/null 2>&1 || { echo >&2 "I require curl but it's not installed.  Aborting."; exit 1; }
type base64 >/dev/null 2>&1 || { echo >&2 "I require base64 but it's not installed.  Aborting."; exit 1; }
type git >/dev/null 2>&1 || { echo >&2 "I require git but it's not installed.  Aborting."; exit 1; }
type kubectl >/dev/null 2>&1 || { echo >&2 "I require kubectl but it's not installed.  Aborting."; exit 1; }
type jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed.  Aborting."; exit 1; }
type htpasswd >/dev/null 2>&1 || { echo >&2 "I require htpasswd but it's not installed. Please, install 'apache2-utils'. Aborting."; exit 1; }


mkdir -p "$TMP_DIR"
cd "$TMP_DIR"
git clone --depth 1 https://github.com/flant/kubernetes-efk.git
cd "$WORKDIR"


function install {
  PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
  PASSWORD_BASE64=$(echo -n "$PASSWORD" | base64 -w0)
  BASIC_AUTH_SECRET=$(echo "$PASSWORD" | htpasswd -ni admin | base64 -w0)
  # install basic-auth secret
  sed -i -e "s%##BASIC_AUTH_SECRET##%$BASIC_AUTH_SECRET%" -e "s%##PLAINTEXT_PASSWORD##%$PASSWORD_BASE64%" \
              manifests/ingress/basic-auth-secret.yaml
  # install ingress host
  sed -i -e "s/##KIBANA_HOST##/$KIBANA_HOST/g" manifests/ingress/ingress.yaml
  # set storage parameters
  sed -i -e "s/##STORAGE_CLASS_NAME##/$STORAGE_CLASS_NAME/g" \
         -e "s/##STORAGE_SIZE##/$STORAGE_SIZE/g" \
              manifests/es-data/es-data.yaml
  # set memory usage
  find manifests/ -type f -exec \
          sed -i "s/##MEMORY_USAGE##/$MEMORY_USAGE/g" {} +
  $DEPLOY_SCRIPT
  echo '##################################'
  echo "Login: admin"
  echo "Password: $PASSWORD"
  echo '##################################'
}

function upgrade {
  PASSWORD=$(kubectl -n "$NAMESPACE" get secret basic-auth-secret -o json | jq .data.password -r | base64 -d)
  PASSWORD_BASE64=$(echo -n "$PASSWORD" | base64 -w0)
  KIBANA_HOST=$(kubectl -n "$NAMESPACE" get ingress kibana-ingress -o json | jq -r '.spec.rules[0].host')
  BASIC_AUTH_SECRET=$(echo "$PASSWORD" | htpasswd -ni admin | base64 -w0)
  # install basic-auth secret
  sed -i -e "s%##BASIC_AUTH_SECRET##%$BASIC_AUTH_SECRET%" -e "s%##PLAINTEXT_PASSWORD##%$PASSWORD_BASE64%" \
              manifests/ingress/basic-auth-secret.yaml
  # install ingress host
  sed -i -e "s/##KIBANA_HOST##/$KIBANA_HOST/g" manifests/ingress/ingress.yaml
  # set storage parameters
  sed -i -e "s/##STORAGE_CLASS_NAME##/$STORAGE_CLASS_NAME/g" \
         -e "s/##STORAGE_SIZE##/$STORAGE_SIZE/g" \
              manifests/es-data/es-data.yaml
  # set memory usage
  find manifests/ -type f -exec \
          sed -i "s/##MEMORY_USAGE##/$MEMORY_USAGE/g" {} +
  $DEPLOY_SCRIPT
}

if [ "$MODE" == "install" ]
then
  if [ -z "$1" ] && [ -z "$2" ]; then echo "One positional arguments required. See '--help' for more information."; exit 1; fi
  KIBANA_HOST="$1"
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 && FIRST_INSTALL="false"
  if [ "$FIRST_INSTALL" == "true" ]
  then
    install
  else
    echo "Namespace $NAMESPACE exists. Please, delete or run with the --upgrade option it to avoid shooting yourself in the foot."
  fi
elif [ "$MODE" == "upgrade" ]
then
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || (echo "Namespace '$NAMESPACE' does not exist. Please, install operator with '-i' option first." ; exit 1)
  upgrade
elif [ "$MODE" == "delete" ]
then
  $TEARDOWN_SCRIPT || true
  kubectl delete ns "$NAMESPACE" || true
fi

function cleanup {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
