#!/bin/bash

set -eu -o pipefail
# set -x
export LANG=C LC_ALL=C
cd $(dirname $0)

BUILDKIT_IMAGE="moby/buildkit:latest"


### Common
function INFO(){
    echo -e "\e[104m\e[97m[INFO]\e[49m\e[39m $@"
}
function bb::volume_name(){
    echo "buildbench-$1"
}
function bb::network_name(){
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
    local dindimg="$5"

    INFO "Initializing ${builder}"
    ${builder}::prune || true
    ${builder}::init ${dindimg}
    for i in $(seq 1 ${n});do
        INFO "${i} of ${n}: ${builder}: preparing"
        rm -f ${dir}/$(bb::dummy_file_name)
        ${builder}::prepare ${dindimg}
        local desc="${i} of ${n}: ${builder} #1 (clean env)"
        INFO "${desc}: starting"
        local begin=$(date +%s.%N)
        ${builder}::build ${dir} ${dindimg}
        local end=$(date +%s.%N)
        local took=$(echo ${end}-${begin} | bc)
        INFO "${desc}: done, took ${took} seconds"
        echo "${builder}-1,${took},${begin},${end}" >> ${csv}
        desc="${i} of ${n}: ${builder} #2 (with dummy modification. cache can be potentially used.)"
        date > ${dir}/$(bb::dummy_file_name)
        INFO "${desc}: starting"
        local begin=$(date +%s.%N)
        ${builder}::build ${dir} ${dindimg}
        local end=$(date +%s.%N)
        local took=$(echo ${end}-${begin} | bc)
        INFO "${desc}: done, took ${took} seconds"
        echo "${builder}-2,${took},${begin},${end}" >> ${csv}
        INFO "${i} of ${n}: ${builder}: pruning"
        rm -f ${dir}/$(bb::dummy_file_name)
        ${builder}::prune
    done
}

### Docker
function docker::init(){
    local dindimg="$1"
    docker pull ${dindimg}
    INFO "Docker version"
    docker run --rm ${dindimg} docker --version
}
function docker::prepare(){
    local dindimg="$1"
    INFO "begin prepare docker"
    docker volume create $(bb::volume_name docker)
    docker network create $(bb::network_name docker)

    if [ "$dindimg" == "docker:18.09-dind" ]; then
        INFO "dind is docker 18.09"
        docker run --privileged --name $(bb::container_name docker) -d -v $(bb::volume_name docker):/var/lib/docker ${dindimg} \
            -s overlay2
    else
        INFO "dind version is not 18.09"
        docker run --privileged --name $(bb::container_name docker) -d \
                    --network $(bb::network_name docker) --network-alias docker \
                    -v $(bb::volume_name docker):/var/lib/docker \
                    -e DOCKER_TLS_CERTDIR=/certs \                                            
                    -v docker-certs-ca:/certs/ca \                                       
                    -v docker-certs-client:/certs/client \ 
                    ${dindimg} -s overlay2
    fi
    INFO "prepare docker success"
}
function docker::build(){
    INFO "begin docker build"
    local dir="$1"
    local dindimg="$2"
    INFO "DEBUG dir ${dir}"
    INFO "DEBUG dindimg ${dindimg}"
    if [ "$dindimg" == "docker:18.09-dind" ]; then
        INFO "dind is docker 18.09"
        docker run -v ${dir}:/workspace -w /workspace --rm --link $(bb::container_name docker):docker -e DOCKER_HOST=tcp://docker:2375 ${dindimg} \
        docker build -t foo -q . > /dev/null 2>&1
    else
        INFO "dind version is not 18.09"
        docker run --rm --network $(bb::network_name docker) \
                    -e DOCKER_TLS_CERTDIR=/certs \
                    -v docker-certs-client:/certs/client:ro \
                    -v ${dir}:/workspace -w /workspace \
                    ${dindimg} \
                    docker build -t foo -q .
    fi
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
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 DIR CSV N DINDIMG"
    exit 1
fi

DIR=$(realpath "$1")
CSV="$2"
N="$3"
DINDIMG="$4"

builders=(docker buildkit)

# NOW=$(ls ${DIR})
# INFO "DEBUG NOW ${NOW}"
INFO "DEBUG DIR ${DIR}"
INFO "DEBUG CSV ${CSV}"
INFO "DEBUG N ${N}"
INFO "DEBUG DINDIMG ${DINDIMG}"

for builder in ${builders[@]}; do
    bb::test ${builder} ${DIR} ${CSV} ${N} ${DINDIMG}
done