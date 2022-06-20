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

        if [ "$builder" == "docker" ]; then
            local size=$(${builder}::imageSize ${dindimg})
            echo "docker,${dindimg},1,${took},${size}" >> ${csv}    
        else
            local size=$(${builder}::imageSize ${dir})
            echo "buildkit,latest,1,${took},${size}" >> ${csv}
        fi

        desc="${i} of ${n}: ${builder} #2 (with dummy modification. cache can be potentially used.)"
        date > ${dir}/$(bb::dummy_file_name)

        INFO "${desc}: starting"
        local begin=$(date +%s.%N)
        ${builder}::build ${dir} ${dindimg}
        local end=$(date +%s.%N)
        local took=$(echo ${end}-${begin} | bc)

        local size="$(${builder}::imageSize ${dindimg})"

        if [ "$builder" == "docker" ]; then
            echo "docker,${dindimg},2,${took},${size}" >> ${csv}    
        else
            echo "buildkit,latest,2,${took},${size}" >> ${csv}
        fi


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
    docker volume create docker-certs-ca
    docker volume create docker-certs-client   
    docker network create dind-network

    if [ "$dindimg" == "docker:18.09-dind" ]; then
        INFO "dind is docker 18.09"
        docker run --privileged --name $(bb::container_name docker) -d -v $(bb::volume_name docker):/var/lib/docker ${dindimg} \
            -s overlay2
    else
        INFO "dind version is not 18.09"
        docker run --privileged --name $(bb::container_name docker) -d \
            --network dind-network --network-alias docker \
            -e DOCKER_TLS_CERTDIR=/certs \
            -v docker-certs-ca:/certs/ca \
            -v docker-certs-client:/certs/client \
            ${dindimg}
    fi
    sleep 15
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
        docker build -t docker-build -q . > /dev/null 2>&1
    else
        INFO "dind version is not 18.09"
        # docker logs --tail 30 $(bb::container_name docker)
        docker run --rm --network dind-network \
                    -e DOCKER_HOST=tcp://docker:2376 \
                    -e DOCKER_TLS_CERTDIR=/certs \
                    -v docker-certs-client:/certs/client:ro \
                    -v ${dir}:/workspace -w /workspace \
                    ${dindimg} \
                    docker build -t docker-build -q . > /dev/null 2>&1
    fi
    INFO "docker build success"
}

function docker::imageSize() {
    local dindimg="$1"
    if [ "$dindimg" == "docker:18.09-dind" ]; then
        docker run -v ${dir}:/workspace -w /workspace --rm --link $(bb::container_name docker):docker -e DOCKER_HOST=tcp://docker:2375 ${dindimg} \
        docker images docker-build --format "{{.Size}}"
    else
        docker run --rm --network dind-network \
                    -e DOCKER_HOST=tcp://docker:2376 \
                    -e DOCKER_TLS_CERTDIR=/certs \
                    -v docker-certs-client:/certs/client:ro \
                    -v ${dir}:/workspace -w /workspace \
                    ${dindimg} \
                    docker images docker-build --format "{{.Size}}"
    fi
}

function docker::prune(){
    docker rm -f $(bb::container_name docker)
    docker volume rm -f $(bb::volume_name docker)
    docker volume rm -f docker-certs-ca
    docker volume rm -f docker-certs-client
    docker network rm dind-network
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
    sleep 15
    INFO "prepare buildkit success"
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

function buildkit::imageSize(){
    local dir="$1"
    docker run \
           -v ${dir}:/workspace -w /workspace \
           --rm \
           --link $(bb::container_name buildkit):buildkit \
           -e BUILDKIT_HOST=tcp://buildkit:1234 \
           --entrypoint buildctl \
           ${BUILDKIT_IMAGE} \
           build --frontend=dockerfile.v0 --local context=. --local dockerfile=. --output type=docker,name=buildkit-build,dest=buildkit-build.tar > /dev/null
    docker load -i buildkit-build.tar > /dev/null
    echo $(docker images buildkit-build --format "{{.Size}}")
}



### Main
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 DIR CSV N DINDIMG"
    exit 1
fi

DIR=$(realpath "$1")
CSV="$2"
N="$3"
DINDIMG="$4"

# both
# docker
# buildkit
BUILDER="$5"


# NOW=$(ls ${DIR})
# INFO "DEBUG NOW ${NOW}"
INFO "DEBUG DIR ${DIR}"
INFO "DEBUG CSV ${CSV}"
INFO "DEBUG N ${N}"
INFO "DEBUG DINDIMG ${DINDIMG}"
INFO "DEBUG BUILDER ${BUILDER}"

INFO "Linux Version: $(cat /proc/version)"
INFO "MemTotal: $(grep MemTotal /proc/meminfo)"
INFO "CPU Core: $(grep "cpu cores" /proc/cpuinfo)"
INFO "CPU MODEL: $(grep "model name" /proc/cpuinfo)"

if [ "$BUILDER" == "both" ]; then
    INFO "Both docker and buildkit will be test"
    bb::test docker ${DIR} ${CSV} ${N} ${DINDIMG}
    bb::test buildkit ${DIR} ${CSV} ${N} ${DINDIMG}
else
    INFO "Only ${BUILDER} will be test"
    bb::test ${BUILDER} ${DIR} ${CSV} ${N} ${DINDIMG}
fi