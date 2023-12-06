#!/bin/sh
#
# Copyright (c) 2023, Jesús Daniel Colmenares Oviedo <DtxdF@disroot.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Reproduce version.
VERSION="%%VERSION%%"

# Used by sig_handler.
LAST_EXIT_STATUS=0
# Used by sig_handler_remove_last_jail.
LAST_JAIL=
# Used by sig_handler_terminate_last_pid.
LAST_PIDS=
# Used by sig_handler_remove_lock.
REMOVE_LOCK="NO"

# Colors
COLOR_DEFAULT="\033[39;49m"
COLOR_RED="\033[0;31m"
COLOR_LIGHT_YELLOW="\033[0;93m"
COLOR_LIGHT_BLUE="\033[0;94m"
COLOR_GRAY="\033[0;90m"

# see sysexits(3)
EX_OK=0
EX_USAGE=64
EX_DATAERR=65
EX_NOINPUT=66
EX_NOUSER=67
EX_NOHOST=68
EX_UNAVAILABLE=69
EX_SOFTWARE=70
EX_OSERR=71
EX_OSFILE=72
EX_CANTCREAT=73
EX_IOERR=74
EX_TEMPFAIL=75
EX_PROTOCOL=76
EX_NOPERM=77
EX_CONFIG=78

# Home directory.
UID=`id -u`
HOMEDIR=`getent passwd ${UID} | cut -d: -f6` || exit $?

if [ ! -d "${HOMEDIR}" ]; then
    err "Cannot find home directory '${HOMEDIR}'"
fi

# Configuration file.
CONFIG="${HOMEDIR}/.config/appjail-reproduce/config.conf"

# Reproduce directory prefix.
REPRODUCEDIR="${HOMEDIR}/.reproduce"

# Signals.
IGNORED_SIGNALS="SIGALRM SIGVTALRM SIGPROF SIGUSR1 SIGUSR2"
HANDLER_SIGNALS="SIGHUP SIGINT SIGQUIT SIGTERM SIGXCPU SIGXFSZ"

# Defaults.
PROJECTSDIR="${REPRODUCEDIR}/projects"
LOGSDIR="${REPRODUCEDIR}/logs"
RUNDIR="${REPRODUCEDIR}/run"
JAIL_PREFIX="reproduce_"
BEFORE_MAKEJAILS=
AFTER_MAKEJAILS=
MIRRORS=
DEBUG="NO"
COMPRESS_ALGO="xz"

