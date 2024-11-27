#!/usr/bin/env bash

# Copyright 2024 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

readonly SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE}")"/.. && pwd)"

# Keep outer module cache so we don't need to redownload them each time.
# The build cache already is persisted.
readonly GOMODCACHE="$(go env GOMODCACHE)"
readonly GO111MODULE="on"
readonly GOFLAGS="-mod=mod"
readonly GOPATH="$(mktemp -d)"
readonly MIN_REQUIRED_GO_VER="$(go list -m -f '{{.GoVersion}}')"

function go_version_matches {
  go version | perl -ne "exit 1 unless m{go version go([0-9]+.[0-9]+)}; exit 1 if (\$1 < ${MIN_REQUIRED_GO_VER})"
  return $?
}

if ! go_version_matches; then
  echo "Go v${MIN_REQUIRED_GO_VER} or later is required to run code generation"
  exit 1
fi

export GOMODCACHE GO111MODULE GOFLAGS GOPATH

# Even when modules are enabled, the code-generator tools always write to
# a traditional GOPATH directory, so fake on up to point to the current
# workspace.
mkdir -p "$GOPATH/src/sigs.k8s.io"
ln -s "${SCRIPT_ROOT}" "$GOPATH/src/sigs.k8s.io/multi-network-api"

readonly OUTPUT_PKG=sigs.k8s.io/multi-network-api/pkg/client
readonly APIS_PKG=sigs.k8s.io/multi-network-api
readonly CLIENTSET_NAME=versioned
readonly CLIENTSET_PKG_NAME=clientset
readonly VERSIONS=(v1alpha1)

MN_INPUT_DIRS_SPACE=""
MN_INPUT_DIRS_COMMA=""
for VERSION in "${VERSIONS[@]}"
do
  MN_INPUT_DIRS_SPACE+="${APIS_PKG}/apis/${VERSION} "
  MN_INPUT_DIRS_COMMA+="${APIS_PKG}/apis/${VERSION},"
done
MN_INPUT_DIRS_SPACE="${MN_INPUT_DIRS_SPACE%,}" # drop trailing space
MN_INPUT_DIRS_COMMA="${MN_INPUT_DIRS_COMMA%,}" # drop trailing comma


if [[ "${VERIFY_CODEGEN:-}" == "true" ]]; then
  echo "Running in verification mode"
  readonly VERIFY_FLAG="--verify-only"
fi

readonly COMMON_FLAGS="${VERIFY_FLAG:-} --go-header-file ${SCRIPT_ROOT}/hack/boilerplate/boilerplate.generatego.txt"

for VERSION in "${VERSIONS[@]}"
do
  echo "Generating ${VERSION} CRDs at ${APIS_PKG}/apis/${VERSION}"
  go run sigs.k8s.io/controller-tools/cmd/controller-gen crd \
    object:headerFile=${SCRIPT_ROOT}/hack/boilerplate/boilerplate.generatego.txt \
    paths="${APIS_PKG}/apis/${VERSION}" \
    output:crd:dir="${SCRIPT_ROOT}/config/crds"
done

# throw away
new_report="$(mktemp -t "$(basename "$0").api_violations.XXXXXX")"

echo "Generating openapi schema"
go run k8s.io/kube-openapi/cmd/openapi-gen \
  --output-file zz_generated.openapi.go \
  --report-filename "${new_report}" \
  --output-dir "pkg/generated/openapi" \
  --output-pkg "sigs.k8s.io/multi-network-api/pkg/generated/openapi" \
  ${COMMON_FLAGS} \
  $MN_INPUT_DIRS_SPACE \
  k8s.io/apimachinery/pkg/apis/meta/v1 \
  k8s.io/apimachinery/pkg/runtime \
  k8s.io/apimachinery/pkg/version


