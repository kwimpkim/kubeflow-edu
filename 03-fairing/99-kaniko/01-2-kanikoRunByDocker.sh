#!/bin/bash
WD=/root/kubeflow-edu/03-fairing/99-kaniko
IMG=reddiana/jupyterlab-kale:0114.1445
docker run \
	-v ${WD}/:/workspace/ \
	-v ${WD}/dockerConfig.json:/kaniko/.docker/config.json:ro \
    gcr.io/kaniko-project/executor:latest \
    --dockerfile=/workspace/Dockerfile \
    --context=dir://workspace \
    --destination=${IMG}