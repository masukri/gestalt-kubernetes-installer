#!/bin/bash

PUBLISH=0
SILENT=0
VERBOSE=0
PRINT_IMAGE_ID=0
REGISTRY="galacticfog"
LABEL="gestalt-installer-base"
DEFAULT_TAG="build"
declare -a TAGS
declare -a BUILD_ARGS

debug() {
  if [ $VERBOSE -ne 0 ] && [ $SILENT -eq 0 ]; then
    echo "$@"
  fi
}

info() {
  if [ $SILENT -eq 0 ]; then
    echo "$@"
  fi
}

error() {
  >&2 echo "[Error] $@"
}

exit_with_error() {
  error "$@"
  exit 1
}

exit_on_error() {
  [ $? -eq 0 ] || exit_with_error "$@"
}

usage() {
  local CMD=`basename $0`
  echo "\

$CMD USAGE:
    $CMD [-p] [-r REGISTRY] [-t TAG] [-l LABEL]
    
    OPTIONS:
    -h
      Print this help info to STDOUT.
    -p
      Push the built image to the container image registry.  If this flag is NOT set, the
      script will build the image, but will not push it to a remote registry.
      NOTE: This option has no effect if no tags are defined with the -t option.
    -s
      Run silent.  Do not print output to STDOUT, but print errors to STDERR.
    -a BUILD_ARG_NAME=BUILD_ARG_VALUE
      Adds a build-arg to the docker build command.  Can be used multiple times.
    -i
      Print the built image ID to STDOUT even if the -s flag is set.  If both -s and -i
      flags are set, the image ID will be the only output from the build script.
    -v
      Run verbose - print additional diagnostic output to STDOUT.  NOTE: -s overrides -v
    -r REGISTRY
      Push the built image to this registry. (default DockerHub '${REGISTRY}' registry)
    -l LABEL
      Use this image label value. (default '${LABEL}')
    -d DEFAULT_TAG
      Tag the image with this value when building. (default '${DEFAULT_TAG}')
      The default tag will always be applied to the built image, but this tag will NOT be 
      pushed to the registry unless it is also passed in with the -t option
    -t TAG
      Tag the image with this value. Can be used multiple times. (no default value)
      If no tags are defined, the -p option is ignored.  Only tags defined with this option
      will be pushed to the registry.
"
}

while getopts ":hpsiva:l:r:t:" opt; do
  case ${opt} in
    h)
      debug "-h flag is set!  Printing usage info to STDOUT..."
      usage
      exit 0
      ;;
    p)
      PUBLISH=1
      debug "-p flag is set!"
      ;;
    s)
      debug "-s flag is set!"
      SILENT=1
      ;;
    i)
      PRINT_IMAGE_ID=1
      debug "-i flag is set!"
      ;;
    v)
      VERBOSE=1
      debug "-v flag is set!"
      ;;
    r)
      REGISTRY=$OPTARG
      debug "-r option sets REGISTRY to '$REGISTRY'"
      ;;
    a)
      BUILD_ARGS+=("$OPTARG")
      debug "-a option adds BUILD_ARG '$OPTARG'"
      debug "BUILD_ARGS = ( ${BUILD_ARGS[@]} )"
      ;;
    t)
      TAGS+=("$OPTARG")
      debug "-t option adds TAG '$OPTARG'"
      debug "TAGS = ( ${TAGS[@]} )"
      ;;
    l)
      LABEL=$OPTARG
      debug "-l option sets LABEL to '$LABEL'"
      ;;
    :)
      exit_with_error "INVALID INPUT option '-${OPTARG}' requires an argument! $(usage)"
      ;;
    ?) 
      exit_with_error "INVALID INPUT option '-${OPTARG}' undefined! $(usage)"
      ;;
  esac
done
shift $((OPTIND -1))

if [ ${#TAGS[@]} -gt 0 ]; then
  debug "${#TAGS[@]} defined '${TAGS[*]}'"
else
  debug "Building only the default tag '${DEFAULT_TAG}'"
  PUBLISH=0
fi

NOT_STRING="NOT "
if [ $PUBLISH -eq 1 ]; then
  NOT_STRING=""
fi
debug "$0 will ${NOT_STRING}publish the built image to the '$REGISTRY' registry"

OUTPUT="docker command has not been called!"
get_output() {
  echo
  echo "------------------------------ START OUTPUT ------------------------------"
  echo "${OUTPUT}"
  echo "------------------------------- END OUTPUT -------------------------------"
}

#Build the image
info "Building..."
BUILD_CMD="docker build -t ${REGISTRY}/${LABEL}:${DEFAULT_TAG} ."
for arg in ${BUILD_ARGS[@]}; do
  BUILD_CMD="${BUILD_CMD} --build-arg $arg"
done
debug "Building with command '$BUILD_CMD'"
OUTPUT=$($BUILD_CMD 2>&1)
[ $? -eq 0 ] || exit_with_error "FAILED image build for '$LABEL' using command '$BUILD_CMD' $(get_output)"
debug "$(get_output)"

imageid=$( grep "^Successfully built" <<<"$OUTPUT" | awk '{ print $3 }' )
if [ -z "${imageid}" ]; then
  exit_with_error "Failed to obtain newly created image id from docker build output! $(get_output)"
fi
info "----- Successfully built ${LABEL} image with ID '$imageid'"
[ $PRINT_IMAGE_ID -eq 0 ] || echo "$imageid"

#Tag and Push
for TAG in ${TAGS[@]}; do
  full_tag="${REGISTRY}/${LABEL}:${TAG}"
  info "Tagging ${LABEL} image id ${imageid} as ${full_tag}"
  TAG_CMD="docker tag $imageid $full_tag"
  debug "Tagging image with command '$TAG_CMD'"
  OUTPUT=$($TAG_CMD)
  [ $? -eq 0 ] || exit_with_error "FAILED to tag image ${imageid} with '${full_tag}' using command '$TAG_CMD'"
  if [ ${PUBLISH} -eq 1 ]; then
    info "Pushing ${LABEL} image id ${imageid} as ${full_tag}"
    PUSH_CMD="docker push ${full_tag}"
    debug "Pushing image with command '$PUSH_CMD'"
    OUTPUT=$($PUSH_CMD)
    [ $? -eq 0 ] || exit_with_error "FAILED to push image ${imageid} to '${full_tag}' using command '$PUSH_CMD' $(get_output)"
    debug "$(get_output)"
  fi
done

echo "Build and publish successful."
