#!/bin/bash -e

ALTERNATIVE_WAITER="${ALTERNATIVE_WAITER:-0}"
EARLY_TTYS="${EARLY_TTYS:-${ALTERNATIVE_WAITER}}"
SELECT_THEME="${SELECT_THEME:-0}"
REBUILD_INITRD="${REBUILD_INITRD:-0}"
THEME="${THEME:-example}"
RENAME="${RENAME:-themer}"

# This is determined automagically later from the plymouth-set-default-theme command
THEMES="/usr/share/plymouth/themes"
ETC="/etc"

VARIANT="default"

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
    msg "    ALTERNATIVE_WAITER=1   - modify plymouth to wait for splash-waiter script before quitting."
    msg "    EARLY_TTYS=1           - stop getty service from waiting for plymouth to quit."
    msg "    SELECT_THEME=1         - select this theme as the default after installation."
    msg "    REBUILD_INITRD=1       - use -R option to plymouth-set-default-theme"
    msg "    THEME=<name>           - change the theme name"
    msg "    VARIANT=<name>         - change the theme variant name"
}

function install-dropin()
{
    local service_name="${1}"
    local file="${2}"
    local dir="/etc/systemd/system/${service_name}.service.d"
    mkdir -p "${dir}"
    cp -f "${file}" "${dir}/"
}

function is-installed()
{
    command -v "${1}" > /dev/null 2>&1
}

function install-plymouth()
{
    # We need plymouth-themes for the plymouth script plugin
    if is-installed apt-get
    then
        apt-get -y install plymouth-themes || /bin/true
    elif is-installed yum || is-installed dnf
    then
        yum -y install plymouth-plugin-script
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

    copy-as-new-theme
}

function select-theme()
{
    if (( SELECT_THEME ))
    then
        local rebuild_flag=""
        if (( REBUILD_INITRD ))
        then
            rebuild_flag="-R"
        fi
        plymouth-set-default-theme ${rebuild_flag} "${THEME}"
        echo "SPLASH_VARIANT=${VARIANT}" > "/etc/default/splash-${THEME}"
        # Note that this file needs to be edited within the initrd, generally, not the main
        # system (unless for example we're still running with the initrd as with a diskless boot)
        sed -i 's/^Theme=/Theme=${THEME}/' "${ETC}/plymouth/plymouthd.conf"
    fi
}

function configure-themer()
{
    cp -f splash-themer.sh /usr/local/bin
    install-dropin plymouth-start splash-themer.conf
}

function configure-ttys()
{
    # If the splash is being reconfigured to wait for some other condition
    # then we need to stop the login ttys from waiting for the splash
    if (( EARLY_TTYS ))
    then
        local getty_service=$(systemctl cat getty@.service)

        # The 'systemctl cat' can fail when running in chroot or fakeroot
        if [[ -z "${getty_service}" ]]
        then
            local -
            shopt -s nullglob
            local -a getty_service_files=( $(echo /{usr,}/lib/systemd/system/getty@.service) )
            local f
            for f in "${getty_service_files[@]}"
            do
                msg "Check ${f}"
                getty_service=$(cat "${f}")
                [[ -n "${getty_service}" ]] && break
            done
        fi

        if [[ -z "${getty_service}" ]]
        then
            err "Could not find existing getty service!"
        else
            local getty_after=$(sed <<< "${getty_service}" -n -e '/^After=/ { s/(plymouth-quit-wait|rc-local)[.]service/ /g; s/^After=[[:space:]]*$//; p}' )
            local tmpd=$(mktemp -t -d tmp_dropin.XXXXXX)
            local getty_dropin="${tmpd}/splash-waiter.conf"
            echo -e "[Unit]\nAfter=\n${getty_after}" > "${getty_dropin}"

           install-dropin getty@.service "${getty_dropin}"
           systemctl disable getty@tty1.service
        fi
    fi
}

function configure-waiter()
{
    if (( ALTERNATIVE_WAITER ))
    then
        cp -f splash-waiter.sh /usr/local/bin
        install-dropin plymouth-quit splash-waiter.conf
    fi
}

function copy-as-new-theme()
{
    if [[ -n "${RENAME}" ]] && [[ "${RENAME}" != "${THEME_NAME}" ]]
    then
        msg "Copying theme ${THEME} as ${RENAME}."
        local old_theme="${THEMES}/${THEME##*/}/"
        local new_theme="${THEMES}/${RENAME}/"
        rsync -av "${THEMES}/${THEME##*/}/" "${RENAME}/"
        mv "${new_theme}/${THEME}.plymouth" "${new_theme}/${RENAME}.plymouth"
        sed -i 's%themes/${THEME}%themes/${RENAME}%' "${new_theme}/${RENAME}.plymouth"
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
            ALTERNATIVE_WAITER=*|SELECT_THEME=*|EARLY_TTYS=*|REBUILD_INITRD=*)
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
            VARIANT=*|THEME=*|RENAME=*)
                local key="${arg%%=*}"
                local val="${arg#*=}"
                eval "${key}"="${val}"
                ;;
            *)
                usage
                die "Unrecognised option: '${arg}'"
                ;;
        esac
    done
}

function determine-themedir()
{

    local cmd=$(command -v plymouth-set-default-theme)
    local check=()

    if [[ "${cmd}" =~ ^/usr/local ]]
    then
        check+=("/usr/local/share/plymouth/themes")
    elif [[ "${cmd}" =~ ^/usr/ ]]
    then
        check+=("/usr/share/plymouth/themes")
    elif [[ "${cmd}" =~ ^/opt ]]
    then
        check+=("/opt/plymouth/themes")
    else
        local bindir="${cmd%/*}"
        local bin_parent="${bindir%/bin}"
        bin_parent="${bin_parent%/sbin}"
        check+=("${bin_parent}/themes")
        check+=("${bin_parent}/share/themes")
    fi
    check+=("/usr/share/plymouth/themes")
    local dir
    for dir in "${check[@]}"
    do
        if [[ -d "${dir}" ]]
        then
            THEMES="${dir}"
            case "${d}" in
                /usr/local/*)
                    ETC="/usr/local/etc"
                    ;;
                /usr/*)
                    ETC="/etc"
                    ;;
                /opt/*)
                    ETC="/etc"
                    ;;
                *)
                    ETC="/etc"
                    ;;
            esac
            break
        fi
    done
}

function main()
{
    process-argv "${@}"

    if install-plymouth
    then
        determine-themedir
    fi

    if copy-theme
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
