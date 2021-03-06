# This file is sourced into the installer

exit_with_error() {
  echo "[Error] $@"
  exit 1
}

exit_on_error() {
  [ $? -eq 0 ] || exit_with_error $@
}

warn_on_error() {
  [ $? -eq 0 ] || echo "[Warning] $@"
}

debug() {
  [ ${DEBUG:-0} -eq 0 ] || echo "[Debug] $@"
}

check_release_name_and_namespace() {
  if [ -z "$RELEASE_NAME" ]; then
    echo "Application RELEASE_NAME is not defined - using default value 'gestalt'"
    RELEASE_NAME='gestalt'
  fi
  debug "Installing Gestalt with application name '${RELEASE_NAME}'"
  
  DEFAULT_NS="${RELEASE_NAME}-system"
  if [ -z "$RELEASE_NAMESPACE" ]; then
    echo "Kubernetes RELEASE_NAMESPACE is not defined - using default value '${DEFAULT_NS}'"
    RELEASE_NAMESPACE='${DEFAULT_NS}'
  fi
  debug "Installing Gestalt in Kubernetes Namespace '${RELEASE_NAMESPACE}'"
}

check_for_required_environment_variables() {
  retval=0

  for e in $@; do
    if [ -z "${!e}" ]; then
      echo "Required environment variable \"$e\" not defined."
      retval=1
    fi
  done

  if [ $retval -ne 0 ]; then
    echo "One or more required environment variables not defined, aborting."
    exit 1
  else
    echo "All required environment variables found."
  fi
}

check_for_required_tools() {
  # echo "Checking for required tools..."
  which base64    >/dev/null 2>&1 ; exit_on_error "'base64' command not found, aborting."
  which tr        >/dev/null 2>&1 ; exit_on_error "'tr' command not found, aborting."
  which sed       >/dev/null 2>&1 ; exit_on_error "'sed' command not found, aborting."
  which seq       >/dev/null 2>&1 ; exit_on_error "'seq' command not found, aborting."
  which sudo      >/dev/null 2>&1 ; exit_on_error "'sudo' command not found, aborting."
  which true      >/dev/null 2>&1 ; exit_on_error "'true' command not found, aborting."
  # 'read' may be implemented as a shell function rather than a separate function
  # which read      >/dev/null 2>&1 ; exit_on_error "'read' command not found, aborting."
  which bc        >/dev/null 2>&1 ; exit_on_error "'bc' command not found, aborting."
  which kubectl   >/dev/null 2>&1 ; exit_on_error "'kubectl' command not found, aborting."
  which curl      >/dev/null 2>&1 ; exit_on_error "'curl' command not found, aborting."
  which unzip     >/dev/null 2>&1 ; exit_on_error "'unzip' command not found, aborting."
  which tar       >/dev/null 2>&1 ; exit_on_error "'tar' command not found, aborting."
  which jq        >/dev/null 2>&1 ; exit_on_error "'jq' command not found. To obtain do 'bew install jq', aborting."
  echo "OK - Required tools found."
}

check_profile() {
  local PROFILE=$1
  if [ -z "$PROFILE" ]; then
    PROFILE=$(get_profile_from_kubecontext)
    if [ $? -ne 0 ]; then
      echo "$PROFILE"
      return 1
    fi
  fi
  [ -d "./profiles/$PROFILE" ] || exit_with_error "Could not find a profile definition for '$PROFILE'!"
  echo $PROFILE
}

get_profile_from_kubecontext() {
  local kubecontext="`kubectl config current-context`"
  if [ "$kubecontext" == "docker-for-desktop" ]; then
    echo "docker-desktop"
    return 0
  elif [ "$kubecontext" == "docker-desktop" ]; then
    echo "docker-desktop"
    return 0
  elif [ "$kubecontext" == "minikube" ]; then
    echo $kubecontext
    return 0
  fi

  # Try to detect type
  echo $kubecontext | grep ^gke_ >/dev/null
  [ $? -eq 0 ] && echo "gke" && return 0

  echo $kubecontext | grep ^'arn:aws:eks:' >/dev/null
  [ $? -eq 0 ] && echo "eks" && return 0

  echo $kubecontext | grep ^'arn:aws:' >/dev/null
  [ $? -eq 0 ] && echo "aws" && return 0

  local kubeserver=$( kubectl config view --minify=true -o=json | jq -r '.clusters[].cluster.server' )
  echo $kubeserver | grep -e '\.azmk8s\.' >/dev/null
  [ $? -eq 0 ] && echo "aks" && return 0

  exit_with_error "Could not find a suitable profile for context '$kubecontext'. Please specify an installation profile (docker-desktop, minikube, gke, eks, aws, aks)."
  return 1
}