echo "Generating apply configuration"
go run k8s.io/code-generator/cmd/applyconfiguration-gen \
  --openapi-schema <(go run ${SCRIPT_ROOT}/cmd/modelschema) \
  --output-dir "apis/applyconfiguration" \
  --output-pkg "${APIS_PKG}/apis/applyconfiguration" \
  ${COMMON_FLAGS} \
  ${MN_INPUT_DIRS_SPACE}


# Temporary hack until https://github.com/kubernetes/kubernetes/pull/124371 is released
function fix_applyconfiguration() {
  local package="$1"
  local version="$(basename $1)"

  echo $package
  echo $version
  pushd $package > /dev/null

  # Replace import
  for filename in *.go; do
    import_line=$(grep "$package" "$filename")
    if [[ -z "$import_line" ]]; then
      continue
    fi
    import_prefix=$(echo "$import_line" | awk '{print $1}')
    sed -i'.bak' -e "s,${import_prefix} \"sigs.k8s.io/multi-network-api/${package}\",,g" "$filename"
    sed -i'.bak' -e "s,\[\]${import_prefix}\.,\[\],g" "$filename"
    sed -i'.bak' -e "s,&${import_prefix}\.,&,g" "$filename"
    sed -i'.bak' -e "s,*${import_prefix}\.,*,g" "$filename"
    sed -i'.bak' -e "s,^\t${import_prefix}\.,,g" "$filename"
  done

  rm *.bak
  go fmt .
  find . -type f -name "*.go" -exec sed -i'.bak' -e "s,import (),,g" {} \;
  rm *.bak
  go fmt .

  popd > /dev/null
}

export -f fix_applyconfiguration
find apis/applyconfiguration/apis -name "v*" -type d -exec bash -c 'fix_applyconfiguration $0' {} \;

echo "Generating clientset at ${OUTPUT_PKG}/${CLIENTSET_PKG_NAME}"
go run k8s.io/code-generator/cmd/client-gen \
  --clientset-name "${CLIENTSET_NAME}" \
  --input-base "${APIS_PKG}" \
  --input "${MN_INPUT_DIRS_COMMA//${APIS_PKG}/}" \
  --output-dir "pkg/client/${CLIENTSET_PKG_NAME}" \
  --output-pkg "${OUTPUT_PKG}/${CLIENTSET_PKG_NAME}" \
  --apply-configuration-package "${APIS_PKG}/apis/applyconfiguration" \
  ${COMMON_FLAGS}

echo "Generating listers at ${OUTPUT_PKG}/listers"
go run k8s.io/code-generator/cmd/lister-gen \
  --output-dir "pkg/client/listers" \
  --output-pkg "${OUTPUT_PKG}/listers" \
  ${COMMON_FLAGS} \
  ${MN_INPUT_DIRS_SPACE}

echo "Generating informers at ${OUTPUT_PKG}/informers"
go run k8s.io/code-generator/cmd/informer-gen \
  --versioned-clientset-package "${OUTPUT_PKG}/${CLIENTSET_PKG_NAME}/${CLIENTSET_NAME}" \
  --listers-package "${OUTPUT_PKG}/listers" \
  --output-dir "pkg/client/informers" \
  --output-pkg "${OUTPUT_PKG}/informers" \
  ${COMMON_FLAGS} \
  ${MN_INPUT_DIRS_SPACE}

echo "Generating ${VERSION} register at ${APIS_PKG}/apis/${VERSION}"
go run k8s.io/code-generator/cmd/register-gen \
  --output-file zz_generated.register.go \
  ${COMMON_FLAGS} \
  ${MN_INPUT_DIRS_SPACE}

for VERSION in "${VERSIONS[@]}"
do
  echo "Generating ${VERSION} deepcopy at ${APIS_PKG}/apis/${VERSION}"
  go run sigs.k8s.io/controller-tools/cmd/controller-gen \
    object:headerFile=${SCRIPT_ROOT}/hack/boilerplate/boilerplate.generatego.txt \
    paths="${APIS_PKG}/apis/${VERSION}"
done
