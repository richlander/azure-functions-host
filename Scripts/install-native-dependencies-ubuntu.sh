#!/bin/bash

# Do not move to shebang, the way Devops calls this script will make
# them get ignored.
#
set -eux

# This script installs the native Linux dependencies required to build or to
# run/test SQLPAL. This script is currently used in environments where the
# machine can be a blank Ubuntu install, so this script can also serve as
# a reference for the minimal installs required in order to build/run/debug.
# This script completely replaces the use of `ht` in those environments, and
# it can be executed from anywhere with public internet access, no corpnet
# required.
#

# Do not move this to the #! above, because callers of this script typically
# explicitly call bash on it (such as when in YAML and doing `bash: <script file>`),
# and that bypasses the shebang.
#
set -xeu

# Defines ExecuteWithRetry and other common utilities, as well as most version-related
# and environment-related variables.
#
source "$(dirname "$0")/provisioning/provisioning-common.sh"

DEPENDENCIES=""
BUILD=false
RUNTIME=false
DEBUG=false
AEGIS=false
TEST=false
BOOTSTRAP=false
INSTALL_DOTNET=${INSTALL_DOTNET:-false}
INSTALL_PWSH=${INSTALL_PWSH:-false}
INSTALL_DOCKER=${INSTALL_DOCKER:-false}
INSTALL_AZCLI=${INSTALL_AZCLI:-false}
DEVOPS_RUN_TESTCOVERAGE=${DEVOPS_RUN_TESTCOVERAGE:-false}
NormalizeBoolVariable INSTALL_DOTNET INSTALL_PWSH INSTALL_DOCKER DEVOPS_RUN_TESTCOVERAGE 

if [ $IS_LAB_AGENT == true ]; then
    # The official Linux apt repositories are very robust, but packages.microsoft.com
    # is not. In any case, build/test jobs using this script will benefit from having
    # more retries. The timeout value is in seconds. Sometimes packages.microsoft.com
    # is so bad that it takes tens of seconds just to establish the HTTPS connection.
    #
    echo 'APT::Acquire::Retries "10";' > /etc/apt/apt.conf.d/80-retries
    echo 'Acquire::http::Timeout "30";' > /etc/apt/apt.conf.d/99-timeout
fi

# Print help message.
#
function PrintHelp
{
    echo " Script to install native Linux dependencies. If no option "
    echo " is used, this script will install dependencies to run palrun. "
    echo
    echo " Usage: $(/usr/bin/basename $0) [--debug] [-h | --help]"
    echo
    echo " Options:"
    echo "   -h, --help  Display this help information."
    echo "   --runtime   Installs dependencies for running palrun. This does "
    echo "               not include the whole set of dependencies for dbgbridge "
    echo "               and testing. "
    echo "   --debug     Installs dependencies for running dbgbridge."
    echo "   --test      Installs dependencies for running tests (includes runtime and debug)."
    echo "   --build     Installs dependencies for being able to build the whole "
    echo "               Linux HE repo."
    echo "   --aegis     Installs dependencies for within the Aegis containers. "
    echo "               This includes runtime, but also Aegis-specific things like"
    echo "               Docker"
    echo "   --docker    Includes the Docker deaemon and CLI."
    echo "   --bootstrap Installs dependencies for bootstraping the image."
    echo
    exit 1
}

# 'unnattended-upgrades can hold the apt lock randomly for a long time which can cause our
# install scripts to fail. This has been shown to cause flakiness, and it is not useful
# to our images.
#
function Uninstall_UnattendedUpgrades_Package()
{
    if [ $IS_LAB_AGENT == true ]; then
        apt remove -y unattended-upgrades || true
    fi
}

Uninstall_UnattendedUpgrades_Package

function AddVTune
{
    # Add Intel oneAPI repo.
    #
    wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | gpg --dearmor | tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null

    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | tee /etc/apt/sources.list.d/oneAPI.list

    ExecuteWithRetry apt update

    DEPENDENCIES+="intel-oneapi-vtune "
}

