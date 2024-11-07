#!/bin/bash -x

# Define trap so we can see -e errors easily.
#
trap 'echo Error at ${BASH_SOURCE[0]}:$LINENO -- $BASH_COMMAND' ERR

#---------------------------------------------------------
# Function: InvokeDevopsLogCommand
#
# Description:
#   Helper to output one of the special logging commands that Devops supports, such
#   as adding a build error, or setting an environment variable at the pipeline level.
#   See https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=bash
#    
function InvokeDevopsLogCommand
{
    local cmd=$1

    # '-x' mode must be suspended before we echo the special log, because otherwise
    # the debug echo will also trigger the ##vso parsing code, and depending on the
    # commands, this will break the pipeline because when Devops fails to parse a 
    # string containing ##vso it fails the build.
    #
    PushBashOptionSet +x
    echo "##vso$cmd"
    PopBashOptions
}

#---------------------------------------------------------
# Function: WriteError
#
# Description:
#   Prints the given message as error. If running in Devops, this will use
#   the devops-specific syntax so that the error gets surfaced to the build's
#   list of warnings.
#
#   Required parameters:
#     $1 - The message.
#    
function WriteError
{
    local message=${1:-<WriteError without a message!>}

    if [ $IS_DEVOPS == true ]; then
        InvokeDevopsLogCommand "[task.logissue type=error]$message"
    else
        >&2 echo -e "ERROR: $message"
    fi
}

#---------------------------------------------------------
# Function: WriteWarning
#
# Description:
#   Prints the given message as warning. If running in Devops, this will use
#   the devops-specific syntax so that the warning gets surfaced to the build's
#   list of warnings.
#
#   Required parameters:
#     $1 - The message.
#    
function WriteWarning
{
    local message=${1:-<WriteWarning without a message!>}

    if [ $IS_DEVOPS == true ]; then
        InvokeDevopsLogCommand "[task.logissue type=warning]$message"
    else
        >&2 echo "WARNING: $message"
    fi
}

#---------------------------------------------------------
# Function: BeginDevopsLogGroup
#
# Description: Begins a logical block of logs that can be collapsed or expanded
# in the build output in Devops. These cannot be nested - it will not break the
# build, but it will display all weird.
#
#   Required parameters:
#     $1 - The title for the block.
#   
function BeginDevopsLogGroup
{
    # See comment in InvokeDevopsLogCommand.
    #
    PushBashOptionSet +x
    echo "##[group] $1"
    PopBashOptions
}   

#---------------------------------------------------------
# Function: EndDevopsLogGroup
#
# Description: Closes a scope started with BeginDevopsLogGroup.
#
function EndDevopsLogGroup
{
    # See comment in InvokeDevopsLogCommand.
    #
    PushBashOptionSet +x
    echo "##[endgroup]"
    PopBashOptions
}