check_for_kube() {
  # echo "Checking for Kubernetes..."
  local kubecontext="`kubectl config current-context`"

  # if [ ! -z "$target_kube_context" ]; then
  #     if [ "$kubecontext" != "$target_kube_context" ]; then
  #     do_prompt_to_continue \
  #       "Warning - Kubernetes context is '$kubecontext' (expected '$target_kube_context')" \
  #       "Proceed anyway?"
  #     fi
  # fi

  kube_cluster_info=$(kubectl cluster-info)
  exit_on_error "Kubernetes cluster not accessible, aborting."

  echo "OK - Kubernetes cluster '$kubecontext' is accessible."
}

check_cluster_capacity() {
  # echo "Checking cluster capacity..."
  ./helpers/check-cluster-capacity
  local check=$?
  if [ $check -eq 10 ]; then
    # Meets minimum capacity requirements, but not recommended.  Prompt to continue
      do_prompt_to_continue \
        "" \
        "Proceed anyway?"
  elif [ $check -ne 0 ]; then
    # Doesn't meet minimum capacity requirements
    exit_with_error "Cannot proceed with installation, not enough cluster resources."
  fi
}

create_or_check_for_required_namespace() {
  # echo "Checking for existing Kubernetes namespace '$RELEASE_NAMESPACE'..."
  kubectl get namespace $RELEASE_NAMESPACE > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo ""
    echo "Kubernetes namespace '$RELEASE_NAMESPACE' doesn't exist, creating..."
    create_ns "$RELEASE_NAMESPACE"
  fi
  echo "OK - Kubernetes namespace '$RELEASE_NAMESPACE' is present."
}

create_namespace() {
  debug "Checking for existing Kubernetes namespace '$RELEASE_NAMESPACE'..."
  kubectl get namespace $RELEASE_NAMESPACE > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    create_ns "$RELEASE_NAMESPACE"

    # Wait for namespace to be created
    sleep 5
    echo "Namespace $RELEASE_NAMESPACE created."
  fi
}

create_ns() {
  local NS_NAME=$1
  echo "Creating namespace '$RELEASE_NAMESPACE'..."
  kubectl create namespace $NS_NAME
  exit_on_error "FAILED to create namespace '$NS_NAME', aborting."
  kubectl label namespace $NS_NAME "app.kubernetes.io/app=gestalt" "app.kubernetes.io/name=$RELEASE_NAME"
  exit_on_error "FAILED to label namespace '$NS_NAME' with Gestalt labels, aborting."
}

check_for_existing_namespace() {
  # echo "Checking for existing Kubernetes namespace '$RELEASE_NAMESPACE'..."
  kubectl get namespace $RELEASE_NAMESPACE > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo ""
    echo "Kubernetes namespace '$RELEASE_NAMESPACE' already exists, aborting.  To delete the namespace, run the following command:"
    echo ""
    echo "  kubectl delete namespace $RELEASE_NAMESPACE"
    echo ""
    exit_with_error "Kubernetes namespace '$RELEASE_NAMESPACE' already exists, aborting."
  fi
  echo "OK - Kubernetes namespace '$RELEASE_NAMESPACE' does not exist."
}

check_for_required_namespace() {
  # echo "Checking for existing Kubernetes namespace '$RELEASE_NAMESPACE'..."
  kubectl get namespace $RELEASE_NAMESPACE > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo ""
    echo "Kubernetes namespace '$RELEASE_NAMESPACE' doesn't exist, aborting.  To create the namespace, run the following command:"
    echo ""
    echo "  kubectl create namespace $RELEASE_NAMESPACE"
    echo ""
    echo "Then ensure that 'Full Control' grants are provided for the '$RELEASE_NAMESPACE/default' service account."
    echo ""
    exit_with_error "Kubernetes namespace '$RELEASE_NAMESPACE' doesn't exist, aborting."
  fi
  echo "OK - Kubernetes namespace '$RELEASE_NAMESPACE' is present."
}

