#!/bin/bash

# This script extracts layer images from an open raster image file (collection of layer PNG files)
# and renames the PNGs to match the layer name.

# the temp dir, a global for the cleanup trap
tmpd=""
tmp_template="tmp_ora.XXXXXX"
tmp_pattern="tmp_ora[.].{6}"

function cleanup()
{
    pkill -KILL -P $$
    cd /
    if [[ -d "${tmpd}" && "${tmpd}" =~ ${tmp_pattern} ]]
    then
        msg ""
        msg "Cleanup ${tmpd}"
        rm -rf "${tmpd}"
    fi
}

function msg()
{
    echo "${*}" 1>&2
}

function err()
{
    echo "ERROR: ${*}" 1>&2
}

function die()
{
    err "${@}"
    exit 1
}

function usage()
{
    msg "Usage: ${0##*/} [image.ora] [destination|--dest=destination] [--name=<pattern>...]"
    msg ""
    msg "Extract ora files and rename the images"
}

function extract_and_rename()
(
    local from="${1}"
    local to="${2}"
    set -e
    cd "${to}"
    unzip "${from}"

    local _lines=$(cat stack.xml | tr '<>' '\n' | egrep src= | sed -e  's/^layer //' -e 's% /%%')
    local -a lines=()
    mapfile -t lines <<< "${_lines}"
    local line
    local name_regex='.*name="([^"]*)"'
    local src_regex='.*src="*([^"]*)"'
    for line in "${lines[@]}"
    do
        #echo "Process line ${line}"
        local name="" src=""
        [[ "${line}" =~ ${name_regex} ]] && name="${BASH_REMATCH[1]}"
        [[ "${line}" =~ ${src_regex} ]] && src="${BASH_REMATCH[1]}"
        if [[ -n "${src}" && -n "${name}" ]]
        then
            name="${name// /-}"
            msg "Renaming ${src} to ${name}.png"
            mv -f "./${src}" "./${name}.png"
        else
            err "Could not parse line ${line}"
        fi
    done
    rm -f stack.xml
    rm -f mimetype
    rmdir data
    rm -f Thumbnails/thumbnail.png
    rmdir Thumbnails
    echo "Unpacked and renamed"
)

function move_files()
{
    local tmpd="${1}"
    local -a only=("${@:2}")
    local f

    for f in "${tmpd}"/*.png
    do
        if (( "${#only[@]}" ))
        then
            # filter by name
            local o
            local matched=0;
            local n="${f##*/}"
            n="${n%.png}"s

            for o in "${only[@]}"
            do
                if [[ "${n}" =~ ${o} ]]
                then
                    ((matched++))
                    break
                fi
            done
            if ! (( matched ))
            then
                msg "Skip ${n} - did not match any of ${only[*]}"
                continue
            fi
        fi
        local result
        if ! mv -i "${f}" ./
        then
            # mv -i returns 0 on overwrite and when the user skips.
            # but returns an exit status when the user Ctrl-C's
            return 1
        fi
    done
}

function main()
{
    local orafile=""
    local dest=""
    local pattern=""
    local arg
    local -a only=()

    for arg in "${@}"
    do
        case "${arg}" in
            *.ora)
                orafile="${arg}"
                ;;
            --name=*)
                only+=("${arg#*=}")
                ;;
            -h|-help|--help|help)
                usage
                exit 0
                ;;
            *)
                if [[ -d "${arg}" ]]
                then
                    dest="${arg}"
                fi
                ;;
            --dest=*)
                dest="${arg#*=}"
                ;;
        esac
    done

    [[ -f "${orafile}" ]] || die "No file specified"
    [[ "${orafile}" =~ [.]ora$ ]] || die "Expected an ora file"

    [[ -z "${dest}" ]] && dest="${PWD}"
    [[ -d "${dest}" ]] || die "Destination '${dest}' does not exist."

    tmpd=$(mktemp -t -d "${tmp_template}")

    [[ -d "${tmpd}" ]] || die "Failed creating temp dir"

    orafile=$(readlink -f "${orafile}")
    if extract_and_rename "${orafile}" "${tmpd}"
    then
        trap "cleanup" INT TERM HUP
        move_files "${tmpd}" "${only[@]}"
    fi

    cleanup
}

main "${@}"
