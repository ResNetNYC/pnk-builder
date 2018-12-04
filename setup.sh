#!/bin/bash

set -x

PACKER_URL=https://releases.hashicorp.com/packer/1.3.2/packer_1.3.2_linux_amd64.zip
PLUGIN_URL=https://github.com/solo-io/packer-builder-arm-image

# Install Packer
wget ${PACKER_URL} -O packer.zip
unzip packer.zip packer
# Check if plugin built and copy into place
if [[ ! -f packer ]]; then {
    echo "ERROR: Packer failed to install."
    exit 1
}; fi


# Build plugin
mkdir -p $GOPATH/src/github.com/solo-io/
pushd $GOPATH/src/github.com/solo-io/
# clean up potential residual files from previous builds
rm -rf packer-builder-arm-image
git clone --depth 1 ${PLUGIN_URL} packer-builder-arm-image
pushd ./packer-builder-arm-image
go build

# Check if plugin built and copy into place
if [[ ! -f packer-builder-arm-image ]]; then {
    echo "ERROR: Plugin failed to build."
    exit 1
} else {
    mkdir -p $HOME/.packer.d/plugins
    cp packer-builder-arm-image $HOME/.packer.d/plugins/
}; fi