# check_for_existing_namespace_ask() {
#   echo "Checking for existing Kubernetes namespace '$RELEASE_NAMESPACE'..."
#   kubectl get namespace $RELEASE_NAMESPACE > /dev/null 2>&1
#   if [ $? -eq 0 ]; then
#     while true; do
#         read -p " Kubernetes namespace '$RELEASE_NAMESPACE' already exists, proceed? [y/n]: " yn
#         case $yn in
#             [Yy]*) return 0  ;;
#             [Nn]*) echo "Aborted" ; exit  1 ;;
#         esac
#     done
#   fi
#   echo "OK - Kubernetes namespace '$RELEASE_NAMESPACE' does not exist."
# }

check_for_prior_install() {
  # echo "Checking for prior installation..."

  local num_lines=$( kubectl get all -n $RELEASE_NAMESPACE --no-headers 2>/dev/null | wc -l)
  if [ $num_lines -ne 0 ]; then
      exit_with_error "Gestalt resources found in $RELEASE_NAMESPACE namespace, aborting."
  fi

  kubectl get services --all-namespaces | grep default-kong > /dev/null
  if [ $? -eq 0 ]; then
    exit_with_error "'default-kong' service already present, aborting."
  fi

  # Note: using the local keyword in 'local existing_namespaces=$( ... ) returns zero, unexpectedly.. so not using it.
  existing_namespaces=$(kubectl get namespace -l meta/fqon -o name)
  if [ $? -eq 0 ] && [ ! -z "$existing_namespaces" ]; then
    echo ""
    echo "Warning: There are existing namespaces that appear to be from a prior install:"
    echo "$existing_namespaces"
    echo ""

    if [ -z "$MARKETPLACE_INSTALL" ]; then
      do_prompt_to_continue \
        "There appear to be existing namespaces. Recommand inspecting and deleting these namespaces before continuing." \
        "Proceed anyway?"
    else
      echo "Continuing anyway since this is an automated install, press Ctrl-C to cancel..."
      sleep 5
    fi
  else
    echo "OK - No prior Gestalt installation found."
  fi
}

prompt_to_continue() {

  local kubecontext="`kubectl config current-context`"

  if [ ! -f __skip_eula ]; then
    do_prompt_to_continue \
      "You must accept the Gestalt Enterprise End User License Agreement (http://www.galacticfog.com/gestalt-eula.html) to continue." \
      "Accept EULA and proceed with Gestalt Platform installation to '$kubecontext'?"
    accept_eula $@
  fi
}

do_prompt_to_continue() {
  if [ ! -z "$1" ]; then
    echo ""
    echo -e $1
    echo ""
  fi 
  while true; do
      read -p "$2 [y/n]: " yn
      case $yn in
          [Yy]*) echo ; return 0  ;;
          [Nn]*) echo "Aborted" ; exit  1 ;;
      esac
  done
}

get_installer_image_config() {
  local PROFILE=${1}
  local INSTALLER_IMAGE
  local FOUND=$(get_installer_from_config "./base-config.yaml")
  [ $? -eq 0 ] && INSTALLER_IMAGE="$FOUND"
  FOUND=$(get_installer_from_config "./profiles/$PROFILE/config.yaml")
  [ $? -eq 0 ] && INSTALLER_IMAGE="$FOUND"
  echo "$INSTALLER_IMAGE"
}

get_installer_from_config() {
  local CONFIG_FILE=${1}
  local INSTALLER_IMAGE
  if [ -f "$CONFIG_FILE" ]; then
    INSTALLER_IMAGE=$(grep '^INSTALLER_IMAGE' $CONFIG_FILE | grep -v '^#' | awk '{print $2}')
  fi
  [ -z "$INSTALLER_IMAGE" ] && exit 1
  echo "$INSTALLER_IMAGE"
}