main()
{
    local _o
    local opt_build=0
    local opt_check_config=0
    local errlevel

    set -T

    trap '' ${IGNORED_SIGNALS}
    trap 'sig_handler; exit 70' ${HANDLER_SIGNALS}
    trap 'LAST_EXIT_STATUS=$?; sig_handler; exit ${LAST_EXIT_STATUS}' EXIT

    if [ $# -eq 0 ]; then
        usage
        exit ${EX_USAGE}
    fi

    if ! which -s appjail; then
        err "Cannot find appjail, please install it using 'pkg-install(8)':"
        err
        err "# pkg install -y appjail # or"
        err "# pkg install -y appjail-devel"
        exit ${EX_UNAVAILABLE}
    fi

    if ! which -s appjail-config; then
        err "Cannot find appjail-config!"
        exit ${EX_UNAVAILABLE}
    fi

    while getopts ":bdhvA:B:C:c:j:l:m:p:r:" _o; do
        case "${_o}" in
            A|B|C|c|j|l|m|p|r)
                if [ -z "${OPTARG}" ]; then
                    usage
                    exit ${EX_USAGE}
                fi
                ;;
        esac

        case "${_o}" in
            b)
                opt_build=1
                ;;
            d)
                DEBUG="YES"
                ;;
            h)
                help
                exit ${EX_USAGE}
                ;;
            v)
                version
                exit 0
                ;;
            A)
                AFTER_MAKEJAILS="${OPTARG}"
                ;;
            B)
                BEFORE_MAKEJAILS="${OPTARG}"
                ;;
            C)
                COMPRESS_ALGO="${OPTARG}"
                ;;
            c)
                CONFIG="${OPTARG}"
                opt_check_config=1
                ;;
            j)
                JAIL_PREFIX="${OPTARG}"
                ;;
            l)
                LOGSDIR="${OPTARG}"
                ;;
            m)
                MIRRORS="${OPTARG}"
                ;;
            p)
                PROJECTSDIR="${OPTARG}"
                ;;
            r)
                RUNDIR="${OPTARG}"
                ;;
            *)
                usage
                exit ${EX_USAGE}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ ${opt_build} -eq 0 ]; then
        usage
        exit ${EX_USAGE}
    fi

    if [ -f "${CONFIG}" ]; then
        if [ ${opt_check_config} -eq 1 ]; then
            err "Cannot find configuration file '${CONFIG}'"
            exit ${errlevel}
        fi

        debug "Loading configuration file '${CONFIG}'"

        . "${CONFIG}"

        errlevel=$?

        if [ ${errlevel} -ne 0 ]; then
            err "Error loading '${CONFIG}'"
            exit ${errlevel}
        fi
    fi

    if [ ! -d "${PROJECTSDIR}" ]; then
        debug "Creating projects directory '${PROJECTSDIR}'"
        safe_exc mkdir -p -- "${PROJECTSDIR}" || exit $?
    fi

    if [ ! -d "${RUNDIR}" ]; then
        debug "Creating run directory '${RUNDIR}'"
        safe_exc mkdir -p -- "${RUNDIR}" || exit $?
    fi

    local total

    if [ $# -gt 0 ]; then
        PROJECTS="$@"

        if [ -z "${PROJECTS}" ]; then
            usage
            exit ${EX_USAGE}
        fi

        debug "Projects defined from positional arguments: ${PROJECTS}"

        total="$#"
    else
        PROJECTS=`ls -- "${PROJECTSDIR}"` || exit $?

        if [ -z "${PROJECTS}" ]; then
            err "There are no projects to build."
            exit ${EX_NOINPUT}
        fi

        debug "Projects found in projects directory:" ${PROJECTS}

        total=`printf "%s\n" "${PROJECTS}" | wc -l | tr -d ' '`
    fi

    local total_errors=0 total_hits=0 index=1 project

    if [ -f "${RUNDIR}/lock" ]; then
        err "appjail-reproduce is locked. Use 'rm -f \"${RUNDIR}/lock\"' to remove the lock file."
        exit ${Ex_NOPERM}
    fi

    debug "Locking ..."

    REMOVE_LOCK="YES"

    safe_exc touch -- "${RUNDIR}/lock" || exit $?

    local makejail after_makejails_args=

    for makejail in ${AFTER_MAKEJAILS}; do
        if [ ! -f "${makejail}" ]; then
            err "'${makejail}' Makejail (type:after) not found."
            exit ${EX_NOINPUT}
        fi

        debug "Processing Makejail (type:after): ${makejail}"

        makejail=`safe_exc realpath -- "${makejail}"` || exit $?

        if [ -z "${after_makejails_args}" ]; then
            after_makejails_args="-a \"${makejail}\""
        else
            after_makejails_args="${after_makejails_args} -a \"${makejail}\""
        fi
    done

    local before_makejails_args=

    for makejail in ${BEFORE_MAKEJAILS}; do
        if [ ! -f "${makejail}" ]; then
            err "'${makejail}' Makejail (type:before) not found."
            exit ${EX_NOINPUT}
        fi

        debug "Processing Makejail (type:before): ${makejail}"

        makejail=`safe_exc realpath -- "${makejail}"` || exit $?

        if [ -z "${after_makejails_args}" ]; then
            before_makejails_args="-B \"${makejail}\""
        else
            before_makejails_args="${before_makejails_args} -B \"${makejail}\""
        fi
    done

    local init_build_time=`date +"%s"`

    info "Started at `date`"

    for project in ${PROJECTS}; do
        local _project

        _project=`basename -- "${project}" 2>&1`

        if [ $? -ne 0 ]; then
            err "${_project}"
            total_errors=$((total_errors+1))
            continue
        fi

        if [ "${project}" != "${_project}" ]; then
            err "Invalid project name '${project}'"
            total_errors=$((total_errors+1))
            continue
        fi

        project="${_project}"

        local tags2build
        
        tags2build=`getvalue : "${project}"`
        project=`getkey : "${project}"`

        local arch2build

        arch2build=`getvalue % "${project}"`
        project=`getkey % "${project}"`

        if [ -z "${project}" ]; then
            err "Project number '${index}' has an empty name."
            total_errors=$((total_errors+1))
            continue
        fi

        if [ "${total}" -gt 1 ]; then
            info "[${project}] (${index}/${total}):"
        else
            info "[${project}]:"
        fi

        index=$((index+1))

        local projectdir="${PROJECTSDIR}/${project}"
        
        if [ -d "${projectdir}" ]; then
            export REPRODUCE_PROJECT="${project}"
            export REPRODUCE_PROJECTDIR="${projectdir}"
        else
            err "Project not found."
            total_errors=$((total_errors+1))
            continue
        fi

        local makejail="${projectdir}/Makejail"

        if [ ! -f "${makejail}" ]; then
            err "Makejail not found."
            total_errors=$((total_errors+1))
            continue
        fi

        projectdir=`realpath -- "${projectdir}" 2>&1`

        if [ $? -ne 0 ]; then
            err "${projectdir}"
            total_errors=$((total_errors+1))
            continue
        fi

        local rundir="${RUNDIR}/${project}"

        if [ ! -d "${rundir}" ]; then
            debug "Creating run directory '${rundir}'"
            if ! safe_exc mkdir -p -- "${rundir}"; then
                total_errors=$((total_errors+1))
                continue
            fi
        fi

        local logdir="${LOGSDIR}/${project}"

        if [ ! -d "${logdir}" ]; then
            debug "Creating log directory '${logdir}'"
            if ! safe_exc mkdir -p -- "${logdir}"; then
                total_errors=$((total_errors+1))
                continue
            fi
        fi

        local config="${projectdir}/reproduce.conf"

        local reproduce_jail_name=
        local reproduce_name=
        local reproduce_version=
        local reproduce_tags=
        local reproduce_arch=
        local reproduce_release=
        local reproduce_ignore_osarch=
        local reproduce_ignore_osversion=
        local reproduce_ignore_release=
        local reproduce_args=
        local reproduce_remove_rc_vars=
        local reproduce_mirrors=

        if [ -f "${rundir}/jail_name" ]; then
            reproduce_jail_name=`head -1 -- "${rundir}/jail_name"`

            if [ $? -ne 0 ]; then
                err "The jail name cannot be obtained."
                total_errors=$((total_errors+1))
                continue
            fi
        fi

        if [ -z "${reproduce_jail_name}" ]; then
            reproduce_jail_name="${JAIL_PREFIX}`uuidgen -r`"

            safe_exc printf "%s" "${reproduce_jail_name}" > "${rundir}/jail_name"
        fi

        export REPRODUCE_JAIL_NAME="${reproduce_jail_name}"

        debug "Jail name for ${project} is ${reproduce_jail_name}"

        if [ -f "${config}" ]; then
            local _key _value _err=0

            for _key in name release ignore_external ignore_osarch ignore_osversion ignore_release; do
                _value=`getconf "${config}" ${_key}`

                if [ $? -ne 0 ]; then
                    _err=1
                    break
                fi

                setvar "reproduce_${_key}" "${_value}"
            done

            if [ ${_err} -eq 1 ]; then
                total_errors=$((total_errors+1))
                continue
            fi

            for _key in tags arch args remove_rc_vars mirrors; do
                _value=`getallconf "${config}" ${_key}`

                if [ $? -ne 0 ]; then
                    _err=1
                    break
                fi

                setvar "reproduce_${_key}" "${_value}"
            done

            if [ ${_err} -eq 1 ]; then
                total_errors=$((total_errors+1))
                continue
            fi
        fi

        reproduce_name="${reproduce_name:-${project}}"
        reproduce_version=`freebsd-version | grep -Eo '[0-9]+\.[0-9]+-[a-zA-Z0-9]+'`
        reproduce_tags="${reproduce_tags:-latest/${reproduce_version}}"
        reproduce_arch="${reproduce_arch:-`uname -p`}"
        reproduce_ignore_external="${reproduce_ignore_external:-NO}"
        reproduce_ignore_osarch="${reproduce_ignore_osarch:-NO}"
        reproduce_ignore_osversion="${reproduce_ignore_osversion:-NO}"
        reproduce_ignore_release="${reproduce_ignore_release:-NO}"

        reproduce_release="${reproduce_release:-default}"
        export REPRODUCE_OSRELEASE="${reproduce_release}"

        if trace_exc appjail image get -- "${reproduce_name}" name > /dev/null 2>&1; then
            debug "Removing image '${reproduce_name}'"

            if ! trace_exc appjail image remove -- "${reproduce_name}"; then
                err "Error removing image '${reproduce_name}'"
                total_errors=$((total_errors+1))
                continue
            fi
        fi
        
        local arch

        local logfile="${logdir}/`date +"%Y-%m-%d_%Hh%Mm%Ss"`.log"

        info "Logs: ${logfile}"

        for arch in ${reproduce_arch}; do
            errlevel=0

            if [ -n "${arch2build}" ]; then
                if ! checkmatch , "${arch}" "${arch2build}"; then
                    debug "Ignoring arch '${arch}'"
                    continue
                fi
            fi

            export REPRODUCE_OSARCH="${arch}"

            local tag

            for tag in ${reproduce_tags}; do
                version=`getvalue / "${tag}"`

                local _version=`basename -- "${version}"`

                if [ "${version}" != "${_version}" ]; then
                    err "Invalid OS version '${version}'"
                    total_errors=$((total_errors+1))
                    continue
                fi

                export REPRODUCE_OSVERSION="${version}"

                local _tag=`getkey / "${tag}"`

                if [ -z "${_tag}" ]; then
                    err "'${_tag}' incorrect format: tag/osversion"
                    total_errors=$((total_errors+1))
                    continue
                fi

                tag="${_tag}"

                _tag=`basename -- "${tag}"`

                if [ "${tag}" != "${_tag}" ]; then
                    err "Invalid tag '${tag}'"
                    total_errors=$((total_errors+1))
                    continue
                fi

                if [ -n "${tags2build}" ]; then
                    if ! checkmatch , "${tag}" "${tags2build}"; then
                        debug "Ignoring tag '${tag}'"
                        continue
                    fi
                fi

                export REPRODUCE_TAG="${tag}"

                info "> [${project}] (osarch:${arch}, osversion:${version}, tag:${tag}):"

                local _err=0
                local arg args=

                for arg in ${reproduce_args}; do
                    local value=

                    checkparam "${config}" "${tag}.args.${arg}"

                    errlevel=$?

                    if [ ${errlevel} -eq 0 ]; then
                        value=`getconf "${config}" "${tag}.args.${arg}"`
                    elif [ ${errlevel} -eq 1 ]; then
                        continue
                    else
                        _err=1
                        break
                    fi

                    if [ -z "${args}" ]; then
                        args="\"--${arg}\" \"${value}\""
                    else
                        args="${args} \"--${arg}\" \"${value}\""
                    fi
                done

                if [ ${_err} -eq 1 ]; then
                    total_errors=$((total_errors+1))
                    continue
                fi
                
                info "Executing Makejail: jail:${reproduce_jail_name}, release:${reproduce_release}, args:${args}" 2>&1 | tee -a "${logfile}" >&2

                stop_and_destroy_jail "${reproduce_jail_name}"

                local osversion_arg=

                if ! checkyesno "ignore_osversion" "${reproduce_ignore_osversion}"; then
                    osversion_arg="-o osversion=\"${version}\""
                fi

                local osarch_arg=

                if ! checkyesno "ignore_osarch" "${reproduce_ignore_osarch}"; then
                    osarch_arg="-o osarch=\"${arch}\""
                fi

                local release_arg=

                if ! checkyesno "ignore_release" "${reproduce_ignore_release}"; then
                    release_arg="-o release=\"${reproduce_release}\""
                fi

                local external_makejails_args=

                if ! checkyesno "ignore_external" "${reproduce_ignore_external}"; then
                    external_makejails_args="${before_makejails_args} ${after_makejails_args}"
                fi

                LAST_JAIL="${reproduce_jail_name}"

                local init_makejail_time=`date +"%s"`

                eval trace_exc appjail makejail \
                    -j "${reproduce_jail_name}" \
                    -f "${makejail}" \
                    ${osversion_arg} \
                    ${osarch_arg} \
                    ${release_arg} \
                    ${external_makejails_args} \
                        -- ${args} >> "${logfile}" 2>&1

                errlevel=$?

                info "Execution time: `calc_build_time ${init_makejail_time}`" 2>&1 | tee -a "${logfile}" >&2

                if [ ${errlevel} -ne 0 ]; then
                    err "Makejail exits with a non-zero exit status (${errlevel})." 2>&1 | tee -a "${logfile}" >&2
                    total_errors=$((total_errors+1))
                    stop_and_destroy_jail "${reproduce_jail_name}"
                    continue
                fi

                stop_jail "${reproduce_jail_name}"

                if [ -f "${projectdir}/toremove.lst" ]; then
                    local file

                    while IFS= read -r file; do
                        info "Removing: rm ${file}" 2>&1 | tee -a "${logfile}" >&2

                        if ! trace_exc appjail cmd local "${reproduce_jail_name}" sh -c "rm ${file}"; then
                            warn "Error removing ${file}" 2>&1 | tee -a "${logfile}" >&2
                        fi
                    done < "${projectdir}/toremove.lst"
                fi

                local rc_var

                for rc_var in ${remove_rc_vars}; do
                    info "Removing rc variable: ${rc_var}" 2>&1 | tee -a "${logfile}" >&2

                    trace_exc appjail cmd local "${reproduce_jail_name}" sysrc -f etc/rc.conf -ix -- "${rc_var}" 2>&1 | tee -a "${logfile}" >&2
                done

                local hook="${projectdir}/hook.sh"

                if [ -f "${hook}" ]; then
                    if [ ! -x "${hook}" ]; then
                        warn "'${hook}' hook does not have the execution bit permission set."
                        total_errors=$((total_errors+1))
                        continue
                    fi

                    info "Executing hook" 2>&1 | tee -a "${logfile}" >&2

                    trace_exc appjail cmd jaildir "${hook}" >> "${logfile}" 2>&1

                    errlevel=$?

                    if [ ${errlevel} -ne 0 ]; then
                        err "Hook exits with a non-zero exit status (${errlevel})." 2>&1 | tee -a "${logfile}" >&2
                    fi
                fi

                info "Exporting ${reproduce_name}" 2>&1 | tee -a "${logfile}" >&2

                local init_export_time=`date +"%s"`

                if trace_exc appjail image export -f -c "${COMPRESS_ALGO}" -t "${tag}" -n "${reproduce_name}" -- "${reproduce_jail_name}" >> "${logfile}" 2>&1; then
                    total_hits=$((total_hits+1))
                else
                    err "Error exporting '${reproduce_name}'"
                    total_errors=$((total_errors+1))
                fi

                info "Export time: `calc_build_time ${init_export_time}`" 2>&1 | tee -a "${logfile}" >&2

                stop_and_destroy_jail "${reproduce_jail_name}"

                local mirror mirrors=

                for mirror in ${MIRRORS}; do
                    if [ -z "${mirrors}" ]; then
                        mirrors="${mirror}/${reproduce_name}"
                    else
                        mirrors="${mirrors} ${mirror}/${reproduce_name}"
                    fi
                done

                for mirror in ${mirrors} ${reproduce_mirrors}; do
                    mirror="${mirror}/${tag}-${arch}-image.appjail"

                    debug "Adding mirror (tag:${tag}, arch:${arch}): ${mirror}"

                    if ! trace_exc appjail image metadata set -t "${tag}" -I -- "${reproduce_name}" "source:${arch}+=${mirror}"; then
                        err "Error adding mirror: ${mirror}"
                        total_errors=$((total_errors+1))
                    fi
                done
            done
        done
    done

    info "---"

    # Dramatic delay.
    sleep 1

    info "Ended at `date`"
    info "Build time: `calc_build_time ${init_build_time}`"
    info "Hits: ${total_hits}"
    info "Errors: ${total_errors}"
}

