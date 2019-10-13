#!/bin/bash -e

ALTERNATIVE_WAITER="${ALTERNATIVE_WAITER:-0}"
EARLY_TTYS="${EARLY_TTYS:-${ALTERNATIVE_WAITER}}"
SELECT_THEME="${SELECT_THEME:-0}"
THEME="dudebarf"
THEMES="/usr/share/plymouth/themes"

function msg()
{
    echo "${*}" 1>&2
}

function err()
{
    msg "ERROR: ${*}"
}

function die()
{
    err "${@}"
    exit 1
}

function usage()
{
    msg "Usage for ${0##*/}"
    msg ""
    msg "    ${0##*/} [OPTION=0 | OPTION=1] ..."
    msg "    OPTION1=0 OPTION2=1 ${0##*/}"
    msg ""
    msg "Options:"
    msg "    ALTERNATIVE_WAITER   - modify plymouth to wait for splash-waiter script before quitting."
    msg "    EARLY_TTYS           - stop getty service from waiting for plymouth to quit."
    msg "    SELECT_THEME         - select this theme as the default after installation."
}

function install-dropin()
{
    local file="${1}"
    local dir="/etc/systemd/system/${2}.service.d"
    mkdir -p "${dir}"
    cp -f "${file}" "${dir}/"
}

function is-installed()
{
    command -v "${1}" > /dev/null 2>&1
}

function install-plymouth()
{
    if is-installed apt-get
    then
        apt-get -y install plymouth-themes || /bin/true
    elif is-installed yum || is-installed dnf
    then
        yum -y install plymouth-themes
    else
        err "Could not determine distro for plymouth installation."
        return 1
    fi
}

function copy-theme()
{
    local status=0
    if is-installed rsync
    then
        rsync -av "./${THEME}/" "${THEMES}/${THEME##*/}/"
        status=$?
    else
        cp -av "./${THEME}/" "${THEMES}/"
        status=$?
    fi

    if (( status ))
    then
        err "Failed copying theme files."
        return 1
    else
        msg "Copied successfully."
        return 0
    fi
}

function select-theme()
{
    if (( SELECT_THEME ))
    then
        plymouth-set-default-theme dudebarf
    fi
}

function configure-themer()
{
    install_dropin plymouth-start splash-themer.conf
}

function configure-ttys()
{
    # If the splash is being reconfigured to wait for some other condition
    # then we need to stop the login ttys from waiting for the splash
    if (( EARLY_TTYS ))
    then
        getty_after=$(systemctl cat getty@.service \
            | sed -n -e '/^After=/ { s/(plymouth-quit-wait|rc-local)[.]service/ /g; s/^After=[[:space:]]*$//; p}' )

       tmpd=$(mktemp -t -d tmp_dropin.XXXXXX)
       getty_dropin="${tmpd}/splash-waiter.conf"
       echo -e "[Unit]\nAfter=\n${getty_after}" > "${getty_dropin}"

       install_dropin getty@.service "${getty_dropin}"
       systemctl disable getty@tty1.service
    fi
}

function configure-waiter()
{
    if (( ALTERNATIVE_WAITER ))
    then
        install_dropin plymouth-quit splash-waiter.conf
    fi
}

function process-argv()
{
    local arg
    for arg in "${@}"
    do
        case "${arg}" in
            -h|-help|--help|help)
                usage
                exit 0
                ;;
            ALTERNATIVE_WAITER=*|SELECT_THEME=*|EARLY_TTYS=*)
                local key="${arg%%=*}"
                local val="${arg#*=}"
                if [[ "${val}" =~ ^[01]$ ]]
                then
                    eval "${key}=${val}"
                else
                    usage
                    die "Unrecognised option value: '${val}' for ${key}"
                fi
                ;;
            *)
                usage
                die "Unrecognised option: '${arg}'"
                ;;
        esac
    done
}

function main()
{
    process-argv "${@}"

    if install-plymouth && copy-theme
    then
        select-theme
        configure-themer
        configure-waiter
        configure-ttys
    else
        err "Some part of the installation failed."
    fi
}

main "${@}"
