#!/bin/bash

exit_on_error() {
  if [ $? -ne 0 ]; then
    echo
    echo "[Error] $@"
    exit 1
  fi
}

# Source
gestalt_docker_release_tag="release-2.3.9"
gestalt_installer_docker_release_tag="4"
docker_registry="galacticfog"
# Target
target_registry="gcr.io/galacticfog-public" #GF gke

# Manually grap all applicable images for installer
# grep '${docker_registry}' client/scripts/build-config.sh | awk -F'"' '{print $4}' | awk -F"/" '{print $2}' | sort -u
ALL_IMAGES=(
elasticsearch-docker:5.3.1
#busybox:1.29.3
#postgres:9.6.2
gestalt-security:${gestalt_docker_release_tag}
#rabbit:${gestalt_docker_release_tag}
gestalt-meta:${gestalt_docker_release_tag}
gestalt-log:${gestalt_docker_release_tag}
gestalt-ui-react:${gestalt_docker_release_tag}
gestalt-api-gateway:${gestalt_docker_release_tag}
gestalt-laser:${gestalt_docker_release_tag}
gestalt-laser-executor-dotnet:${gestalt_docker_release_tag}
gestalt-laser-executor-golang:${gestalt_docker_release_tag}
gestalt-laser-executor-js:${gestalt_docker_release_tag}
gestalt-laser-executor-jvm:${gestalt_docker_release_tag}
gestalt-laser-executor-nodejs:${gestalt_docker_release_tag}
gestalt-laser-executor-python:${gestalt_docker_release_tag}
gestalt-laser-executor-ruby:${gestalt_docker_release_tag}
gestalt-log:${gestalt_docker_release_tag}
gestalt-policy:${gestalt_docker_release_tag}
kong:${gestalt_docker_release_tag}
#gestalt-installer:${gestalt_installer_docker_release_tag}
)
# grep '${docker_registry}' ./client/scripts/build-installer-spec.sh | awk -F'"' '{print $2}' | awk -F'/' '{print $2}'
#ALL_IMAGES="${ALL_IMAGES} "

# Pull all images and save locally
for CURR_IMAGE in ${ALL_IMAGES[@]}; do
  cmd="docker pull ${docker_registry}/${CURR_IMAGE}"
  echo "[Info] Pulling image: ${cmd} ..." 
  ${cmd}
  exit_on_error "Failed download image: ${cmd}"
done

# Tag and upload images to target
for CURR_IMAGE in ${ALL_IMAGES[@]}; do
  cmd="docker tag ${docker_registry}/${CURR_IMAGE}  ${target_registry}/${CURR_IMAGE}"
  echo "[Info] Tagging image: ${cmd} ..."
  ${cmd}
  exit_on_error "Failed tag an image: ${cmd}"
  cmd="docker push ${target_registry}/${CURR_IMAGE}"
  echo "[Info] Pushing image: ${cmd} ..."
  ${cmd}
  exit_on_error "Failed to push an image: ${cmd}"
done