getkey()
{
    printf "%s" "$2" | cut -d"$1" -f1
}

getvalue()
{
    printf "%s" "$2" | cut -s -d"$1" -f2-
}

sig_handler()
{
    trap '' ${HANDLER_SIGNALS} EXIT

    sig_handler_unset_IFS
    sig_handler_terminate_last_pid
    sig_handler_remove_last_jail
    sig_handler_remove_lock

    trap - ${HANDLER_SIGNALS} ${IGNORED_SIGNALS} EXIT
}

sig_handler_unset_IFS()
{
    unset IFS
}

sig_handler_remove_lock()
{
    if checkyesno "REMOVE_LOCK" "${REMOVE_LOCK}" && [ -f "${RUNDIR}/lock" ]; then
        debug "Unlocking ..."

        rm -f -- "${RUNDIR}/lock"
    fi
}

sig_handler_terminate_last_pid()
{
    if [ -n "${LAST_PIDS}" ]; then
        local pid

        for pid in ${LAST_PIDS}; do
            safe_kill ${pid}
        done
    fi
}

sig_handler_remove_last_jail()
{
    if [ -n "${LAST_JAIL}" ]; then
        stop_and_destroy_jail "${LAST_JAIL}"
    fi
}

trace_exc()
{
    local pid

    "$@" &

    pid=$!

    LAST_PIDS="${LAST_PIDS} ${pid}"

    wait ${pid}
}

