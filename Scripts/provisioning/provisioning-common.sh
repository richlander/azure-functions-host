#!/bin/bash -xeu

# Defines ExecuteWithRetry and other common utilities, as well as most version-related
# and environment-related variables.
#
source "$(dirname "$BASH_SOURCE")/../common-utilities.sh"

# This script can get 'source'd multiple times in a single build step. To reduce the noise,
# disable -x mode. There is not much of interest to log the initialization of global variables 
# in this file.
#
PushBashOptionSet +x

# Enforce these options for the scope of this script, but revert them back to whatever
# the caller was using at the very end of this file.
#
PushBashOptionSet -eEu

SQLPAL_PROVISIONING_ROOT_DIR="${SQLPAL_PROVISIONING_ROOT_DIR:-/var/lib/hls}"

# These are created and filled by provision-linux-vm.sh.
#
export SQLPAL_PROVISIONING_ROOT_DIR
export SQLPAL_PROVISIONING_PATH_DIR="${SQLPAL_PROVISIONING_ROOT_DIR}/GlobalPATH"

if [[ "$PATH" != *"$SQLPAL_PROVISIONING_PATH_DIR"* ]]; then
    export PATH="$SQLPAL_PROVISIONING_PATH_DIR:$PATH"
fi

function ChmodAndTestProgram
{
    local binary="${1:-}"

    if [ -z "$binary" ]; then
        FailAndExit "The program (\$1) is required"
    fi

    if [ ! -f "$binary" ]; then
        FailAndExit "Program does not exist: $binary"
    fi

    chmod +x "$binary"

    PushBashOptionSet -eE
    echo "Testing '$binary --version' -> $($binary --version | head -n 1)"
    PopBashOptions
}

