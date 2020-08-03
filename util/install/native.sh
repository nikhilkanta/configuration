#!/bin/bash
##
## Installs the pre-requisites for running Open edX on a single Ubuntu 16.04
## instance.  This script is provided as a convenience and any of these
## steps could be executed manually.
##
## Note that this script requires that you have the ability to run
## commands as root via sudo.  Caveat Emptor!
##

##
## Get IP ADDRESS of server and path to the private key
##
## Get this from a file instead
#brkvar=N
#while [[ ! $brkvar =~ ^([yY][eE][sS]|[yY])$ ]]
#do
 # read -p "Enter the ip address of the server(e.g: 0.0.0.0): " ip_address
  #echo "Installing edx on the server with the ip address: $ip_address"

 # read -p "Enter the path to the private key of the above server:" path_to_private_key
 # echo "The path to private key is at: $path_to_private_key"

 # read -p "Are the ip address and path right [y/N]: " brkvar
#done

cd ~
source server-vars.txt
echo "Installting edx-platform on the server with the ip address: $ip_address"
echo "The path to the private key of the server is at: $path_to_private_key"

##
## Sanity checks
##

if [[ ! $OPENEDX_RELEASE ]]; then
    echo "You must define OPENEDX_RELEASE"
    exit
fi

if [[ `lsb_release -rs` != "16.04" ]]; then
    echo "This script is only known to work on Ubuntu 16.04, exiting..."
    exit
fi

# Config.yml is required, must define LMS and CMS names, and the names
# must not infringe trademarks.

if [[ ! -f config.yml ]]; then
    echo 'You must create a config.yml file specifying the hostnames (and if'
    echo 'needed, ports) of your LMS and Studio hosts.'
    echo 'For example:'
    echo '    EDXAPP_LMS_BASE: "11.22.33.44"'
    echo '    EDXAPP_CMS_BASE: "11.22.33.44:18010"'
    exit
fi

grep -Fq EDXAPP_LMS_BASE config.yml
GREP_LMS=$?

grep -Fq EDXAPP_CMS_BASE config.yml
GREP_CMS=$?

if [[ $GREP_LMS == 1 ]] || [[ $GREP_CMS == 1 ]]; then
    echo 'Your config.yml file must specify the hostnames (and if'
    echo 'needed, ports) of your LMS and Studio hosts.'
    echo 'For example:'
    echo '    EDXAPP_LMS_BASE: "11.22.33.44"'
    echo '    EDXAPP_CMS_BASE: "11.22.33.44:18010"'
    exit
fi

grep -Fq edx. config.yml
GREP_BAD_DOMAIN=$?

if [[ $GREP_BAD_DOMAIN == 0 ]]; then
    echo '*** NOTE: Open edX and edX are registered trademarks.'
    echo 'You may not use "openedx." or "edx." as subdomains when naming your site.'
    echo 'For more details, see the edX Trademark Policy: https://edx.org/trademarks'
    echo ''
    echo 'Here are some examples of unacceptable domain names:'
    echo '    openedx.yourdomain.org'
    echo '    edx.yourdomain.org'
    echo '    openedxyourdomain.org'
    echo '    yourdomain-edx.com'
    echo ''
    echo 'Please choose different domain names.'
    exit
fi

##
## Log what's happening
##

mkdir -p logs
log_file=logs/install-$(date +%Y%m%d-%H%M%S).log
exec > >(tee $log_file) 2>&1
echo "Capturing output to $log_file"
echo "Installation started at $(date '+%Y-%m-%d %H:%M:%S')"

function finish {
    echo "Installation finished at $(date '+%Y-%m-%d %H:%M:%S')"
}
trap finish EXIT

echo "Installing release '$OPENEDX_RELEASE'"

##
## Overridable version variables in the playbooks. Each can be overridden
## individually, or with $OPENEDX_RELEASE.
##
VERSION_VARS=(
    edx_platform_version
    certs_version
    forum_version
    XQUEUE_VERSION
    configuration_version
    demo_version
    NOTIFIER_VERSION
    INSIGHTS_VERSION
    ANALYTICS_API_VERSION
    ECOMMERCE_VERSION
    ECOMMERCE_WORKER_VERSION
    DISCOVERY_VERSION
    THEMES_VERSION
)

for var in ${VERSION_VARS[@]}; do
    # Each variable can be overridden by a similarly-named environment variable,
    # or OPENEDX_RELEASE, if provided.
    ENV_VAR=$(echo $var | tr '[:lower:]' '[:upper:]')
    eval override=\${$ENV_VAR-\$OPENEDX_RELEASE}
    if [ -n "$override" ]; then
        EXTRA_VARS="-e $var=$override $EXTRA_VARS"
    fi
done

# my-passwords.yml is the file made by generate-passwords.sh.
if [[ -f my-passwords.yml ]]; then
    EXTRA_VARS="-e@$(pwd)/my-passwords.yml $EXTRA_VARS"
fi

# extra-vars.yml is the file for extra variables
if [[ -f extra-vars.yml ]]; then
    EXTRA_VARS="-e@$(pwd)/extra-vars.yml $EXTRA_VARS"
fi

EXTRA_VARS="-e@$(pwd)/config.yml $EXTRA_VARS"

CONFIGURATION_VERSION=${CONFIGURATION_VERSION-$OPENEDX_RELEASE}

##
## Clone the configuration repository and run Ansible
##
cd /var/tmp/
git clone https://github.com/nikhilkanta/configuration
cd configuration
git checkout $CONFIGURATION_VERSION
git pull

##
## Install the ansible requirements
##
# cd /var/tmp/configuration
# sudo -H pip install -r requirements.txt
# Since director will have already configured this

##
## Install System pre-requisites
## 
cd /var/tmp/configuration/playbooks && sudo -E ansible-playbook -vvv --user=ubuntu --private-key=$path_to_private_key ./install_prerequisites.yml -i "$ip_address,"
##
## Run the openedx_native.yml playbook in the configuration/playbooks directory
##
cd /var/tmp/configuration/playbooks && sudo -E ansible-playbook -vvv --user=ubuntu --private-key=$path_to_private_key ./openedx_native.yml -i "$ip_address," $EXTRA_VARS "$@"
ansible_status=$?

if [[ $ansible_status -ne 0 ]]; then
    echo " "
    echo "========================================"
    echo "Ansible failed!"
    echo "----------------------------------------"
    echo "If you need help, see https://open.edx.org/getting-help ."
    echo "When asking for help, please provide as much information as you can."
    echo "These might be helpful:"
    echo "    Your log file is at $log_file"
    echo "    Your environment:"
    env | egrep -i 'version|release' | sed -e 's/^/        /'
    echo "========================================"
fi