safe_kill()
{
	local pid

	pid=$1

	if [ -z "${pid}" ]; then
		echo "safe_kill pid"
		exit ${EX_USAGE}
	fi

    appjail cmd jaildir kill ${pid} > /dev/null 2>&1

    appjail cmd jaildir pwait -o -t 30 ${pid} > /dev/null 2>&1

    if [ $? -eq 124 ]; then
        warn "Timeout has been reached, pid ${pid} is still running!"
    fi
}

usage()
{
    cat << EOF
usage: appjail-reproduce -h
       appjail-reproduce -v
       appjail-reproduce -b [-d] [-A include_files] [-B include_files] [-C compress]
                         [-c config] [-j prefix] [-l logsdir] [-m mirrors]
                         [-p projectsdir] [project[%arch1,archN][:tag1,tagN] ...]
EOF
}

help()
{
    cat << EOF
`usage`

AppJail Reproduce is a small open source BSD-3 licensed tool for automating the
creation of images using Makejails, scripts and simple text files, providing a
common workflow and simplifying many things.

Parameters:
    -b                      -- Build one or more projects.
    -h                      -- Show this message and exit.
    -v                      -- Show the version and exit.

Options:
    -d                      -- Enable debug logging.
    -A include_files        -- List of Makejails to include after the main instructions.
    -B include_files        -- List of Makejails to include before the main instructions.
    -C compress             -- Compress the images using this algorithm.
    -c config               -- Configuration file.
    -j prefix               -- Jail prefix.
    -l logsdir              -- Logs directory.
    -m mirrors              -- List of mirrors. 
    -p projectsdir          -- Projects directory.
    -r rundir               -- Directory used by Reproduce to store certain information,
                               such as the lock file and jail names.
EOF
}