function AddTestDependencies
{
    DEPENDENCIES+="gdb "
    DEPENDENCIES+="hostname "
    DEPENDENCIES+="libgssapi-krb5-2 "
    DEPENDENCIES+="cabextract "
    DEPENDENCIES+="freetds-bin "
    DEPENDENCIES+="unzip "
    DEPENDENCIES+="openjdk-8-jre "
    DEPENDENCIES+="jq "
    DEPENDENCIES+="mysql-client "
    DEPENDENCIES+="net-tools "
    DEPENDENCIES+="lsof "
    DEPENDENCIES+="iproute2 "
    DEPENDENCIES+="bzip2 "
    DEPENDENCIES+="moreutils "

    # Not strictly necessary, but saves a lot of time for the tests
    # that capture and zip dumps.
    #
    DEPENDENCIES+="lbzip2 pbzip2 "

    # For sar monitoring.
    #
    DEPENDENCIES+="sysstat "

    # Dummy NFS shares are created during GCI to validate special cases
    # around those filesystems.
    #
    DEPENDENCIES+="nfs-kernel-server nfs-common rpcbind "

    INSTALL_DOTNET=true
    INSTALL_PWSH=true
}

function AddBootstrapDependencies
{
    DEPENDENCIES+="gettext " # git
    DEPENDENCIES+="autoconf " # git, JQ
    DEPENDENCIES+="automake "
    DEPENDENCIES+="libtool m4 " # ->autoconf
    DEPENDENCIES+="pkg-config " # ->libpmem
    DEPENDENCIES+="libncurses5-dev "
    DEPENDENCIES+="gzip "
    DEPENDENCIES+="grep "
    DEPENDENCIES+="libudev1 "
    DEPENDENCIES+="openssl "
}

function AddBuildDependencies
{
    # Primitive dependencies used throughout our build and scripts.
    #
    DEPENDENCIES+="curl "
    DEPENDENCIES+="wget "
    DEPENDENCIES+="rsync "
    DEPENDENCIES+="unzip "
    DEPENDENCIES+="sudo "
    DEPENDENCIES+="jq "
    DEPENDENCIES+="make "
    DEPENDENCIES+="uuid-dev "
    DEPENDENCIES+="ninja-build "
    DEPENDENCIES+="libncurses5 "
    DEPENDENCIES+="lsb-release "
    DEPENDENCIES+="libffi-dev " # This is generic, but we appear to only need it for buildtool.

    DEPENDENCIES+="libnuma-dev "
    DEPENDENCIES+="libpam0g-dev "
    DEPENDENCIES+="libsss-nss-idmap-dev "
    DEPENDENCIES+="libsasl2-dev "
    DEPENDENCIES+="libcurl4-gnutls-dev " # for buildtool
    DEPENDENCIES+="libgnutls28-dev " # for libcurl4-gnutls-dev

    DEPENDENCIES+="libudev-dev "
    DEPENDENCIES+="xfslibs-dev "
    DEPENDENCIES+="xfsprogs "

    # These are for the various security / crypto features of SQLPAL,
    # like the kerberos authentication and such.
    #
    DEPENDENCIES+="libavahi-client3 "
    DEPENDENCIES+="libavahi-common-data "
    DEPENDENCIES+="libavahi-common-dev  "
    DEPENDENCIES+="libavahi-common3 "
    DEPENDENCIES+="libavahi-core-dev "
    DEPENDENCIES+="libavahi-core7 "
    DEPENDENCIES+="libkrb5-dev "
    DEPENDENCIES+="libldap2-dev "
    DEPENDENCIES+="libsasl2-dev "
    DEPENDENCIES+="libsasl2-modules "
    DEPENDENCIES+="libsasl2-modules-db "

    DEPENDENCIES+="libssl-dev "

    # Required to build curl python wheel.
    #
    DEPENDENCIES+="build-essential "

    # For sar monitoring.
    #
    DEPENDENCIES+="sysstat "

    NormalizeBoolVariable ENABLE_VTUNE
    if [ "${ENABLE_VTUNE:-false}" == "true" ]; then
        AddVTune
    fi

    INSTALL_DOTNET=true
    INSTALL_PWSH=true 
    INSTALL_AZCLI=true
}

function AddAegisDependencies
{
    DEPENDENCIES+="rsync "
    DEPENDENCIES+="gawk "
    DEPENDENCIES+="wget "
    DEPENDENCIES+="sed "
    INSTALL_DOCKER=true
}

