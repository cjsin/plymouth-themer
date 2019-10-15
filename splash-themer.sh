#!/bin/bash -e
#set -vx
shopt -s nullglob

HELP_REGEX='[[:space:]](-h|-help|--help|help)[[:space:]]'
THEME_NAME="${THEME_NAME:-dudebarf}"
THEMES="${THEMES:-/usr/share/plymouth/themes}"
TESTING="${TESTING:-0}"
NUMBERING="${NUMBERING:-0}"
TEST_COMMANDLINE=(splash quiet s.printk s.variant=1 s.est=30 s.cyc=2  )
config_files=(/etc/default/splash-{${THEME_NAME}})
flag_names='^(variant|est|cyc|printk)$'

declare -A shortcuts
shortcuts=()
shortcuts["est"]="ESTIMATE"
shortcuts["cyc"]="CYCLES"

declare -A fallbacks
fallbacks=()
fallbacks["SPLASH_THEME"]="${THEME_NAME}"
fallbacks["SPLASH_VARIANT"]="default"

function msg()
{
    echo "${*}" 1>&2
}

function err()
{
    msg "ERROR: ${*}"
}

function warn()
{
    msg "WARNING: ${*}"
}

function die()
{
    err "${@}"
    exit 1
}

function usage()
{
    msg "Usage: ${0##*/} [-h|-help|--help] <options>"
    msg ""
    msg "  Process splash options and update (generate) the splash theme."
    msg ""
    msg "  If no options are specified then the contents of /proc/cmdline will be used."
    msg ""
    msg "  Options:"
    msg "     s.est             Specify an estimated boot time"
    msg "     s.cyc             I forget"
    msg "     s.variant         Choose a theme variant file"
    msg "     s.theme           Choose a different theme"
    msg "     s.!<var-name>     Set a variable in the theme file "
}

function load_config()
{
    local _lines=$(egrep '^s[.]' < "${1}")
    local -a lines=()
    mapfile -t lines <<< "${_lines}"
    process_args "${lines[@]}"
}

function load_configs()
{
    local f
    for f in "${@}"
    do
        if [[ -f "${f}" ]]
        then
            load_config "${f}"
        fi
    done
}

function store_var()
{
    local n="${1}"
    local v="${2}"
    vars+=("${1} = ${2};")
}

function store_flag()
{
    local n="${1}"
    local v="${2}"
    if [[ "${n}" =~ ${flag_names} ]]
    then
        flags+=("SPLASH_${n^^}=${v}")
    else
        warn "Unrecognised splash flag: s.${n}"
    fi
}

function process_args()
{
    local arg="" n="" v=""
    for arg in "${@}"
    do
        case "${arg}" in
            quiet)
                [[ -w /proc/sys/kernel/printk ]] && echo "2 3 1 7" > /proc/sys/kernel/printk
                ;;
            s.!*=*)
                arg="${arg:3}"
                n="${arg%%=*}"
                v="${arg#*=}"
                store_var "${n}" "${v}"
                ;;
            s.*=*)
                arg="${arg:2}"
                n="${arg%%=*}"
                v="${arg#*=}"
                store_flag "${n}" "${v}"
                ;;
            s.*)
                n="${arg:2}"
                store_flag "${n}" 1
                ;;
        esac
    done
}
function comment_block()
{
    if (( NUMBERING ))
    then
        echo "/* ${GNUM}: */ ###"
        ((GNUM++))
        echo "/* ${GNUM}: */ # ${*}"
        ((GNUM++))
        echo "/* ${GNUM}: */ ###"
        ((GNUM++))
    fi
}