version()
{
    echo "${VERSION}"
}

calc_build_time()
{
    local init_time="$1"
    local current_seconds=`date +"%s"`
    current_seconds=$((current_seconds-$init_time))

    printf "%02d:%02d:%02d" $((current_seconds/3600)) $((current_seconds%3600/60)) $((current_seconds%60))
}

stop_and_destroy_jail()
{
    debug "Trying to stop and destroy '$1'"

    stop_jail "$1" || return 0

    debug "Destroying jail $1"
    
    appjail jail destroy -Rf -- "$1" > /dev/null 2>&1
}

stop_jail()
{
    if ! appjail jail get -- "$1" name > /dev/null 2>&1; then
        debug "Jail '$1' not found."

        return 1
    fi

    if appjail status -q -- "$1" > /dev/null 2>&1; then
        debug "Stopping jail $1"

        appjail stop -- "$1" > /dev/null 2>&1
    fi

    return 0
}

checkmatch()
{
    local item

    IFS="$1"

    for item in $3; do
        if [ -z "${item}" ]; then
            continue
        fi

        if [ "${item}" = "$2" ]; then
            unset IFS

            return 0
        fi
    done

    unset IFS

    return 1
}

checkyesno()
{
    case "$2" in
        [Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]|1) return 0 ;;
        [Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]|[Oo][Ff][Ff]|0) return 1 ;;
        *) warn "$1 is not set properly."; return 2 ;;
    esac
}