#---------------------------------------------------------
# Function: PrintBacktrace
#
# Description: Prints a backtrace to stderr.
#
#   Optional Parameters:
#     $1 - The number of stack frames to skip. Defaults to 1.
#     $2 - The prefix to add to each line. Defaults to "    ".
#
function PrintBacktrace
{
    local framesToSkip=${1:-1}
    local prefix=${2:-"    "}

    frames=$(expr ${#BASH_LINENO[@]} - 2)
    for i in $(seq $framesToSkip $frames); do
        echo "${prefix}${FUNCNAME[$i]}() called at ${BASH_SOURCE[$i+1]}:${BASH_LINENO[$i]}"
    done
}

#---------------------------------------------------------
# Function: FailAndExit
#
# Description:
#   Prints the given failure reason as error, and exits the current program.
#
#   Required parameters:
#     $1 - The reason for failure.
#    
function FailAndExit
{
    local message=${1:-"FailAndExit was called"}
    WriteError "$message"

    # Show call stack leading to failure.
    #
    PrintBacktrace

    # This is only a convenience when testing script modifications locally,
    # this variable is never set otherwise, as we always expect to exit.
    #
    if [ "${FAILANDEXIT_SKIP_EXIT:-}" != true ]; then
        exit 1
    fi
}

#---------------------------------------------------------
# Function: NormalizeBoolVariable
#
# Description:
#    Takes a list of variables as input (their names as string), and
#    normalizes their values as literal lowercase 'true' or 'false'. If 
#    a value is not recognized, defaults to false. Recognizes the most 
#    common boolean pairs, such as true/1/y/yes/ON. '$STRICT' can be
#    set to true to fail on unrecognized input instead of returning
#    false.
#
#    Note: If a variable is not set at all, this will default it to false.
#
#  Required parameters:
#   $1+... : Names of the variables to normalize.
#
#  Optional variables:
#   $STRICT: If true, does not default unknown values to false, and fails
#            instead.
#
#  Example usage:
#       TEST=True
#       TEST2=yes
#       NormalizeBoolVariable TEST TEST2
#       echo "$TEST $TEST2" <-- both are now 'true'.
#
function NormalizeBoolVariable
{
    local strict="${STRICT:-false}"

    for ((i=1; i<=$#; i++))
    do
        local argname=${!i}
        local argvalue="${!argname}"
        argvalue="${argvalue,,}"

        # We are lax about what we support because between our bash
        # scripts, our CMake, our makefiles and buildtool, a lot of
        # combinations are supported, and to avoid being confusing to
        # the users we may as well support everything everywhere.
        #
        case "$argvalue" in
        true | 1 | on | y | yes)
            argvalue=true
            ;;
        false | 0 | off | n | no)
            argvalue=false
            ;;
        *)
            if [ $strict == true ]; then
                FailAndExit "Unrecognized boolean value: $argvalue"
            else
                argvalue=false
            fi
            ;;
        esac

        printf -v "${argname}" '%s' "${argvalue}"
    done
}

#---------------------------------------------------------
# Function: GetNormalizedBool
#
# Description:
#    Returns "true" or "false" by normalizing the input value.
#
function GetNormalizedBool
{
    # Allow $1 to be missing because it is a common mistake to write
    # `GetNormalizedBool ${MY_VAR:-}`, and if MY_VAR is missing, we
    # will not have a $1 (due to missing quotes around ${MY_VAR:-}). 
    # The caller typically assumes this should result in returning 
    # "false" as with any other invalid/missing input, so tolerate
    # it.
    #
    local value="${1-}"    
    NormalizeBoolVariable value
    echo $value
}

#---------------------------------------------------------
# Aborts the script if bash is currently in "set -x" mode. This is used 
# in places where we know are handling secrets, and it is the caller who
# should be in quiet mode.
#
function EnsureNotDebugTracing
{
    # IGNORE_ANTI_DEBUG_TRACING is only for debugging when editing these scripts,
    # it should never be set for things that pipelines or users will use by default,
    # because it allows for leaking secrets.
    # 
    local ignore=$(GetNormalizedBool "${IGNORE_ANTI_DEBUG_TRACING:-}")

    if [[ "$-" == *"x"* ]] && [[ $ignore == false ]]; then
        FailAndExit "This function cannot be called in 'set -x' mode."
    fi
}

#---------------------------------------------------------
# Function: CopySecretVariable
#
# Description:
#   Copies the value from $1 into $2, where both arguments
#   are the *names* of the variables. The source ($1) may
#   be empty. This function will not output the values to
#   the debug log, making it suitable for secrets.
#
function CopySecretVariable
{
    local sourceVarName="${1:-}"
    local destVarName="${2:-}"

    if [ -z "$sourceVarName" ]; then
        FailAndExit "The source variable name (\$1) is required"
    fi

    if [ -z "$destVarName" ]; then
        FailAndExit "The destination variable name (\$2) is required"
    fi

    EnsureIsVariableDefined $sourceVarName

    PushBashOptionSet +x
    export "$destVarName"="${!sourceVarName}"
	PopBashOptions
}

#---------------------------------------------------------
# Function: UploadDevopsBuildLog
#
# Description:
#   This command requests that Devops captures the given file and attaches
#   it to the current task's logs.
#
#   Required parameters:
#     $1 - The file containing the logs.
#
#   Optional variables:
#     - UPLOAD_AS_FILE: If false (default), the log file will be concatenated 
#       to the current task logs. If true, they will not be concatenated to the
#       current task logs (what you see in the build), but instead only be available
#       in the zip you can download from Devops when clicking "Download all logs"
#       on a build. Setting this to false is useful when the logs are of no use
#       the majority of the time, but you may still need them in rare cases for 
#       special investigations of build breaks for example.
#
function UploadDevopsBuildLog
{
    local logfile=$1
    if [ ! -f "$logfile" ]; then
        FailAndExit "File argument (\$1) is required and must be a valid file: $logfile"
    fi

    local command="build.uploadlog"
    if [ $(GetNormalizedBool "${UPLOAD_AS_FILE:-}") == true ]; then
        command="task.uploadfile"
    fi

    InvokeDevopsLogCommand "[$command]$1"
}

#---------------------------------------------------------
# Function: HasProgramInPath
#
# Description:
#   Echos 'true' if the given program can be found in PATH, 'false' otherwise.
#
#   Required parameters:
#     $1 - The program to test.
#
function HasProgramInPath
{
    local program=${1:-}

    if [ -z "$program" ]; then
        FailAndExit "Program name (\$1) is required"
    fi

    PushBashOptionSet +eE

    # The best way to accomplish this in bash is a great subject of debate, but this
    # appears to be the most popular answer.
    #
    if hash "$program" 2>/dev/null; then
        echo true
    else
        echo false
    fi

    PopBashOptions
}

#---------------------------------------------------------
# Function: SetDevopsVariable
#
# Description:
#
function SetDevopsVariable
{
    local variable=${1:-}
    local value=${2:-}

    if [ -z "$variable" ]; then
        FailAndExit "Variable name (\$1) is required"
    fi

    if [ $IS_DEVOPS == true ]; then

        local command="task.setvariable variable=$variable"

        if [ $(GetNormalizedBool $IS_OUTPUT) == true ]; then
            command+=";isoutput=true"
        fi

        InvokeDevopsLogCommand "[$command]$value"
    fi

    printf -v "${variable}" '%s' "${value}"
}

#---------------------------------------------------------
# Function: PushBashOptionSet
#
# Description:
#    Applies a change of bash options, such as "set -e". This can then be reverted
#    by PopBashOptions.
#
# Required Parameters:
#    $1..N: The option to change, such as "-x" or "+e".
#
function PushBashOptionSet
{
    # This function gets called hundreds of times in builds. Do not echo
    # anything in "set -x" mode, the "PushBashOptionSet +e" debug log
    # you get is already enough. We must implement it manually here,
    # because we cannot call ourselves recursively, but everywhere else
    # should use regular Push/PopBashOptionSet instead.
    #
    {
        local oldOptions="$-"
        set +x
    } 2>/dev/null

    local optSets=""
    for opt in "$@"
    do
        if [[ ! "$opt" =~ ^[+-][a-zA-Z]+$ ]]; then
            FailAndExit "opt (\$1) is required. Example: '-e' or '+x'"
        fi
        optSets+="$opt "
    done

    if [ -z "$optSets" ]; then
        FailAndExit "opt (\$1) is required. Example: '-e' or '+x'"
    fi

    # Push two items - the current "set" options, and the option
    # we are changing now.
    #
    BashOptionsStack+=("$oldOptions" "$optSets")

    {
        # Undo manual "set +x" above.
        #
        if [[ "$oldOptions" == *"x"* ]]; then
            set -x
        fi

        set $optSets
    } 2>/dev/null
}

#---------------------------------------------------------
# Function: PopBashOptions
#
# Description:
#    Reverts a previous PushBashOptionSet operation.
#
function PopBashOptions
{
    # This function gets called hundreds of times in builds. Do not echo
    # anything in "set -x" mode, the "PushBashOptionSet +e" debug log
    # you get is already enough. We must implement it manually here,
    # because we cannot call ourselves recursively, but everywhere else
    # should use regular Push/PopBashOptionSet instead.
    #
    { set +x; } 2>/dev/null

    # Do a sanity on the size of the stack. When calling PopBashOptions, it must always
    # be 2 or more, because each PushBashOptionSet call pushes 2 items, and in here we
    # dequeue 2-by-2 below.
    #
    local stackedItemsCount=${#BashOptionsStack[@]}
    if [[ "$stackedItemsCount" -lt 2 ]]; then
        FailAndExit "Unbalanced PopBashOptions calls"
    fi

    # Pop the two items from PushBashOptionSet (in reverse order). The shorter 
    # 'unset arr[-1]' bash syntax is not supported in our older distributions,
    # but this longer form of unset works everywhere. All these lines do is 
    # first get the last item, then remove it from the array.
    #
    local optSets=${BashOptionsStack[-1]}
    unset 'BashOptionsStack[${#BashOptionsStack[@]}-1]'
    local initialShellOptions=${BashOptionsStack[-1]}
    unset 'BashOptionsStack[${#BashOptionsStack[@]}-1]'

    local unsetOpts=""
    for opt in $optSets
    do
        # Split "-e" into 'sign=-' and 'flag=e'. There can be multiple flag characters,
        # loop over each from 1 to the end.
        #
        local sign=${opt:0:1}

        local opposite="+"
        if [ "$sign" == "+" ]; then
            opposite="-"
        fi

        local i
        local flags=""

        for (( i=1; i<${#opt}; i++ )); do
            local flag=${opt:$i:1}
            if [[ "$sign" == "-" ]]; then
                if [[ ! $initialShellOptions =~ $flag ]]; then
                    flags+=$flag
                fi
            else
                if [[ $initialShellOptions =~ $flag ]]; then
                    flags+=$flag
                fi
            fi
        done

        if [ -n "$flags" ]; then
            unsetOpts+="$opposite$flags "
        fi
    done

    {
        # Undo manual "set +x" above.
        #
        if [[ "$initialShellOptions" == *"x"* ]]; then
            set -x
        fi

        if [ -n "$unsetOpts" ]; then
            set $unsetOpts
        fi
    } 2>/dev/null

}

#---------------------------------------------------------
# Given an Ubuntu version (like "20.04"), returns "focal". Aborts the program on unknown value.
#
# Require parameters:
#   $1: The version number.
#
function UbuntuVersionToName
{
    local ver=${1:-}
    case $ver in
    "16.04") echo "xenial" ;;
    "18.04") echo "bionic" ;;
    "20.04") echo "focal" ;;
    "22.04") echo "jammy" ;;
    * )
        FailAndExit "Unsupported Linux version: $ver"
        ;;
    esac
}

