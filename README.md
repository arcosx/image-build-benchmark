# image-build-benchmark [![CI](https://github.com/arcosx/image-build-benchmark/actions/workflows/main.yml/badge.svg)](https://github.com/arcosx/image-build-benchmark/actions/workflows/main.yml)

Testing the speed and size of container image builds.

**The project is still in progress, so you can wait.**


### Usage

#### Only see the result
Look at this summary report ! [TODO]


#### for your own images
fork this project, modify [.github/workflows/main.yml](.github/workflows/main.yml)，
Of course you can also run it locally.

```shell
$ ./build.sh ${DOCKER_FILE_DIR} ${OUTPUT_CSV_PATH} ${RUN_TIMES} ${DIND_IMAGE} ${BUILDER}

# examples:

./build.sh dockerfiles/pytorchcuda out.csv 2 docker:18.09-dind buildkit

./build.sh dockerfiles/pytorchcuda out.csv 2 docker:20.10-dind docker
```

### Support Build Engine
* docker:18.09-dind (Sep 5,2019)
* docker:19.03-dind (Aug 6,2021)
* docker:20.10-dind (Jun 8,2022)
* buildkit:latest   (Now)

### Test Dockerfiles
* (c and go build 6.7MB)[dockerfiles/01](./dockerfiles/01/Dockerfile)
* (pytorch for deep learning 2.07GB) [dockerfiles/pytorchnocuda](./dockerfiles/pytorchnocuda/Dockerfile)
* (pytorch for deep learning with nvidia-cuda  6.06GB) [dockerfiles/pytorchcuda](./dockerfiles/pytorchcuda/Dockerfile)


### Thanks

Core code and processes from https://github.com/AkihiroSuda/buildbench 

Many thanks [@AkihiroSuda](https://github.com/AkihiroSuda)

This code also follows the `Apache-2.0 license`.
