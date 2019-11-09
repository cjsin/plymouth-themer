#!/bin/bash

TTY="tty1"
WAIT=60
START_TTY=0
SWITCH_TTY=5
LOGFILE=/dev/shm/splash-waiter.log
KERNEL_REGEX='(^|[[:space:]])splash([[:space:]]|)$'

function usage()
{
    echo "${0##*/} [--help|--ready|--wait]" 1>&2
}

function do_wait()
{
    if ! egrep "${KERNEL_REGEX}" /proc/cmdline
    then
        echo "The splash is not enabled." 1>&2
        return 0
    fi

    if ! (( waited ))
    then
        sleep "${WAIT}"
    fi
}
function motd()
(
    export TERM=linux
    clear
    if [[ -d "/etc/update-motd.d" ]]
    then
        local f
        shopt -s nullglob
        for f in /etc/update-motd.d/*
        do
            "${f}"
        done
    fi
)

function do_ready()
{
    motd < "/dev/${TTY}" > "/dev/${TTY}" 1>&2

    if (( START_TTY ))
    then
        systemctl enable "getty@${TTY}.service"
        systemctl start  "getty@${TTY}.service"
    fi

    if (( SWITCH_TTY ))
    then
        chvt ${SWITCH_TTY}
    fi
}

function main()
{
    if ! (( $# ))
    then
        usage
        exit 1
    fi
    local waited=0
    [[ -f "${LOGFILE}" ]] && waited=1

    local arg=""
    for arg in "${@}"
    do
        case "${arg}" in
            -h|-help|--help|help)
                usage
                return 0
                ;;
            -r|-ready|--ready|ready)
                do_ready
                ;;
            -w|-wait|--wait|wait)
                do_wait > "${LOGFILE}" 2>&1
                ;;
            *)
                err "Unrecognised argument: ${arg}"
                usage
                return 1
                ;;
        esac
    done
}

main "${@}"