#---------------------------------------------------------
# Given an Ubuntu verbose name (like "Ubuntu 22.04 LTS"), returns "22.04". Aborts the program on unknown value.
#
# Require parameters:
#   $1: The version name. Example: "Ubuntu 22.04 LTS"
#
function GetUbuntuVersionFromLsbRelease
{
    local name=${1:-}
    name=${name,,}

    if [ -z "$name" ]; then
        FailAndExit "Name (\$1) is mandatory"
    fi

    # Input: 'Ubuntu 18.04.1 LTS'
    # Extract '18.04.1', keep only "Major.Minor" (5 characters).
    #
    echo $(echo "$name" | awk '{print $2}' | head -c 5)
}

#---------------------------------------------------------
# Given a distro verbose name (like "Ubuntu 22.04 LTS"), returns 
# the identifier we use in our official packaging, such as "ubuntu2204". 
# Aborts the program on unknown value.
#
# Require parameters:
#   $1: The version name. Example: "Ubuntu 22.04 LTS"
#
function DistroNameToPackagingString
{
    local name=${1:-}
    name=${name,,}

    if [[ "$name" == "ubuntu 16"* ]]; then
        # For legacy reasons, Ubuntu 16.04 LTS is named as simply 'ubuntu' across 
        # our various scripts, as well as our public releases, so the name must 
        # stay.
        #
        echo "ubuntu"
    elif [[ "$name" == "ubuntu "* ]]; then
        # Extract '18.04', and remove the dot, to get something like "ubuntu1804".
        #
        local version=$(GetUbuntuVersionFromLsbRelease "$name")
        echo "ubuntu$(echo "$version" | sed 's/\.//')"
    else
        # This will match 'suse linux enterprise server 15' as input and return '15'.
        # Same logic for RHEL. The expected output looks like 'sles15' or 'rhel8', respectively.
        # The extra "([a-z]+ )*?" is to discard the extra words that some specific releases have,
        # such as red hat enterprise linux server 7.9 (maipo)'
        #                                  ^^^^^^
        #
        if   echo "$name" | grep -q 'suse linux enterprise server'; then
            result="sles"
        elif echo "$name" | grep -q 'sles'; then
            result="sles"
        elif echo "$name" | grep -q 'red hat enterprise linux'; then
            result="rhel"
        elif echo "$name" | grep -q 'common base linux mariner'; then
            result="mariner"
        else
            FailAndExit "Unsupported Linux version: $name"
        fi

        local ver=$(echo "$name" | grep -oP '([a-z]+ )+?(\K[0-9]+)')
        if [ $? = 0 ]; then
            echo "$result$ver"
        else
            FailAndExit "Could not extract version from '$name'"
        fi
    fi
}

#---------------------------------------------------------
# Given one of our packaging names (ubuntu, ubuntu2004, sles12, ...),
# returns the corresponding version (16.04, 20.04, 12).
#
function GetDistroVersionFromPackagingString
{
    local name=${1:-}
    name="${name,,}"

    if [[ "$name" == "ubuntu"* ]]; then
        local ver="${name:6}"

        # The special "ubuntu" case.
        #
        if [ "$ver" == "" ]; then
            echo "16.04"
        else
            # The normal "ubuntu1804" -> "18.04" case.
            #
            echo "${ver:0:2}.${ver:2:2}"
        fi
    elif [[ "$name" == "rhel"* ]] || [[ "$name" == "sles"* ]]; then
        # "rhel8" -> "8".
        #
        echo "${name:4}"
    else
        FailAndExit "Unsupported Linux version: $name"
    fi
}

#---------------------------------------------------------
# Converts from our "packaging name" such as ubuntu, ubuntu2204, rhel8, to the
# suffix we use in our public repos. For most distros, the result is the same
# as the input, but for ubuntu, the convention uses the codenames like xenial.
# This is unused in SQLPAL repo, but shared with mssql-server, where it is used.
# The reason for having it in SQLPAL repo is that this goes together with the 
# other similar functions here, and we may as well have them all together.
#
function PackagingStringToRepoName
{
    local name=${1:-}
    name="${name,,}"

    # For ubuntu, we use the version code name like Xenial.
    # For everything else, we use the same as our packaging string,
    # such as "rhel8".
    if [[ "$name" == "ubuntu"* ]]; then
        local dottedVersion=$(GetDistroVersionFromPackagingString $name)
        echo $(UbuntuVersionToName $dottedVersion)
    else
        echo "$name"
    fi
}

