#!/bin/bash

set -eu -o pipefail
# set -x
export LANG=C LC_ALL=C
cd $(dirname $0)

### Constants
# April 11, 2019
DOCKER_IMAGE="docker:18.09-dind"
# March 14, 2019
BUILDKIT_IMAGE="moby/buildkit:v0.4.0"


### Common
function INFO(){
    echo -e "\e[104m\e[97m[INFO]\e[49m\e[39m $@"
}
function bb::volume_name(){
    echo "buildbench-$1"
}
function bb::container_name(){
    echo "buildbench-$1"
}
function bb::dummy_file_name(){
    echo "buildbench-dummy"
}
function bb::test(){
    local builder="$1"
    local dir="$2"
    local csv="$3"
    local n="$4"
    INFO "Initializing ${builder}"
    ${builder}::prune || true
    ${builder}::init
    for i in $(seq 1 ${n});do
        INFO "${i} of ${n}: ${builder}: preparing"
        rm -f ${dir}/$(bb::dummy_file_name)
        ${builder}::prepare
        local desc="${i} of ${n}: ${builder} #1 (clean env)"
        INFO "${desc}: starting"
        local begin=$(date +%s.%N)
        ${builder}::build ${dir}
        local end=$(date +%s.%N)
        local took=$(echo ${end}-${begin} | bc)
        INFO "${desc}: done, took ${took} seconds"
        echo "${builder}-1,${took},${begin},${end}" >> ${csv}
        ${builder}::prune
    done
}

### Docker
function docker::init(){
    docker pull ${DOCKER_IMAGE}
    INFO "Docker version"
    docker run --rm ${DOCKER_IMAGE} docker --version
}
function docker::prepare(){
    INFO "begin prepare docker"
    docker volume create $(bb::volume_name docker)
    docker run --privileged --name $(bb::container_name docker) -d -v $(bb::volume_name docker):/var/lib/docker ${DOCKER_IMAGE} \
           -s overlay2
    INFO "prepare docker success"
}
function docker::build(){
    INFO "begin docker build"
    local dir="$1"
    INFO "[debug] ${dir}"
    docker run -v ${dir}:/workspace -w /workspace --rm --link $(bb::container_name docker):docker -e DOCKER_HOST=tcp://docker:2375 ${DOCKER_IMAGE} \
           docker build -t foo -q . > /dev/null 2>&1
    INFO "docker build success"
}
function docker::prune(){
    docker rm -f $(bb::container_name docker)
    docker volume rm -f $(bb::volume_name docker)
}

### BuildKit
function buildkit::init(){
    docker pull ${BUILDKIT_IMAGE}
    INFO "BuildKit version"
    docker run --rm ${BUILDKIT_IMAGE} --version
}
function buildkit::prepare(){
    docker volume create $(bb::volume_name buildkit)
    docker run --privileged --name $(bb::container_name buildkit) -d -v $(bb::volume_name buildkit):/var/lib/buildkit -p 1234:1234 ${BUILDKIT_IMAGE} \
           --addr tcp://0.0.0.0:1234
}
function buildkit::build(){
    local dir="$1"
    docker run \
           -v ${dir}:/workspace -w /workspace \
           --rm \
           --link $(bb::container_name buildkit):buildkit \
           -e BUILDKIT_HOST=tcp://buildkit:1234 \
           --entrypoint buildctl \
           ${BUILDKIT_IMAGE} \
           build --frontend=dockerfile.v0 --local context=. --local dockerfile=. > /dev/null 2>&1
}
function buildkit::prune(){
    docker rm -f $(bb::container_name buildkit)
    docker volume rm -f $(bb::volume_name buildkit)
}



### Main
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 DIR CSV N"
    exit 1
fi
DIR=$(realpath "$1")
CSV="$2"
N="$3"

builders=(docker buildkit)

INFO "DEBUG DIR ${DIR}"
INFO "DEBUG CSV ${CSV}"
INFO "DEBUG N ${N}"

for builder in ${builders[@]}; do
    only=ONLY_$(echo ${builder} | tr a-z A-Z)
    if [[ ! -z ${!only-} ]]; then
        INFO "Only running ${builder}"
        bb::test ${builder} ${DIR} ${CSV} ${N}
        exit
    fi
done

for builder in ${builders[@]}; do
    disable=DISABLE_$(echo ${builder} | tr a-z A-Z)
    if [[ ! -z ${!disable-} ]]; then
        INFO "Skipping ${builder}"
    else
        bb::test ${builder} ${DIR} ${CSV} ${N}
    fi
done