#---------------------------------------------------------
# Function: AddGlobalProgram
#
# Description:
#   Validates that the given program exists, and registers it
#   to global PATH.
#
function AddGlobalProgram
{
    local i
    for ((i=1; i<=$#; i++))
    do
        # -s is required on realpath to preserve symlink names, this makes a 
        # functional difference for programs like compilers that are symlinked
        # to various names and behave differently according to their currently-
        # executing name.
        #
        local binary=$(realpath -s "${!i}")

        ChmodAndTestProgram $binary
    
        ln -fs "$binary" "/usr/local/bin/$(basename $binary)"

        mkdir -p $SQLPAL_PROVISIONING_PATH_DIR
        ln -fs "$binary" "$SQLPAL_PROVISIONING_PATH_DIR/$(basename $binary)"
    done
}

#---------------------------------------------------------
# Function: ExecuteWebInstallScript
#
# Description:
#    Downloads a shell script from a URL, and executes it with
#    the provided arguments.
#
# Required parameters:
#   $1     : The URL to the script
#   $2...  : The arguments to the script
#
function ExecuteWebInstallScript
{
    local url="$1"
    
    # Discard the URL from the arguments, and everything else will be passed to the
    # script.
    #
    shift

	local scriptFile="$(mktemp --suffix=--install-script.sh)"

	echo "Downloading $url..."
	RobustDownload "$url" "$scriptFile"
	chmod +x "$scriptFile"
	ExecuteWithRetry "$scriptFile" "$@"
	rm "$scriptFile"
} 

#---------------------------------------------------------
# Function: InstallCMake
#
# Description:
#    Installs a modern version of CMake from the official 
#    repo.
#
function InstallCMake
{
	cmakeInstallFile=$(mktemp)
	cmakeVersion="3.27.6"
	cmakeInstallDir="${SQLPAL_PROVISIONING_ROOT_DIR}/cmake/$cmakeVersion"
    mkdir -p "$cmakeInstallDir"

    ExecuteWebInstallScript \
        "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-linux-$SYSTEM_ARCH.sh" \
        --skip-license --prefix="$cmakeInstallDir"

	AddGlobalProgram "$cmakeInstallDir/bin/cmake"
    AddGlobalProgram "$cmakeInstallDir/bin/ctest"
}

#---------------------------------------------------------
# Function: EnsureHasDotnet
#
# Description:
#    Checks for Dotnet and install if required. 
#
# Optional arguments:
#    $1 - Minimum version required
#
function EnsureHasDotnet
{
    local minVer=${1:-"6.0.0"}

    PushBashOptionSet +eE
    dotnetVer=$(dotnet --version | grep -oP '.*\K[[0-9]+\.[0-9]+\.[0-9]+.*')
    res=$?
    PopBashOptions

    if  [ "$res" -ne 0 ] || VersionLessThan $dotnetVer $minVer; then
        InstallDotnet
    fi
}

#---------------------------------------------------------
# Function: InstallDotnet
#
# Description:
#    Installs the dotnet SDK and runtime. 
#
function InstallDotnet
{
    # By default, dotnet-install.sh will install in a per-user directory (to avoid sudo), but for
    # all of our usecases (both GCI and dev setup), we want it to go to global, so that dotnet
    # commands seamlessly always work. Some random tools are also hardcoded to look for /usr/share/dotnet.
    #
    local dotnetGlobalDir=/usr/share/dotnet

    # Install latest LTS (6.0 for now).
    #
    ExecuteWebInstallScript \
        "https://dot.net/v1/dotnet-install.sh" \
        --install-dir "${dotnetGlobalDir}" --channel 6.0

    # Override any system-provided package files.
    # UNDONE: We may want to switch to a "init/activate" based approach to avoid
    # messing up with system packages.
    # 
    mkdir -p /etc/dotnet
    echo "${dotnetGlobalDir}" > /etc/dotnet/install_location
    echo "${dotnetGlobalDir}" > /etc/dotnet/install_location_x64
    find /etc/profile.d/ -type f -exec sed -i 's:DOTNET_ROOT=.*:DOTNET_ROOT=/usr/share/dotnet:g' {} \;

    # The python KeyRing thing is not clever enough to look at the well-defined default location 
    # for dotnet, so we must add it to PATH as well.
    #
    AddGlobalProgram "${dotnetGlobalDir}/dotnet"
}


#---------------------------------------------------------
# Function: EnsureHasPowershell
#
# Description:
#    Checks for Powershell and install if required. 
#
# Optional arguments:
#    $1 - Minimum version required
#
function EnsureHasPowershell
{
    local minVer=${1:-"0.0.0"}

    PushBashOptionSet +eE
    pwshVer=$(pwsh --version | grep -oP '.*\K[[0-9]+\.[0-9]+\.[0-9]+.*')
    res=$?
    PopBashOptions

    if  [ "$res" -ne 0 ] || VersionLessThan $pwshVer $minVer; then
        InstallPowershellThroughDotnet
    fi
}

# The easiest and most cross-platform way to install powershell is actually through the dotnet CLI.
# Powershell's own one-liner install scripts have arbitrary restrictions on the OS, even though
# it would actually work in all of our supported distros.
#
function InstallPowershellThroughDotnet
{
    # Dotnet tool install notoriously has issues when your working directory (or its ancestors,
    # up to the root) include a "nuget.config" file. Make our own.
    #
    local tmpPwshInstallDir="$(mktemp -d --suffix=--pwsh-install)"
    local tmpNugetConfig="$tmpPwshInstallDir/pwsh-custom-nuget.config"

    # Dotnet tools are always installed through nuget.org, even if the general policy is that
    # nuget.org is forbidden (for feeds in normal pipelines). We could _maybe_ upstream that
    # through SqlHelsinki, but that would require keeping the version up-to-date in our 
    # SqlHelsinki copy, because otherwise whatever version we have there will stay forever,
    # dotnet will not know to go look for newer versions upstream. The "Powershell" nuget is
    # a "protected prefix" in nuget.org, meaning it cannot be hijacked anyway, so this is not
    # a security hazard either.
    #
    cat<<-EOF > "$tmpNugetConfig"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
EOF
    
    local sqlpalPwshDir="${SQLPAL_PROVISIONING_ROOT_DIR}/pwsh"

    PushBashOptionSet +eE

    # Check tool version. Uninstalling then reinstalling does not work with docker:
    # "Failed to uninstall tool package 'powershell': Invalid cross-device link".
    #
    action="none"
    pwshVer=$(dotnet tool list --tool-path "${sqlpalPwshDir}" | grep -oP 'powershell\s+\K[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$?" -eq 0 ]; then
        # Tool is already installed.
        #
        echo "Found powershell at version $pwshVer"

        if VersionLessThan "$pwshVer" "7.2.13"; then
            action="update"
        fi
    else
        # Tool is not installed.
        #
        action="install"
    fi

    PopBashOptions

    if [ "$action" != "none" ]; then

        # Restrict to 7.2.x because of net6.0 compatibility.
        #
        # This function is typically executed as root, and executing "dotnet tool install"
        # may result in creating a few things that are actually shared in tmp, such as
        # '/tmp/NugetScratch'. Avoid permission conflicts by redirecting temp to this throwaway
        # folder for this one command. This way, we do not have to special-case any internal
        # details of this install script.
        #
        TMPDIR="$tmpPwshInstallDir" \
            dotnet tool "$action" --tool-path "${sqlpalPwshDir}" powershell --version "7.2.*" --configfile "$tmpNugetConfig"
        
        installRes=$?

        rm -rf "$tmpPwshInstallDir"
    fi
    
    AddGlobalProgram "${sqlpalPwshDir}"/pwsh
}

function GetPackageInstallDir
{
    EnsureIsVariableDefined NAME
    EnsureIsVariableDefined VERSION
    EnsureIsVariableDefined BUILDID
    EnsureIsVariableDefined SQLPAL_PROVISIONING_ROOT_DIR

    echo "${SQLPAL_PROVISIONING_ROOT_DIR}/${NAME}/${VERSION}-${BUILDID}"
}

function EnsureHasArtifactTool
{
    if [ "$(HasProgramInPath artifacttool)" != "true" ]; then
        echo "'artifacttool' is not in path, attempting to download it..."
        # Some variables cause problems, such as PAT_VAR, we need to clean them.
        # UNDONE: Other variables might be problematic. Maybe we should reconsider 
        # the parameters as variables paradigm.
        #
        env -u PAT_VAR $(dirname "$BASH_SOURCE")/download-artifacttool.sh
    fi
}

function PublishUpack
{
    local artifacttool=$(EnsureHasArtifactTool)

    EnsureIsVariableDefined SOURCE_DIR
    EnsureIsVariableDefined VERSION
    EnsureIsVariableDefined NAME
    EnsureIsVariableDefined FEED

    local tarTempDir=
    local sourceDir="$SOURCE_DIR"

    if [ "${TAR:-false}" == true ]; then
        tarTempDir="$(mktemp -d --suffix=-$NAME-$VERSION-upack)"

        tarFile="${tarTempDir}/${NAME}-${VERSION}.tar"
        echo "TAR'ing to $tarFile"
        tar -cvf "$tarFile" -C "${sourceDir}" .
        ls -lh $tarFile

        sourceDir="$tarTempDir"
    fi

    ExecuteWithRetry \
        artifacttool universal publish \
            --unstructured-logging \
            --feed $FEED \
            --service "https://dev.azure.com/${ORG:-sqlhelsinki}/" \
            --package-name $NAME \
            --package-version $VERSION \
            --path "$sourceDir" \
            --patvar "${PAT_VAR:-SYSTEM_ACCESSTOKEN}" \
            --verbosity ${VERBOSITY:-None}

    if [ -n "$tarTempDir" ]; then
        rm -rf "$tarTempDir"
    fi
}

function DownloadUpack
{
    local artifacttool=$(EnsureHasArtifactTool)

    EnsureIsVariableDefined NAME
    EnsureIsVariableDefined FEED

    local tempDest=$(mktemp -d)
    local packageDir=${PACKAGE_DIR:-$NAME}
    local rootInstall=$(GetNormalizedBool ${ROOT_INSTALL:-false})
    local installPrefix="${SQLPAL_PROVISIONING_ROOT_DIR}/${packageDir}"
    local version="${FULL_VERSION:-}"

    if [ -z "$version" ]; then
        EnsureIsVariableDefined VERSION
        EnsureIsVariableDefined BUILDID
        version="${VERSION}${BUILD_PACKAGE_SUFFIX}-${BUILDID}"
    fi

    if [ "$rootInstall" == true ]; then
        local finalDest=/
        local programsPrefix=$(GetPackageInstallDir)
    else
        local finalDest="${DESTINATION:-$SQLPAL_PROVISIONING_ROOT_DIR/$packageDir}"
        local programsPrefix="$finalDest"
    fi

    local forwardEnv=()
    if [ ${PAT_VAR+x} ]; then
        forwardEnv+=( 
            ${PAT_VAR}
            )
    fi

    FORWARD_ENV=${forwardEnv[@]:-} \
        ExecuteWithRetry \
            artifacttool universal download \
                --unstructured-logging \
                --feed $FEED \
                --service "https://dev.azure.com/${ORG:-sqlhelsinki}/" \
                --package-name "$NAME" \
                --package-version "$version" \
                --path "$tempDest" \
                --patvar "${PAT_VAR:-SYSTEM_ACCESSTOKEN}" \
                --verbosity ${VERBOSITY:-None}

    UnpackOrMove "$tempDest" "$finalDest" "${UNPACK:-false}"

    if [ -n "${GLOBAL_PROGRAMS:-}" ]; then
        local programs=$(eval "ls $programsPrefix/$GLOBAL_PROGRAMS")
        AddGlobalProgram $programs
    fi
}

function UnpackOrMove
{
    local source="$1"
    local destination="$2"
    local unpack=${3:-false}

    if [ $unpack == true ]; then
        mkdir -p "$destination"

        local unpackedAnything=false

        # Tar uses -h to ensure symlinks are not overwritten by folders, which
        # is the default behavior.
        #

        if [ -z "$(ls "$source"/*.tar* 2>&1 >/dev/null)" ]; then
            find "$source" -name '*.tar*' -exec tar --keep-directory-symlink --no-overwrite-dir -xf {} -C "$destination" \;
            unpackedAnything=true
        fi

        if [ -z "$(ls "$source"/*.tgz 2>&1 >/dev/null)" ]; then
            find "$source" -name '*.tgz' -exec tar --keep-directory-symlink --no-overwrite-dir -xzf {} -C "$destination" \;
            unpackedAnything=true
        fi

        if [ $unpackedAnything == false ]; then
            FailAndExit "The package did not contain any tar file, should UNPACK be false?"
        fi

        rm -rf "$source"
    else
        mv "$source/" "$destination/"
    fi
}

# Function: InstallPipProgram
#
# Description:
#   Installs a program obtained from python pip to PATH. This creates
#   a dedicated venv for each program, because python dependencies are
#   a mess, and especially so with Azure-related programs. With dedicated
#   venv, they cannot break eachother, at least.
#
# Required parameters:
#   $1: The PIP package
#
# Optional parameters:
#   $2: The program inside the package, if different than the package name.
#
# Required variables:
#  SQLPAL_PYTHON: The location to python3.
#
function InstallPipProgram
{
	local pipPackage="$1"
	local program="${2:-$pipPackage}"
    EnsureIsVariableDefined SQLPAL_PYTHON

	local venv="${SQLPAL_PROVISIONING_ROOT_DIR}/$pipPackage"
	$SQLPAL_PYTHON -m venv $venv
	ExecuteWithRetry $venv/bin/pip install --upgrade pip
	ExecuteWithRetry $venv/bin/pip install --upgrade setuptools wheel
	ExecuteWithRetry $venv/bin/pip install --upgrade $pipPackage
	AddGlobalProgram $venv/bin/$program
}

# Function: PublishBinariesNuget
#
# Description:
#   Publishes a nuget that is not really a 'nuget' in the classic sense (intended for dotnet),
#   but instead a zip whose only interesting contents are the $/tools directory inside it.
#   This is used as a trick when universal packages are not suitable.
#
# Required variables:
#   SOURCE_DIR: The contents that will go into tools/ inside the nuget.
#   VERSION
#   NAME
#   FEED
#
function PublishBinariesNuget
{
    EnsureIsVariableDefined SOURCE_DIR
    EnsureIsVariableDefined VERSION
    EnsureIsVariableDefined NAME
    EnsureIsVariableDefined FEED

    # Normalize them to lowercase.
    #
    local NAME=${NAME,,}
    local VERSION=${VERSION,,}

    local tempCsprojDir=$(mktemp -d --suffix=-$NAME-dummy-csproj)
    local tempCsproj="$tempCsprojDir/proj.csproj"
    
    # 'dotnet pack' is the easiest way to use nuget in a cross-platform manner, rather
    # than using the 'Nuget' program directly. When using 'dotnet pack', nuspecs are not
    # supported, a proper valid 'csproj' is required instead. This fragment is the 
    # minimum we need to have a working csproj that produces the nuget package that we need.
    #
    cat<<-EOF > "$tempCsproj"
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <PackageVersion>$VERSION</PackageVersion>
        <PackageId>$NAME</PackageId>
        <Title>$NAME</Title>
        <Authors>SQLPAL</Authors>
        <Description></Description>
        <PackageTags>SQLPAL</PackageTags>
        <TargetFramework>net6.0</TargetFramework>
        <IncludeContentInPack>true</IncludeContentInPack>
        <IncludeBuildOutput>false</IncludeBuildOutput>
        <ContentTargetFolders>content</ContentTargetFolders>
        <NoWarn>\$(NoWarn);NU5128</NoWarn>
        <NoDefaultExcludes>true</NoDefaultExcludes>
    </PropertyGroup>
    <ItemGroup>
        <Content Include="$(realpath $SOURCE_DIR)/**/*">
            <PackagePath>tools/</PackagePath>
            <Pack>true</Pack>
        </Content>
    </ItemGroup>
</Project>
EOF

    dotnet pack --nologo -o "$tempCsprojDir" "$tempCsproj"
    local result=$?

    if [ $result != 0 ]; then
        FailAndExit "dotnet pack failed with $result"
    fi

    local nupkg="$tempCsprojDir/$NAME.$VERSION.nupkg"
    ls -lh "$nupkg"

    local feedUrl=https://sqlhelsinki.pkgs.visualstudio.com/_packaging/$FEED/nuget/v3/index.json
    ExecuteWithRetry dotnet nuget push "$nupkg" -k ADO -s "$feedUrl"

    rm -rf "$tempCsprojDir"
}

# Function: DownloadToolNuget
#
# Description:
#   Downloads a nuget that is not really a 'nuget' in the classic sense (intended for dotnet),
#   but instead a zip whose only interesting contents are the $/tools directory inside it.
#   This is used as a trick when universal packages are not suitable.
#
# Required variables:
#  - NAME
#  - FEED
#  - DESTINATION: The location where the tools/ subdirectory will be extracted.
#
#  - VERSION + BUILDID, where VERSION is like 1.2.3 and BUILDID is the Devops build number.
#      or
#  - FULL_VERSION
#
# Optional variables:
# - PAT_VAR: Default: SYSTEM_ACCESSTOKEN. This is the variable's name, not value.
#
# - UNPACK: If "true", the nuget contains a single tar that should be extracted to DESTINATION.
#   Nugets are already a ZIP in the first place, so this is not to achieve extra compression or anything.
#   Instead, this is to preserve symlinks, which are very common in Linux packages. When this option is
#   used, the nuget will be a zip containing a single tar, which consummers must then untar.
#
function DownloadToolNuget
{
    EnsureIsVariableDefined NAME
    EnsureIsVariableDefined FEED
    EnsureIsVariableDefined DESTINATION

    local version="${FULL_VERSION:-}"

    if [ -z "$version" ]; then
        EnsureIsVariableDefined VERSION
        EnsureIsVariableDefined BUILDID
        version="${VERSION}${BUILD_PACKAGE_SUFFIX}-${BUILDID}"
    fi

    local nugetUrl="https://pkgs.dev.azure.com/sqlhelsinki/_apis/packaging/feeds/$FEED/nuget/packages/$NAME/versions/$version/content?api-version=6.0-preview"
    local nupkgFile="$(mktemp --suffix=$NAME-$version.nupkg)"

    local patVar="${PAT_VAR:-SYSTEM_ACCESSTOKEN}"

    PAT_VAR=$patVar \
        RobustDownload "$nugetUrl" "$nupkgFile"

    local rawNugetDir="$(mktemp -d --suffix=$NAME-$version-nupkg-unzip)"

    # Some old versions of unzip can prompt for things when there are errors,
    # we do not want any prompt as that would stall the build, so redirect
    # stdin to null.
    #
    unzip -q $nupkgFile -d "$rawNugetDir" < /dev/null || true

    local toolsDir="$rawNugetDir/tools"

    if [ ! -d "$toolsDir" ]; then
        FailAndExit "Expected to find tools/ inside the nuget."
    fi

    rm $nupkgFile

    UnpackOrMove "$toolsDir" "$DESTINATION" "${UNPACK:-false}"
}

function NormalizeUpackVersion
{
    local ver=${1:-}

    if [ -z "$ver" ]; then
        FailAndExit "The version (\$1) is required"
    fi

    # If the caller provided a git ref (refs/tags/... or refs/heads/...),
    # remove that.
    #
    match=$(echo $ver | grep -oP "^refs/(heads|tags)/(\K.*)")
    if [ -n "$match" ]; then
        ver="$match"
    fi

    # A lot of repositories use the convention of 'v1.2.3' for their release tags.
    # If we find that, discard the 'v' prefix.
    #
    match=$(echo $ver | grep -oP "^v(\K([0-9]+\.)+.*)")
    if [ -n "$match" ]; then
        ver="$match"
    fi

    # Some repositories use a convention of putting the project name as a prefix too,
    # such as the 'jq-15.0' tags for jq.
    #
    if [ -n "${POSSIBLE_PREFIX:-}" ]; then 
        match=$(echo $ver | grep -oP "^$POSSIBLE_PREFIX[-_](\K([0-9]+\.)+.*)")
        if [ -n "$match" ]; then
            ver="$match"
        fi
    fi

    # If this is a 2-digit version, make it a 3-digit with a zero.
    #
    match=$(echo $ver | grep -oP "^(\K[0-9]+\.[0-9]+)$")
    if [ -n "$match" ]; then
        ver="$match.0"
    fi

    # If this is a 4+ digit version (some schemes even do 5), make that 3, and put 
    # the fourth and beyond behind a dash.
    #
    match=$(echo $ver | grep -oP "^(\K[0-9]+(\.[0-9]+){3,})")
    if [ -n "$match" ]; then
        firstThree=$(echo $ver | grep -oP "^(\K[0-9]+(\.[0-9]+){2})")
        firstThreeLength=$(echo $firstThree | wc -m)
        everythingElse="${ver:$firstThreeLength}"
        ver="$firstThree-$everythingElse"
    fi

    echo $ver
}

function CleanAllPackageManagerCaches
{
	if [ "$IS_UBUNTU" == true ]; then
		apt clean
	elif [ "$IS_RHEL" == true ]; then
		yum clean all
	elif [ "$IS_SLES" == true ]; then
		zypper clean -a
    elif [ "$IS_MARINER" == true ]; then
        tdnf clean all
	else
		FailAndExit "Unsupported distribution: $DISTRONAME"
	fi

	if [ -f "${SQLPAL_PYTHON:-}" ]; then
        # Purge option is somewhat new. Ignore errors.
        #
		$SQLPAL_PYTHON -m pip cache purge || true
	fi
}

# Undo 'PushBashOptionSet -eEu'.
#
PopBashOptions

# Undo 'PushBashOptionSet +x'.
#
PopBashOptions