#---------------------------------------------------------
# Function: ExecuteWithRetry
#
# Executes the given command, retrying up to numRetries times on non-zero return
# status. If all retries fail, this exits the whole script with non-zero.
#
# Required parameters:
#   $1+: The command and arguments.
#
# Optional variables:
#  $NUM_RETRIES : Default: 5.
#  $RETRY_DELAY : Seconds, default 5.
#  $SILENT      : If true, do not echo anything, unless all attempts failed.
#  $FORWARD_ENV : List of variables to forward as environment.
#
function ExecuteWithRetry
{
    # This function gets called hundreds of times in builds, and this function's 
    # code is uninteresting boilerplate. We do log the actual command being executed
    # below, that is enough. Also disable "set -e" mode, we handle errors ourselves
    # in this function.
    #
    PushBashOptionSet +eEx; 

    local cmdArgs=("$@")
    local numRetries=${NUM_RETRIES:-5}
    local retryDelay=${RETRY_DELAY:-5}
    local retriesLeft=$numRetries
    local SILENT=${SILENT:-false}
    local envVars=""
    local attempt=0

    while [[ $retriesLeft -gt 0 ]]
    do
        ((attempt++))

        if [ $SILENT != true ]; then
            # This series of printf's is harder to read than a single regular echo, 
            # but it allows quoting each argument in our log so that it becomes 
            # obvious if there is a quoting mistake from the caller.
            #
            printf "(%d/%d) Executing: " $attempt $numRetries; printf '"%s" ' "${cmdArgs[@]}"; printf "\n"
        fi

        # Environment variables may contain secrets.
        # 
        PushBashOptionSet +x

        # Build list of environment variables to forward.
        #
        for var in ${FORWARD_ENV[@]:-};
        do
            envVars+="${var}=${!var}"
        done

        env ${envVars} "${cmdArgs[@]}"
        result=$?

        PopBashOptions

        if [[ "$result" == "0" ]]; then
            if [ $SILENT != true ]; then
                echo "Command succeeded."
            fi
            break
        fi

        if [ $SILENT != true ]; then
            echo "FAILED command: ${cmdArgs[@]}"
        fi
        ((retriesLeft--))

        if [[ "$retriesLeft" == "0" ]]; then
            echo "FAILED command after $numRetries retries: ${cmdArgs[@]}" >&2
            exit $result
        fi

        sleep $retryDelay
    done

    PopBashOptions

    return $result
}

#---------------------------------------------------------
# Executes a HTTP GET, with retries. The extra arguments allow
# downloading to a file, or outputting the result as a string.
#
# Required parameters:
#   $1+...: The custom arguments to curl.
#
# Optional variables:
#   PAT_VAR: If set, the given environment variable will be will be passed as PAT credential. 
#   This should only be used for Devops endpoints.
#
#   DOWNLOAD_TIMEOUT: Absolute duration for the timeout, in seconds. The default is 
#   900 (15 minutes).
#
function RobustDownloadInternal
{
    local extraArgs=("$@")

    local timeout=${DOWNLOAD_TIMEOUT:-900}

    # --max-time is the absolute limit for curl, everything included.
    # --speed-time/limit are different. They tell curl to abort if it has been
    # downloading at less than 100 bytes per second for the past 5 minutes. This
    # is a kind of flakiness that often happens in Devops at peak times. Devops
    # will simply stall the connection and never actually complete the request,
    # and the only solution is to detect it, abort, and try again, which fixes
    # it.
    # 
    # The "X-TFS-FedAuthRedirect" header makes Devops return the correct HTTP error
    # codes (Unauthorized, etc) on failure. By default, it will redirect requests to
    # the web login UI, and a "200 OK", which confuses scripts and automations because
    # it looks like a success.This header is not really "documented", but it is used
    # by all major applications interacting with Devops (VS, Windbg, etc).
    #
    # This utility function is called for more than just the Devops APIs that support it,
    # but sending it to unrelated services should be harmless, so keep things simple and
    # send it to everyone.
    #
    local cmd=(curl 
        --location
        --retry 5
        --retry-delay 5
        --max-time $timeout
        --speed-time 300
        --speed-limit 100
        -H "X-TFS-FedAuthRedirect: Suppress"
        --fail)

    if [ -n "${PAT_VAR:-}" ]; then
        # To attempt to hide the PAT from logs as much as possible, put it into a 
        # --config input file for curl, and add a trap to delete this file, regardless
        # of how this function exits (success, failure, interrupt). Even this is not 
        # the best recommended way of achieving this, but this works with our ExecuteWithRetry,
        # and it is still "okay". The rm "-f" flag is because this trap can trigger multiple
        # times - no need for harmless "File does not exist" errors.
        #
        local configFile=$(mktemp --suffix=--RobustDownload-curl-config.txt)
        trap "rm -f '$configFile' || true" RETURN
        AddExitCallback "rm -f '$configFile'"

        # The syntax for --config files is the same as regular command-line arguments to
        # curl.
        #
        PushBashOptionSet +x
        echo "-u \":${!PAT_VAR}\"" > $configFile
        PopBashOptions -x

        cmd+=(--config "$configFile")        
    fi
        
    cmd+=("${extraArgs[@]}")

    ExecuteWithRetry "${cmd[@]}"
}

#---------------------------------------------------------
# Downloads a file, with retries.
#
# Required parameters:
#   $1: The URL
#   $2: The local file to download to.
#
# Optional variables:
#   PAT_VAR: If set, the given environment variable will be will be passed as PAT credential. 
#   This should only be used for Devops endpoints.
#
function RobustDownload
{
    local url="$1"
    local localFile="$2"

    echo "Attempting to download [$url] to [$localFile]..."
    RobustDownloadInternal --output $localFile $url
}

# Downloads an HTTP endpoint as a string, with retries.
#
# Required parameters:
#   $1: The URL
#
# Optional variables:
#   PAT_VAR: If set, the given environment variable will be will be passed as PAT credential. 
#   This should only be used for Devops endpoints.
#
function RobustDownloadString
{
    local url="$1"

    # Must be silent to get only our download output.
    #
    SILENT=true \
        RobustDownloadInternal --silent $url
}