function AddDebugDependencies
{
    # Bare minimum dependencies for the dbgbridge docker image.
    # Try to keep the image as small as possible.
    # These are required for dbgbridge and minidump-2-core binaries.
    #
    DEPENDENCIES+="libedit-dev "
    DEPENDENCIES+="libatomic1 "

    # Minidump-2-core and lldb (which also drags the whole llvm too because
    # of our advanced usage of lldb) are compiled differently than everything
    # else, and they explicitly require libc++. This is not strictly required
    # for SQLPAL to work, it is only for being able to debug.
    #
    DEPENDENCIES+="libc++1 "
    DEPENDENCIES+="libc++abi1 "
}

function AddRuntimeDependencies
{
    DEPENDENCIES+="locales "

    DEPENDENCIES+="tzdata "
    DEPENDENCIES+="openssl "
    DEPENDENCIES+="libatomic1 "
    DEPENDENCIES+="libnuma1 "
    DEPENDENCIES+="libc++1 "    

    # In case of crash.
    #
    DEPENDENCIES+="tar bzip2 "

    # All the following are LDAP/Kerberos related.
    #
    DEPENDENCIES+="libgssapi-krb5-2 "
    DEPENDENCIES+="libsss-nss-idmap0 "
    if [ ${UBUNTU_VERSION_MAJOR} -ge 23 ]; then
        DEPENDENCIES+="libldap2 "
    elif [ ${UBUNTU_VERSION_MAJOR} == 22 ]; then
        DEPENDENCIES+="libldap-2.5-0 "
    else
        DEPENDENCIES+="libldap-2.4-2 "
    fi
    DEPENDENCIES+="libsasl2-2 "
    DEPENDENCIES+="libsasl2-modules-gssapi-mit "
}

# Executes "apt update", but with a friendly description and execution times.
#
function AptGetUpdate
{
    local description="apt update ($1)"
    ExecuteLengthyBlock "$description" ExecuteWithRetry apt update
}

#---------------------------------------------------------
# Function: InstallAzCli
#
# Description:
#    Installs the Azure CLI.
#
function InstallAzCli
{
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
}


# Parse arguments.
#
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
    -h|--help)
        PrintHelp
        ;;
    --debug)
        DEBUG=true
        shift
        ;;
    --test)
        TEST=true
        DEBUG=true
        RUNTIME=true
        shift
        ;;
    --docker)
        INSTALL_DOCKER=true
        shift
        ;;
    --runtime)
        RUNTIME=true
        shift
        ;;
    --build)
        BUILD=true
        shift
        ;;
    --bootstrap)
        BOOTSTRAP=true
        shift
        ;;
    *)
        PrintHelp
        ;;
    esac
done

if [[ "$BUILD" != true ]] && [[ "$RUNTIME" != true ]] && [[ "$DEBUG" != true ]]; then
    echo "Defaulting to --runtime."
    RUNTIME=true
fi

AptGetUpdate "Initial"

if [[ "$AEGIS" == true ]]; then
    apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg
    INSTALL_DOCKER=true
fi

if [[ "$INSTALL_DOCKER" == true ]]; then
    DEPENDENCIES+="apt-transport-https ca-certificates curl software-properties-common gnupg "
fi

if [[ "${DEBUG}" == true ]]; then
    echo
    echo "Installing debug dependencies"
    echo
    AddDebugDependencies
fi

if [[ "${TEST}" == true ]]; then
    echo
    echo "Installing test dependencies"
    echo
    AddTestDependencies
fi

if [[ "${BUILD}" == true ]]; then
    echo
    echo "Installing build dependencies"
    echo
    AddBuildDependencies
fi

if [[ "${AEGIS}" == true ]]; then
    echo
    echo "Installing Aegis dependencies"
    echo
    AddAegisDependencies
fi

if [[ "${RUNTIME}" == true ]]; then
    echo
    echo "Installing runtime dependencies"
    echo
    AddRuntimeDependencies
fi

if [[ "${BOOTSTRAP}" == "true" ]]; then
    echo
    echo "Installing boostrap dependencies"
    echo
    AddBootstrapDependencies
fi

if [[ "${DEVOPS_RUN_TESTCOVERAGE}" == true ]]; then
    DEPENDENCIES+="lcov gcovr "
fi

ExecuteLengthyBlock "apt" ExecuteWithRetry apt -y install $DEPENDENCIES