generate_slack_payload() {

  local eula_data="$1"
  local profile="${2:-'default'}"

  . ${eula_data}_client

  if [ -z "$name" ] || [ -z "$company" ] || [ -z "$email" ]; then
    prompt_eula "${eula_data}"
  fi

  ui_image_version=$(grep '^UI_IMAGE' base-config.yaml | grep -v '^#' | awk '{print $2}' | awk -F':' '{print $2}')

  # The create_slack_payload function is in ../src/scripts/eula-functions.sh
  local payload=$(create_slack_payload "$profile" "$ui_image_version" "$name" "$company" "$email")
  echo $payload > ${eula_data}
}

read_file_data() {
  # Reads a local file echoes the contents
  echo $(<${1})
}

accept_eula() {

  eula_data="./.eula_info"

  if [ ! -f ${eula_data} ]; then
    prompt_eula "${eula_data}"
  else
    if [ ! -f ${eula_data}_client ]; then
      parse_eula_client_data "${eula_data}"
    fi
  fi

  generate_slack_payload "${eula_data}" $@
  
  # The send_slack_message function is in ../src/scripts/eula-functions.sh
  send_slack_message "$(read_file_data "${eula_data}")"

  echo "Proceeding with Gestalt Platform installation."
}

prompt_eula() {

  local eula_data="$1"

  while true; do

    local company
    local name
    local email
    local yn

    echo "Please provide the following to accept the EULA (press Ctrl-C to abort)"

    while [ -z "$name" ];    do read -p "  Your Name: " name ; done
    while [ -z "$company" ]; do read -p "  Your Company name: " company ; done
    while [ -z "$email" ];   do read -p "  Your Email: " email ; done

    echo
    echo "Please verify your information:"
    echo "  Name:    $name"
    echo "  Company: $company"
    echo "  Email:   $email"
    echo
    read -p "Is your information correct? [y/n] " yn

    case $yn in
        [Yy]*)

            cat > ${eula_data}_client << DATA
name="$name"
company="$company"
email="$email"
DATA

            return 0
            ;;
        [Nn]*)
            unset name
            unset email
            unset company
            echo
            ;;
    esac

  done
}

parse_eula_client_data () {
  local eula_data="$1"

  name=$(cat ${eula_data} | awk -F'"name": "' '{print $2}' | awk -F'", "company": "' '{print $1}')
  company=$(cat ${eula_data} | awk -F'"company": "' '{print $2}' | awk -F'", "email": "' '{print $1}')
  email=$(cat ${eula_data} | awk -F'"email": "' '{print $2}' | awk -F'", "message": "' '{print $1}')

  cat > ${eula_data}_client << DATA
name="$name"
company="$company"
email="$email"
DATA
}

summarize_config() {

  # Set defalt URLs.  Post-install scripts can override these
  gestalt_login_url=$gestalt_ui_ingress_protocol://$gestalt_ui_ingress_host:$gestalt_ui_service_nodeport
  gestalt_api_gateway_url=$external_gateway_protocol://$external_gateway_host:$gestalt_kong_service_nodeport

  echo
  echo "=============================================="
  echo "  Configuration Summary"
  echo "=============================================="
  echo " - Kubernetes cluster: `kubectl config current-context`"
  echo " - Kubernetes namespace: $RELEASE_NAMESPACE"
  echo " - Gestalt Admin: $gestalt_admin_username"
  # TODO: Only output if not using dynamic LBs.
  echo " - Gestalt User Interface: $gestalt_login_url"
  echo " - Gestalt API Gateway: $gestalt_api_gateway_url"
  case $provision_internal_database in
    [YyTt1]*)
      echo " - Database: Provisioning an internal database"
      ;;
    *)
      echo " - Database:"
      echo "    Host: $database_hostname"
      echo "    Port: $database_port"
      echo "    Name: $database_name"
      echo "    User: $database_user"
      ;;
  esac

  # Summarize executors
  echo
  echo "Enabled executor runtimes:"
  for e in 'js' 'nodejs' 'dotnet' 'golang' 'jvm' 'python' 'ruby'; do
      local ee="gestalt_laser_executor_${e}_image"
      if [ ! -z "${!ee}" ]; then
        echo " - $e"
      # else
      #   echo " - $e (not enabled)"
      fi
  done
  echo ""
}