#---------------------------------------------------------
# Some build steps use considerable space under root directories like /opt or /var.
# In devops, everything that does not fall under /mnt is very limited in space, so 
# we want to symlink the location to somewhere unique under /mnt.
#
# Eventually, we may want to stop leaking build files in global folders by making
# all of those configurable, but this requires many individual fixes across the 
# codebase.
#
# Required Parameter:
#  $1 : The directory to create or symlink (when in devops).
#
# Optional Parameters:
#  $2 : Force create - If true, and we are in devops, we will replace the directory if
#       it already exists. This is used to replace directories that we may not be creating,
#       such as Docker's temporary directory.
#
function CreateGlobalFolder
{
    local dir=$1
    local force=${2:-false}

    if [ ! -d "$dir" ] || [ $force == true ]; then
        if [ $IS_DEVOPS == true ]; then

            if [[ "$dir" != "/"* ]]; then
                FailAndExit "Expected dir to be rooted: $dir"
            fi

            # Do not add a separator because $dir is rooted and so it already starts
            # with a slash. The path created here will effectively look like:
            # /mnt/tmp/var/lib/hls, for example.
            #
            local symlinkDest="$AGENT_TEMPDIRECTORY$dir"

            if [ -d "$symlinkDest" ]; then
                FailAndExit "Destination already exists: $symlinkDest"
            fi

            # If it already exists, keep the existing contents by moving them into our 
            # new location first.
            #
            if [ -d "$dir" ]; then
                mkdir -p $(dirname "$symlinkDest")
                mv "$dir" "$symlinkDest"
            fi

            # Must create the symlink's parent folder structure if it does not exist yet.
            #
            mkdir -p $(dirname "$dir")

            # Must create the physical location for our redirected files, in case we have
            # not created it above already.
            #
            mkdir -p "$symlinkDest"

            ln -s "$symlinkDest" "$dir"
            echo "Created symlink: $dir -> $symlinkDest"
        else
            mkdir -p "$dir"
        fi
    fi

    # Make sure image provisoned file are accessible by users.
    #
    chmod -R 777 "$dir"

    # Make sure files are created with gu+rw.
    #
    umask 0000
}

#---------------------------------------------------------
# Function: ExecuteLengthyBlock
#
# Description:
#   Executes the given command, and also logs the start end end times
#   of the command.
#
# Required arguments:
#  $1-   A friendly description for the command
#  $2... The command and arguments.
#
function ExecuteLengthyBlock
{
    local description=$1
    local command=("${@:2}")
    echo "$(date) ######################################################"
    echo "$(date) Starting $description"
    "${command[@]}"
    echo "$(date) Completed $description"
}

#---------------------------------------------------------
# Function: GetLocalDevopsOrg
#
# Description:
#   Detects the Devops org of the currently running pipeline. For all of our SQLPAL usecases,
#   this will simply return "sqlhelsinki" as expected - but these scripts also get used by
#   SQLPAL "consumers" such as SqlSapphire and SSIS orgs, in which case this function will
#   return "SqlSapphire". This information is useful for certain Devops APIs where it is easier
#   to point at your own org with your own SYSTEM_ACCESSTOKEN, than it is to access SqlHelsinki
#   cross-org. If not called from a pipeline, defaults to "sqlhelsinki" too.
#
#    It is expected that System.TeamFoundationServerUri will only be of the form:
#       https://ORG.visualstudio.com or https://dev.azure.com/ORG
#
function GetLocalDevopsOrg
{
    # This environment will have:
    # - System.TeamFoundationServerUri when in Devops
    # - CloudTestVstsUrl when in CloudTest
    # - Fallback to SqlHelsinki.
    #
    local devopsUri="${SYSTEM_TEAMFOUNDATIONSERVERURI:-${CloudTestVstsUrl:-https://sqlhelsinki.visualstudio.com}}"
    local org="$(echo $devopsUri | grep -ioP '(?<=https://).+?(?=.visualstudio.com)')"
    if [ -z "$org" ]; then
        org="$(echo $devopsUri | grep -ioP '(?<=https://dev.azure.com/)\w+')"
        if [ -z "$org" ]; then
            FailAndExit "Unrecognized devops base URI: $devopsUri"
        fi
    fi

    echo $org
}