# Reset the dependencies list, some things (like docker) need to be installed as a second
# step.
#
DEPENDENCIES=""

if [ $INSTALL_DOTNET == true ]; then
    EnsureHasDotnet

    if [ $INSTALL_PWSH == true ]; then
        EnsureHasPowershell
    fi
fi

if [ $INSTALL_AZCLI == true ]; then
    InstallAzCli
fi

# Under WSL, it is much more powerful to use Docker Desktop than to use a regular
# dockerd installation on the Linux side. Users can still do it manually if they
# really want, but by default, skip it. For every other environment (regular VMs,
# cloud agents), install docker.
#
if [ $INSTALL_DOCKER == true ]; then
    if [ $IS_WSL == true ]; then
        NormalizeBoolVariable INSTALL_DOCKER_ON_WSL

        if [ $INSTALL_DOCKER_ON_WSL == true ]; then
            echo "INSTALL_DOCKER_ON_WSL is set, will install regular dockerd"
        elif [ "$(HasProgramInPath docker)" == true ]; then
            echo "Not installing dockerd, and 'docker' already exists in PATH."
            INSTALL_DOCKER=false
        else
            echo "Not installing docker on WSL. There are multiple options:"
            echo "- Install Docker Desktop with WSL integration (the most convenient choice)"
            echo "- Define INSTALL_DOCKER_ON_WSL and rerun this script"
            echo "- Install dockerd manually."
            INSTALL_DOCKER=false
        fi
    elif IsContainer; then
        echo "Not installing docker inside a container. If you do want nested docker "
        echo "usage, you should install 'docker-ce-cli' manually."
    fi
fi

if [ $INSTALL_DOCKER == true ]; then
    mkdir -p /etc/apt/keyrings

    RobustDownloadString https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        ${DISTRO_CODENAME} stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    DEPENDENCIES+="docker-ce docker-ce-cli containerd.io "
fi

if [ $IS_DEVOPS == true ] && [ $SYSTEM_ARCH_FRIENDLY_NAME == "x64" ] && [ $BOOTSTRAP == true ]; then
    # Pre-install the 'azsec' and monitoring packages. 1ES Hosted Pools do this at VM provisioning 
    # time, so doing this at image creation time should speed that up. Also, at this time, azsec 
    # does not yet support anything newer than 20.04, so we are actually required to do this as a hack
    # in order to have anything to work at all. On anything newer than Ubuntu 20, pull the packages of 
    # Ubuntu 20. They may not actually work (or may not be compliant), but at this time we are only using
    # Ubuntu 21/22 for tests, so it does not matter, and this unblocks it. This is only available in X64.
    #
    # Taken from https://dev.azure.com/mseng/_search?action=contents&text=azsec-monitor&type=code&lp=custom-Collection&filters=&pageSize=25&includeFacets=false&result=DefaultCollection/Domino/CloudTest/GBmaster//private/Services/Worker/Base/Linux/Geneva/install-geneva.sh
    #
    if [[ $UBUNTU_VERSION_MAJOR -le 20 ]]; then
        os_id=$( grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"' )
        os_code=$( cat /etc/os-release | grep VERSION_CODENAME | cut -d '=' -f2 )
    else
        os_id=ubuntu
        os_code=focal
    fi
      
    echo "deb [arch=amd64 trusted=yes] https://packages.microsoft.com/repos/microsoft-${os_id}-${os_code}-prod ${os_code} main" | sudo tee /etc/apt/sources.list.d/azure.list
    echo "deb [arch=amd64 trusted=yes] https://packages.microsoft.com/repos/azurecore ${os_code} main" | sudo tee -a /etc/apt/sources.list.d/azure.list

    ExecuteWithRetry apt install -y apt-transport-https ca-certificates

    AptGetUpdate "AzSec"
    ExecuteLengthyBlock "apt" ExecuteWithRetry apt -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" install -y --allow-unauthenticated azure-mdsd azure-security azsec-monitor azsec-clamav
fi

if [ -n "$DEPENDENCIES" ]; then
    AptGetUpdate "Second pass"
    ExecuteLengthyBlock "apt #2" ExecuteWithRetry apt -y install $DEPENDENCIES
fi

Uninstall_UnattendedUpgrades_Package