function preprocess_file()
{
    local include_regex='^[[:space:]]*#include[[:space:]]+([^[:space:]#]+)'
    local comment_regex='^[[:space:]]*#'
    local empty_regex='^[[:space:]]*$'
    local f="${1}"
    local d="${f%/*}"
    [[ "${d}" == "${f}" ]] && d="."
    local n="${f##*/}"
    n="${n%.script}"
    local _lines=$(< "${f}")
    local -a lines=()
    mapfile -t lines <<< "${_lines}"
    local line

    #comment_block "Begin File ${n}"
    local LNUM=1;
    for line in "${lines[@]}"
    do
        local is_include=0
        local is_comment=0
        local is_empty=0
        local inc_f=""

        if [[ "${line}" =~ ${include_regex} ]]
        then
            inc_f="${BASH_REMATCH[1]}.script"
            is_include=1
        elif [[ "${line}" =~ ${comment_regex} ]]
        then
            is_comment=1
        elif [[ "${line}" =~ ${empty_regex} ]]
        then
            is_empty=1
        fi

        if ! (( is_include + is_comment + is_empty ))
        then
            if (( NUMBERING ))
            then
                echo "/* ${GNUM}:${n}:${LNUM} */ ${line}"
            else
                echo "${line}"
            fi
            ((GNUM++))
            ((LNUM++))
            continue;
        elif (( is_empty ))
        then
            # don't include it, but maintain the line counter
            ((LNUM++))
            continue;
        elif (( is_comment ))
        then
            # don't include it, but maintain the line counter
            ((LNUM++))
            continue
        elif (( is_include ))
        then
            #comment_block "Processing include : ${line}"
            if [[ "${inc_f:0}" != "/" ]]
            then
                inc_f="${d}/${inc_f}"
            fi
            local check="${included["${inc_f}"]}"
            if [[ -n "${check}" ]]
            then
                #comment_block "Skip #include statement for ${inc_f} - file was already included"
                continue
            else
                included["${inc_f}"]=1
            fi

            if [[ -f "${inc_f}" ]]
            then
                #comment_block "Processed #include statement for ${inc_f}"
                local result=0
                preprocess_file "${inc_f}"
                result=$?
                if (( result ))
                then
                    comment_block "ERROR leading from ${inc_f}"
                    errors+=("${inc_f}")
                fi
                ((problems+=result))
            else
                comment_block "Include not found: ${inc_f}"
            fi
        fi
    done
    return ${problems}
}

function process_file()
{
    local f="${1}"
    local output="${2:-/dev/stdout}"
    declare -A included=()
    local GNUM=1;
    local problems=0;
    local -a errors=();
    if [[ ! -f "${f}" ]]
    then
        err "File does not exist: ${f}"
        return 1
    else
        local result=0
        preprocess_file "${f}" > "${output}"
        result=$?
        if (( "${#errors[@]}" ))
        then
            local e
            for e in "${errors[@]}"
            do
                err "File '${e}' had a problem."
            done
        else
            msg "No errors seen.";
        fi
        return ${result}
    fi
}

function update_theme()
{
    local theme="${1}"
    local fallback_theme="${2}"
    local variant="${3}"
    local fallback_variant="${4}"
    echo "${FUNCNAME[0]} ${*}"
    [[ -z "${theme}" ]] && theme="${fallback_theme}"
    [[ -z "${variant}" ]] && variant="${fallback_variant}"

    local theme_dir="${THEMES}/${theme}"
    local script_dir="${theme_dir}/script"

    if [[ ! -d "${theme_dir}" ]]
    then
        err "Theme dir not found: ${theme_dir}"
        return 1
    fi

    if [[ ! -d "${script_dir}" ]]
    then
        err "Script dir not found: ${script_dir}"
        return 1
    fi

    (
        set -e
        cd "${script_dir}"
        variant_script="variant-${variant}.script"
        generated_script="${script_dir}/generated.script"

        if ! > "${generated_script}"
        then
            err "Cannot write ${script_dir}/${generated_script}"
            return 1
        fi

        if ! cat "${variant_script}" > "selected-variant.script"
        then 
            err "Could not update variant script."
        fi

        if ! > "versiontext.script" 
        then 
            err "Could not write version-text script"
        else
            (
                echo 'if (global.Version ) {'
                echo '    AddVersionText("Theme " + THEME_NAME + " v" + VERSION);'
                echo '    AddVersionText("Variant " + VARIANT_NAME);'
                echo '}'
             ) > "versiontext.script"
        fi

        if ! > "overrides.script"
        then 
            err "Could not overrides script."
        else
            for v in "${vars[@]}"
            do
                echo "${v}"
            done > "overrides.script"
        fi

        if process_file "main.script" "${generated_script}"
        then
            echo "Generated $(wc -l < "${generated_script}") lines."
            echo "(no problems)"
        else
            egrep -i error "${generated_script}"
        fi
    )
}

function main()
{
    local -a cmdline=()
    local -a vars=()
    local -a flags=()
    if (( $# ))
    then
        if [[ " ${*} " =~ ${HELP_REGEX} ]]
        then
            usage
            exit 0
        else
            cmdline=( "${@}" )
        fi
    else
        if (( TESTING ))
        then
            cmdline=("${TEST_COMMANDLINE[@]}")
        else
            cmdline=( $(< /proc/cmdline) )
        fi
    fi

    process_args "${cmdline[@]}"
    load_configs "${config_files[@]}"
    echo "Flags:" "${flags[@]}"
    eval "${flags[@]}"

    echo "Vars:" "${vars[@]}"

    echo "Updating theme."
    update_theme \
        "${SPLASH_THEME}" "${fallbacks["SPLASH_THEME"]}" \
        "${SPLASH_VARIANT}" "${fallbacks["SPLASH_VARIANT"]}"
}
main "${@}"