#--------------------------------------------------------------------------
# Function: AcquireDevopsPAT
#
# Obtain a PAT suitable to access Devops APIs. If interactive mode is used,
# this will defer to the `az` CLI, for browser authentication. Otherwise,
# this function expects to find a SYSTEM_ACCESSTOKEN value.
#
# Required arguments:
#    $1: The *name* of the variable to set with the obtained PAT.
#
# Optional variables:
#    - DEFAULT_PAT_VAR: If set, and if this variable has content, then $pat will be
#      set to this content.
#    - CONFIG_ARTIFACTTOOL_INTERACTIVE_LOGIN: If true, use `az` CLI to dynamically
#      acquire a PAT. This is never used by pipelines, and it is only useful for 
#      local dev builds.
#    - CONFIG_BUILDTOOL_AZ_CLI_USE_DEVICE_CODE: If set, in interactive login mode,
#      add the --use-device-code argument to `az login`.
#    - CONFIG_BUILDTOOL_AZ_CLI_PATH: If set, this is the path to the `az` program.
#      Technically, this can also enable advanced scenarios where the value could be
#      "ssh <my Windows dev box> az". The reason one would want to do that is that 
#      looping through a domain-joined Windows machine instead of using local `az`
#      coming from the Linux machine is that IT security policies severely restrict 
#      the lifetime of login sessions when not in a corporate-managed machine. Leveraging
#      a Windows machine allows having a long-lasting login and not having to constantly
#      re-authenticate. If your value requires quoting or escaping, you should pre-escape
#      it or inner-quote it, such as:
#        export CONFIG_BUILDTOOL_AZ_CLI_PATH=$'\'/mnt/c/Program Files (x86)/az\''
#    - CONFIG_DEVOPS_PAT_FILENAME: If set, the contents of this file is use as the
#      source for the PAT.
#
function AcquireDevopsPAT
{
    local interactive=$(GetNormalizedBool ${CONFIG_ARTIFACTTOOL_INTERACTIVE_LOGIN:-true})

    if [ $IS_LAB_AGENT == true ]; then
        interactive=false
    fi

    local outputVarName="${1:-}"
    if [ -z "$outputVarName" ]; then
        FailAndExit "The variable name (\$1) is required"
    fi

    # Disable debug prints as we handle the PAT.
    # Disable exit on error since we graceully handle errors situations here.
    #
    PushBashOptionSet +xeE

    local patValue=""

    if [ -n "${DEFAULT_PAT_VAR:-}" ] && [ "$(IsVariableDefined $DEFAULT_PAT_VAR)" == true ]; then
        # If the caller has provided an override variable, use that directly.
        #
        CopySecretVariable $DEFAULT_PAT_VAR patValue
        echo "AcquireDevopsPAT Read \$$outputVarName from variable $DEFAULT_PAT_VAR"
    elif [ -n "${CONFIG_DEVOPS_PAT_FILENAME:-}" ] && [ -e "${CONFIG_DEVOPS_PAT_FILENAME}" ]; then
        # Use PAT from file.
        #
        patValue=$(cat $CONFIG_DEVOPS_PAT_FILENAME)
        echo "AcquireDevopsPAT Read \$$outputVarName from file $CONFIG_DEVOPS_PAT_FILENAME"
    elif [ $interactive == true ]; then
        local azCliProgram="${CONFIG_BUILDTOOL_AZ_CLI_PATH:-az}"
        local getPatCommand
        
        # This is the least complicated way I found to make complicated azCliProgram strings
        # (inner escaping, inner quotes) work.
        #
        eval "getPatCommand=($azCliProgram account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798)"

        # Must be in two statements, because the "local" directive squashes $?.
        #
        local patJson 
        patJson=$("${getPatCommand[@]}" 2>&1)

        if [ $? != 0 ]; then
            patJson=
            local versionTest
            versionTest=$($azCliProgram --version 2>&1)
            if [ $? == 0 ]; then
                WriteWarning "Must attempt interactive login to access Devops"

                local azLoginArgs=""

                if [ $(GetNormalizedBool ${CONFIG_BUILDTOOL_AZ_CLI_USE_DEVICE_CODE:-}) == true ]; then
                    azLoginArgs+="--use-device-code "
                else
                    echo "(If this fails, retry with CONFIG_BUILDTOOL_AZ_CLI_USE_DEVICE_CODE=1)"
                fi

                # az-login's stdout must go to our stderr, because our stdout is what we return from this function.
                #
                $azCliProgram login $azLoginArgs -o none 1>&2

                if [ $? == 0 ]; then
                    patJson=$("${getPatCommand[@]}" 2>&1)

                    if [ $? != 0 ]; then
                        FailAndExit "Command '$getPatCommand' failed after two attempts: $patJson"
                    fi
                fi

            else
                FailAndExit "Command '$azCliProgram --version' failed: $versionTest"
            fi
        fi

        if [ -n "$patJson" ]; then
            patValue=$(jq -r .accessToken <<< $patJson)
        fi
    else
        patValue="${SYSTEM_ACCESSTOKEN:-}"
        echo "AcquireDevopsPAT Read \$$outputVarName from variable SYSTEM_ACCESSTOKEN"
    fi

    if [ -z "${patValue:-}" ]; then
        FailAndExit "Could not acquire a PAT, and neither SYSTEM_ACCESSTOKEN / CONFIG_ARTIFACTTOOL_INTERACTIVE_LOGIN / CONFIG_DEVOPS_PAT_FILENAME are set."
    fi

    # Export the value to our caller's variable.
    #
    printf -v $outputVarName '%s' "$patValue"

    PopBashOptions
}

#---------------------------------------------------------
# Function: IsVariableDefined
#
# Description:
#   Returns "true" if the given variable is defined in the current
#   scope. This function ensures that the variable's value does not
#   get printed to debug output, to allow usage with secret variables.
#
function IsVariableDefined
{
    # The code of this function is uninteresting to have in logs, only 
    # the function call is enough.
    #
    PushBashOptionSet +x

    local varName="${1:-}"

    local exists=false

    if [ -n "$varName" ]; then
        # Disable debug logging, disable undefined variables warning.
        #
        PushBashOptionSet +xu

        if [ -n "${!varName}" ]; then
            exists=true
        fi

        PopBashOptions
    fi

    PopBashOptions

    echo $exists
}

#---------------------------------------------------------
# Function: EnsureIsVariableDefined
#
# Description:
#   Fails the program if the given variable is not defined.
#
function EnsureIsVariableDefined
{
    # The code of this function is uninteresting to have in logs, only 
    # the function call is enough.
    #
    PushBashOptionSet +x

    local varName="${1:-}"

    if [ -z "$varName" ]; then
        FailAndExit "The variable name (\$1) is required"
    fi

    if [ "$(IsVariableDefined $varName)" == false ]; then
        FailAndExit "The variable $varName is not set"
    fi

    PopBashOptions
}

#----------------------------------------------------------------------------
# Function DumpDiskUsage
#
# Description:
#   Displays the disk usage on the current system. This includes `df` to show
#   the mounts as well as the physical disk usage, as well as `du` to show
#   all folders of 1GB or more. Both can be useful perspectives to understand
#   disk issues.
# 
function DumpDiskUsage
{
    echo "Dump of disk usage:"
    echo "----------------------------------------------------------------"
    df -h
    echo

    echo "Dump of directories over 1GB:"
    echo "----------------------------------------------------------------"
    du -h / 2>/dev/null | grep '^[0-9\.]\+G'
}