run_helper() {
  local PROFILE=$1
  local HELPER=$2
  local script="./profiles/${PROFILE}/${HELPER}.sh"

  echo "Checking for helper: ${script} ..."
  if [ -f "$script" ]; then
    echo ""
    echo "Running $script ..."
    cd ./profiles/${PROFILE}/
    . ${HELPER}.sh
    cd ~-
    exit_on_error "helper script '${script}' failed, aborting."
  else
    debug "No '${HELPER}' script found for profile '${PROFILE}'"
  fi
  echo
}

prompt_or_wait_to_continue() {
  if [ -z "$MARKETPLACE_INSTALL" ]; then
      prompt_to_continue $@
  else
    echo "About to proceed with installation, press Ctrl-C to cancel..."
    sleep 5
  fi
}

wait_for_installer_launch() {

  local previous_status=""

  local INSTALL_POD="${RELEASE_NAME}-installer"

  echo "Waiting for '${INSTALL_POD}' pod to launch:"
  for i in `seq 1 60`; do
    status=$(kubectl get pod -n ${RELEASE_NAMESPACE} ${INSTALL_POD} -ojsonpath='{.status.phase}')

    if [ "$status" != "$previous_status" ]; then
      echo -n " $status "
      previous_status=$status
    else
      echo -n "."
    fi

    if [ "$status" == "Running" ]; then
      echo
      return 0
    elif [ "$status" == "Completed" ]; then
      echo
      return 0
    fi

    sleep 2
  done

  echo
  echo "Error, '${INSTALL_POD}' pod did not launch within the expected timeframe."  
  return 1
}

# Poll the log of the installer and search for "[Running " steps to display as status
# Check for special markers that indicate installation success or failure
wait_for_install_completion() {
  local previous_status=""

  local INSTALL_POD="${RELEASE_NAME}-installer"
  local TIMEOUT=${INSTALL_POD_TIMEOUT:=600}

  local CHECK_INTERVAL=5
  local MAX_CHECKS=$( expr $TIMEOUT / $CHECK_INTERVAL )

  echo "Waiting for Gestalt Platform installation to complete. ($TIMEOUT seconds)"
  for i in `seq 1 $MAX_CHECKS`; do
    echo -n "."

    line=$(kubectl logs -n $RELEASE_NAMESPACE $INSTALL_POD --tail 20 2> /dev/null)

    echo "$line" | grep "^\[INSTALLATION_SUCCESS\]" > /dev/null
    if [ $? -eq 0 ]; then
      echo
      echo "[Success] Gestalt Platform Installation successful."
      return
    fi
    # Check for failure - no success message, but end of file found
    echo "$line" | grep "^\[INSTALLATION_FAILURE\]" > /dev/null
    if [ $? -eq 0 ]; then
      echo "Installation failed!"
      echo
      echo "---Install log (last 10 lines)---"
      kubectl logs -n $RELEASE_NAMESPACE $INSTALL_POD --tail 10
      echo "----End Logs------"
      echo
      exit_with_error "Installation failed.  View './logs/gestalt-installer.log' for more details."
    fi

    local podstatus=$(kubectl get pod -n $RELEASE_NAMESPACE $INSTALL_POD -ojsonpath='{.status.phase}')
    if [ "$podstatus" == "Failed" ] || [ "$podstatus" == "Error" ]; then
      echo "Installation failed!"
      echo
      echo "---Install log (last 10 lines)---"
      kubectl logs -n $RELEASE_NAMESPACE $INSTALL_POD --tail 10
      echo "----End Logs------"
      echo
      exit_with_error "Installation failed - '$INSTALL_POD' pod returned $podstatus status.  View ./log/gestalt-installer.log for more details."
    fi

    local status=$(echo "$line" | grep "^\[Running " | tail -n 1)
    if [ ! -z "$status" ]; then
      if [ "$status" != "$previous_status" ]; then
        echo ""
        previous_status="$status"
        echo "$status"
      fi
    fi

    sleep $CHECK_INTERVAL
  done
  echo
  exit_with_error "Installation did not complete within expected timeframe."
}