checkparam()
{
    local errlevel
    local output

    output=`appjail-config get -CV -t "$1" -- "$2" 2>&1`

    errlevel=$?

    if [ ${errlevel} -eq ${EX_OK} ]; then
        return 0
    elif [ ${errlevel} -eq ${EX_NOINPUT} ]; then
        return 1
    else
        err "${output}"
        return ${errlevel}
    fi
}

getconf()
{
    _getconf -t "$1" -ni -- "$2"
}

getallconf()
{
    _getconf -t "$1" -niP -- "$2"
}

_getconf()
{
    local errlevel
    local output

    output=`appjail-config get -V "$@" 2>&1`

    errlevel=$?

    if [ ${errlevel} -eq ${EX_OK} -o ${errlevel} -eq ${EX_NOINPUT} ]; then
        if [ -n "${output}" ]; then
            printf "%s\n" "${output}"
        fi

        return 0
    else
        err "${output}"
        return ${errlevel}
    fi
}

safe_exc()
{
    local errlevel
    local output

    debug "Executing '$*'"

    output=`"$@" 2>&1`

    errlevel=$?

    if [ ${errlevel} -ne 0 ]; then
        err "${output}"
        return ${errlevel}
    fi

    if [ -n "${output}" ]; then
        printf "%s\n" "${output}"
    fi

    return ${errlevel}
}

debug()
{
    if checkyesno "DEBUG" "${DEBUG}"; then
        stderr "[${COLOR_GRAY} debug${COLOR_DEFAULT} ] $*"
    fi
}

info()
{
    stderr "[${COLOR_LIGHT_BLUE} info ${COLOR_DEFAULT} ] $*"
}

err()
{
    stderr "[${COLOR_RED} error${COLOR_DEFAULT} ] $*"
}

warn()
{
    stderr "[${COLOR_LIGHT_YELLOW} warn ${COLOR_DEFAULT} ] $*"
}

stdout()
{
    print "$*"
}

stderr()
{
    print "$*" >&2
}

print()
{
    echo -e "$*"
}

main "$@"