#----------------------------------------------------------------------------
# Function DumpMachineEnvironment
#
# Description:
#   Displays the important pieces that describe the execution environment
#   on this machine, such as the environment variables, and profile files.
#
#   Optional variables:
#      DUMP_SETUP_INFO: If set, print the initial status of this machine,
#      such as the 1ESImage logs (if applicable) and important boot files.
#      Default: true
# 
function DumpMachineEnvironment
{
    PushBashOptionSet +eEx

    local DUMP_SETUP_INFO="$(GetNormalizedBool ${DUMP_SETUP_INFO:-true})"

    if [ $DUMP_SETUP_INFO == true ]; then
        echo "Dump of /etc/skel/"
        echo "----------------------------------------------------------------"
        find /etc/skel -type f -exec bash -c "\
            echo ============================ && \
            echo {} && \
            echo ============================= && \
            cat {}" \;

        echo "Dump of /etc/environment"
        echo "----------------------------------------------------------------"
        cat /etc/environment
        echo

        echo "Dump of /etc/fstab"
        echo "----------------------------------------------------------------"
        cat /etc/fstab
        echo

        echo "Dump of ldconfig:"
        echo "----------------------------------------------------------------"
        ldconfig -p
        echo

        # This file is important, it is what will be executed prior to any "bash"
        # task in Devops pipelines. Devops executes bash in "non-interactive, non-login"
        # mode, meaning the ".bashrc", ".profile" files, and everything similar, do NOT
        # get loaded. Only the file indicated by the BASH_ENV variable matters.
        #
        if [ -n "${BASH_ENV:-}" ]; then
            echo "Dump of BASH_ENV file ($BASH_ENV)"
            echo "----------------------------------------------------------------"
            cat $BASH_ENV
        else
            echo "** BASH_ENV is not set"
        fi

        # If we are executing on a custom 1ESImage (which all of our agents are, both in
        # builds and tests), this environment variable will be set to a file containing
        # the logs for the build of our underlying image.
        #
        # This function is also called when building the actual 1ESImages, in which case
        # we must not attempt to dump our own log because this would be recursive.
        #
        if [ -z "${BOOTSTRAPPING_STAGE:-}" ]; then
            echo "VM Image provisioning log:"
            echo "----------------------------------------------------------------"
            if [ -n "${SQLPAL_1ESIMG_PROVISIONING_LOG:-}" ]; then
                # In Devops, keep the main logs lean by publishing the VM provision
                # log as its own file within the "All Logs" zip. In other environments,
                # (CloudTest), just `cat` the file.
                #
                if [ "$IS_DEVOPS" == true ]; then
                    UPLOAD_AS_FILE=true \
                    UploadDevopsBuildLog "$SQLPAL_1ESIMG_PROVISIONING_LOG"
                    echo "Uploaded $SQLPAL_1ESIMG_PROVISIONING_LOG to this pipeline's logs."
                else
                    cat "$SQLPAL_1ESIMG_PROVISIONING_LOG"
                fi
            else
                echo "** SQLPAL_1ESIMG_PROVISIONING_LOG is not set"
                echo "(This is expected for local dev and containers, but not expected for Devops or CloudTest)"
            fi
        fi
    fi

    DumpDiskUsage
    echo

    echo "Dump of environment variables:"
    echo "----------------------------------------------------------------"
    env

    PopBashOptions
}

# This script can get 'source'd multiple times in a single build step. To reduce the noise,
# disable -x mode. There is not much of interest to log the initialization of global variables 
# in this file. To ensure that we do not regress, enforce "-u" for the scope of this file.
#
PushBashOptionSet +x -eEu

# If we are in Devops, this variable can be set at queue time by selecting the 
# "Enable system diagnostics" checkbox. You can also manually set this variable
# for local dev builds to automatically get -x.
#
SYSTEM_DEBUG=${SYSTEM_DEBUG:-false}
export SYSTEM_DEBUG=$(GetNormalizedBool $SYSTEM_DEBUG)

# Used by PushBashOptionSet/PopBashOptions. Check for empty because we do not want to reset
# this variable in case this scripts gets sourced twice.
#
if [ -z "${BashOptionsStack:-}" ]; then
    BashOptionsStack=()
fi

if [ -z "${ExitTraps:-}" ]; then
    ExitTraps=()
fi


# Always initialize these variables, including the version numbers, so that they
# are always safe to use even in bash strict mode.
#
IS_DEVOPS=false
IS_CLOUDTEST=false
IS_LAB_AGENT=false
IS_UBUNTU=false
IS_RHEL=false
IS_SLES=false
IS_MARINER=false
IS_WSL=false
UBUNTU_VERSION=0
UBUNTU_VERSION_MAJOR=0
RHEL_VERSION=0
RHEL_VERSION_MAJOR=0
SLES_VERSION=0
SLES_VERSION_MAJOR=0
MARINER_VERSION=0
MARINER_VERSION_MAJOR=0

# Set to true if scripts can use `sudo ...` without having to prompt the 
# user. In most of our scripts, we prefer warning the user clearly about
# having to sudo (in the very few places where we need it), rather than
# attempting sudo and having it ask for password.
#
CAN_SILENT_SUDO=false
IS_ROOT=false

if [ "$(HasProgramInPath sudo)" != "true" ]; then
    # This script is used on blank cloud VMs/containers that do do not even have 
    # the most basic packages installed yet, which can mean not even having the
    # sudo program itself. If sudo is not there, assume we are root.
    #
    IS_ROOT=true
else
    if [ $(id -u) == "0" ]; then
        IS_ROOT=true
    fi

    sudo -n id >/dev/null 2>&1 && CAN_SILENT_SUDO=true
fi

if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
    IS_WSL=true
fi

# Convert the built-in TF_BUILD=True (uppercase T) that comes from the environment into a 
# more obvious and convenient IS_DEVOPS=true to help readability. ' :- ' is used across this
# file to support 'set -u' mode for these variables that may or may not exist. 'IS_LAB_AGENT'
# means "IS_DEVOPS || IS_CLOUDTEST" since we often treat the two identically.
#
if [ "${TF_BUILD:-}" == "True" ]; then
    IS_DEVOPS=true
    IS_LAB_AGENT=true
elif [ -n "${TestHarness:-}" ]; then
    IS_CLOUDTEST=true
    IS_LAB_AGENT=true
fi

# This script is always `source`d - we cannot use $0.
#
export SQLPAL_COMMON_BUILD_UTILITIES_DIR=$(dirname $(realpath $BASH_SOURCE))

# To simplify manual usages that may not be executing within Devops, always define
# AGENT_TEMPDIRECTORY.
#
export AGENT_TEMPDIRECTORY=${AGENT_TEMPDIRECTORY:-/tmp}

# If we are running under devops or cloudtest, some agent configurations have extremely small 
# storage for /tmp. Override the standard $TMPDIR to point to the harness-provided locations, 
# which will be on our SKU's larger disk. This is used by `mktemp` and similar utilities.
#
if [ $IS_LAB_AGENT == true ]; then
    if [ $IS_DEVOPS == true ]; then
        export TMPDIR=${TMPDIR:-$AGENT_TEMPDIRECTORY/SqlpalTemp}
    else
        export TMPDIR=${TMPDIR:-$WorkingDirectory/SqlpalTemp}
    fi

    if [ ! -d "$TMPDIR" ]; then
        mkdir -p "$TMPDIR"
        chmod -R 1777 "$TMPDIR"
    fi
fi

#----------------------------------------------------------------------------
# Returns the value of a field from the /etc/os-release file, such as 'VERSION'
#
function GetEtcOsReleaseField
{
    local key=$1
    grep -oP "^$key=\"?\K[^\"]*(?=\"?)" /etc/os-release
}

#----------------------------------------------------------------------------
# Function: VersionLessThanOrEqual
#
# Description:
#    Returns true if $1 is less or equal to $2, interpreted as dotted version strings.
#    That is, 
#       VersionLessThan 3.10    3.2    -> false
#       VersionLessThan 3.10.1  3.10.3 -> true
#
function VersionLessThanOrEqual() 
{
    if [ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]; then
		true
	else
		false
	fi
}