fog_cli_login() {

  local SECRETS_NAME="${RELEASE_NAME:-"gestalt"}-secrets"

  gestalt_url=`kubectl get secrets -n $RELEASE_NAMESPACE $SECRETS_NAME -ojsonpath='{.data.gestalt-url}' | base64 --decode`
  gestalt_admin_username=`kubectl get secrets -n $RELEASE_NAMESPACE $SECRETS_NAME -ojsonpath='{.data.admin-username}' | base64 --decode`
  gestalt_admin_password=`kubectl get secrets -n $RELEASE_NAMESPACE $SECRETS_NAME -ojsonpath='{.data.admin-password}' | base64 --decode`
  ./fog login ${gestalt_url} -u $gestalt_admin_username -p $gestalt_admin_password
  if [ $? -ne 0 ]; then
    echo ""
    echo "  Warning: Failed to log in to '$gestalt_url' using user '$gestalt_admin_username'."
    echo "  If Gestalt is behind a load balancer that requires DNS, the Gestalt service may not yet be live.  To attempt to log in manually, run the following:"
    echo ""
    echo "    ./fog login $gestalt_url"
    echo ""
  fi
}

display_summary() {
  echo
  echo "Gestalt Platform installation complete!  Next Steps:"
  echo ""
  echo "  1) Login to Gestalt:"
  echo ""
  echo "         URL:       $gestalt_url"
  echo "         User:      $gestalt_admin_username"
  echo "         Password:  $gestalt_admin_password"
  echo ""
  echo "  2) Next, navigate to the developer sandbox at:"
  echo ""
  echo "         $gestalt_url -> Sandboxes -> Developer Sandbox -> Development"
  echo ""
  echo "     Or via URL:"
  echo ""
  echo "         `./fog context get-browser-url`"
  echo ""
  echo "  3) You may access the Gestalt platform documentation at"
  echo ""
  echo "         http://docs.galacticfog.com/"
  echo ""
  echo "Done."
}

download_fog_cli() {
    echo "Checking for latest CLI..."
    gestalt_cli_version=`curl -o - https://raw.githubusercontent.com/GalacticFog/gestalt-fog-cli/master/LATEST 2> /dev/null`

    if [ -z "$gestalt_cli_version" ]; then
      exit_with_error "gestalt_cli_version not defined, aborting"
    fi

    # echo "Checking for 'fog' CLI..."

    local download="No"

    if [ -f './fog' ]; then
        local version=$(./fog --version)
        if [ "$gestalt_cli_version" != "$version" ]; then
            echo "fog version $version does not match required version $gestalt_cli_version, will remove."
            download="Yes"
        fi
    else 
        echo "'fog' CLI not present."
        download="Yes"
    fi

    if [ "$download" == "Yes" ]; then
        local os=`uname`

        if [ "$os" == "Darwin" ]; then
            local url="https://github.com/GalacticFog/gestalt-fog-cli/releases/download/${gestalt_cli_version}/gestalt-fog-cli-macos-${gestalt_cli_version}.zip"
        elif [ "$os" == "Linux" ]; then
            local url="https://github.com/GalacticFog/gestalt-fog-cli/releases/download/${gestalt_cli_version}/gestalt-fog-cli-linux-${gestalt_cli_version}.zip"
        else
            echo
            echo "Warning: unknown OS type '$os', treating as Linux"
        fi

        if [ ! -z "$url" ]; then
            echo
            echo "Downloading Gestalt fog CLI $gestalt_cli_version..."

            curl -L $url -o fog.zip
            exit_on_error "Failed to download 'fog' CLI, aborting."

            echo
            echo "Unzipping..."

            unzip -o fog.zip
            exit_on_error "Failed to unzip 'fog' CLI package, aborting."

            rm fog.zip
        fi
    fi

    local version=$(./fog --version)
    exit_on_error "Error running 'fog' CLI, aborting."

    echo "OK - fog CLI $version present."
}

cleanup() {
    local file=./logs/gestalt-installer.log

    local INSTALL_POD="${RELEASE_NAME}-installer"

    echo "Capturing installer logs to '$file'"
    date > $file
    kubectl logs -n $RELEASE_NAMESPACE $INSTALL_POD >> $file

    debug "Deleting '$INSTALL_POD' pod..."
    kubectl delete pod -n $RELEASE_NAMESPACE $INSTALL_POD
}