#----------------------------------------------------------------------------
# Function: VersionLessThan
#
# Description:
#    Returns true if $1 is less than $2, interpreted as dotted version strings.
#    That is, 
#       VersionLessThan 3.10    3.2    -> false
#       VersionLessThan 3.10.1  3.10.3 -> true
#
function VersionLessThan
{
	if [ "$1" == "$2" ]; then
		false
	else
		VersionLessThanOrEqual $1 $2
	fi
}

#----------------------------------------------------------------------------
# Function: IsDockerContainer
#
# Description:
#    Returns true if the current script is running is a container via Docker.
#
function IsDockerContainer
{
    test -f /.dockerenv
}

#----------------------------------------------------------------------------
# Function: IsPodmanContainer
#
# Description:
#    Returns true if the current script is running in a container via Podman.
#
function IsPodmanContainer
{
    test -f /run/.containerenv
}

#----------------------------------------------------------------------------
# Function: IsBuildKitContainer
#
# Description:
#    Returns true if the current script is running in a container via buildkit
#    (non-legacy docker build).
#
function IsBuildKitContainer
{
    grep buildkit /proc/self/cgroup >& /dev/null
}

#----------------------------------------------------------------------------
# Function: IsContainer
#
# Description:
#    Returns true if the current script is running in a container.
#
function IsContainer
{
    IsDockerContainer || IsPodmanContainer || IsBuildKitContainer
}

#----------------------------------------------------------------------------
# Function: AddExitCallback
#
# Description:
#   Bash only maintains a single `trap` per signal, but complex scripts
#   like run-tests-common may want multiple things to happen on exit.
#   Code should not manually use `trap [...] EXIT` and should use this
#   function instead, which traps once for all.
#
# Required parameters:
#  $1+ - The command to execute. It may include arguments.
#
function AddExitCallback()
{
    if [ ${#ExitTraps[@]} == 0 ]; then
        trap ExecuteExitCallbacks EXIT
    fi

    ExitTraps+=("$*")
}

function ExecuteExitCallbacks()
{
    for value in "${ExitTraps[@]}"
    do
        $value
    done
}

# Detect the distribution name.
#
export SYSTEM_ARCH=$(uname -m)
export SYSTEM_KERNEL=$(uname -r)

# Skip distribution detection if not running on linux. This is useful when trying
# to source from mingw/msys bash to debug functionnality, for example.
#
if [ "$OSTYPE" != "linux-gnu" ]; then
    echo "Skipping distribution detection skipped on OS $OSTYPE"
else
    if [ -f "/etc/os-release" ]; then
        export DISTRONAME="$(GetEtcOsReleaseField NAME) $(GetEtcOsReleaseField VERSION)"
    else
        FailAndExit "Unsupported distribution: does not have /etc/os-release"
    fi

    if [[ "$(GetEtcOsReleaseField ID)" == "debian" || "$(GetEtcOsReleaseField ID_LIKE)" == "debian" ]]; then
        # Disable interactive prompts for automated install.
        #
        export DEBIAN_FRONTEND=noninteractive
    fi

    case $(GetEtcOsReleaseField ID) in
        ubuntu)
            export IS_UBUNTU=true
            export UBUNTU_VERSION=$(GetEtcOsReleaseField VERSION_ID)
            export UBUNTU_VERSION_MAJOR=$(cut -d "." -f1 <<< $UBUNTU_VERSION)
            export UBUNTU_VERSION_MINOR=$(cut -d "." -f2 <<< $UBUNTU_VERSION)
            export DISTRO_SHORT_NAME="ubuntu$UBUNTU_VERSION_MAJOR$UBUNTU_VERSION_MINOR"
            ;;

        rhel)
            export IS_RHEL=true
            export RHEL_VERSION=$(GetEtcOsReleaseField VERSION_ID)
            export RHEL_VERSION_MAJOR=$(cut -d "." -f1 <<< $RHEL_VERSION)
            export DISTRO_SHORT_NAME="rhel$RHEL_VERSION_MAJOR"
            ;;
        
        sles)
            export IS_SLES=true
            export SLES_VERSION=$(GetEtcOsReleaseField VERSION_ID)
            export SLES_VERSION_MAJOR=$(cut -d "." -f1 <<< $SLES_VERSION)
            export DISTRO_SHORT_NAME="sles$SLES_VERSION_MAJOR"
            ;;

        mariner)
            export IS_MARINER=true
            export MARINER_VERSION=$(GetEtcOsReleaseField VERSION_ID)
            export MARINER_VERSION_MAJOR=$(cut -d "." -f1 <<< $MARINER_VERSION)
            export DISTRO_SHORT_NAME="mariner$MARINER_VERSION_MAJOR"
            ;;

        *)
            FailAndExit "Unsupported distribution $(GetEtcOsReleaseField ID)"
            ;;
    esac

    # When onboarding a new environment, it can be useful to try to hack away
    # with another platform's artifacts. Of course, this should not be used
    # as a long term solution - only for local tests. This variable is also 
    # considered by buildtool.
    #
    if [ -n "${CONFIG_PLATFORM_OVERRIDE:-}" ]; then
        export DISTRO_SHORT_NAME="${CONFIG_PLATFORM_OVERRIDE}"
    fi

    export DISTRO_PKG_NAME=$(DistroNameToPackagingString "$DISTRONAME")

    if [ "$SYSTEM_ARCH" == "x86_64" ]; then
        SYSTEM_ARCH_FRIENDLY_NAME=x64
    elif [ "$SYSTEM_ARCH" == "aarch64" ]; then
        SYSTEM_ARCH_FRIENDLY_NAME=arm64
    else
        SYSTEM_ARCH_FRIENDLY_NAME="$SYSTEM_ARCH"
    fi

    export DISTRO_CODENAME="$(GetEtcOsReleaseField VERSION_CODENAME || true)"

    export CURRENT_PIPELINE_DEVOPS_ORG=$(GetLocalDevopsOrg)

    # This will create a value such as "-x64-ubuntu2004-123456".
    #
    export BUILD_PACKAGE_SUFFIX="-$SYSTEM_ARCH_FRIENDLY_NAME-$DISTRO_SHORT_NAME"
fi

# Undo the "set -eu +x" done earlier in this file.
#
PopBashOptions
