#!/usr/bin/env bash

_num_part='([0-9]|[1-9][0-9]*)'
_lab_part='([0-9]|[1-9][0-9]*|[0-9]*[a-zA-Z-][a-zA-Z0-9-]*)'
_met_part='([0-9A-Za-z-]+)'

RE_NUM="$_num_part(\.$_num_part)*"
RE_LAB="$_lab_part(\.$_lab_part)*"
RE_MET="$_met_part(\.$_met_part)*"
RE_VER="[ \t]*$RE_NUM(-$RE_LAB)?(\+$RE_MET)?"

BRE_NUM='[0-9]\{1,\}\(\.[0-9]\{1,\}\)*'
BRE_PRE='[0-9a-zA-Z-]\{1,\}\(\.[0-9a-zA-Z-]\{1,\}\)*'
BRE_MET='[0-9A-Za-z-]\{1,\}'
BRE_VER="$BRE_NUM\(-$BRE_PRE\)\{0,1\}\(+$BRE_MET\)\{0,1\}"

filter()
{
    local text="$1"
    local regex="$2"
    shift 2
    echo "$text" | grep -E "$@" "$regex"
}

# Gets number part from normalized version
get_number()
{
    echo "${1%%-*}"
}

# Gets prerelase part from normalized version
get_prerelease()
{
    pre_and_meta=${1%+*}
    pre=${pre_and_meta#*-}
    if [ "$pre" = "$1" ]; then
        echo
    else
        echo "$pre"
    fi
}

# Gets major number from normalized version
get_major()
{
    echo "${1%%.*}"
}

# Gets minor number from normalized version
get_minor()
{
    minor_major_bug=${1%%-*}
    minor_major=${minor_major_bug%.*}
    minor=${minor_major#*.}

    if [ "$minor" = "$minor_major" ]; then
        echo
    else
        echo "$minor"
    fi
}

get_bugfix()
{
    minor_major_bug=${1%%-*}
    bugfix=${minor_major_bug##*.*.}

    if [ "$bugfix" = "$minor_major_bug" ]; then
        echo
    else
        echo "$bugfix"
    fi
}

strip_metadata()
{
    echo "${1%+*}"
}

semver_eq()
{
    local ver1 ver2 part1 part2
    ver1=$(get_number "$1")
    ver2=$(get_number "$2")

    local count=1
    while true; do
        part1=$(echo "$ver1"'.' | cut -d '.' -f $count)
        part2=$(echo "$ver2"'.' | cut -d '.' -f $count)

        if [ -z "$part1" ] || [ -z "$part2" ]; then
            break
        fi

        if [ "$part1" != "$part2" ]; then
            return 1
        fi

        local count=$(( count + 1 ))
    done

    if [ "$(get_prerelease "$1")" = "$(get_prerelease "$2")" ]; then
        return 0
    else
        return 1
    fi
}

semver_lt()
{
    local number_a number_b prerelease_a prerelease_b
    number_a=$(get_number "$1")
    number_b=$(get_number "$2")
    prerelease_a=$(get_prerelease "$1")
    prerelease_b=$(get_prerelease "$2")


    local head_a=''
    local head_b=''
    local rest_a=$number_a.
    local rest_b=$number_b.
    while [ -n "$rest_a" ] || [ -n "$rest_b" ]; do
        head_a=${rest_a%%.*}
        head_b=${rest_b%%.*}
        rest_a=${rest_a#*.}
        rest_b=${rest_b#*.}

        if [ -z "$head_a" ] || [ -z "$head_b" ]; then
            return 1
        fi

        if [ "$head_a" -eq "$head_b" ]; then
            continue
        fi

        if [ "$head_a" -lt "$head_b" ]; then
            return 0
        else
            return 1
        fi
    done

    if [ -n "$prerelease_a" ] && [ -z "$prerelease_b" ]; then
        return 0
    elif [ -z "$prerelease_a" ] && [ -n "$prerelease_b" ]; then
        return 1
    fi

    local head_a=''
    local head_b=''
    local rest_a=$prerelease_a.
    local rest_b=$prerelease_b.
    while [ -n "$rest_a" ] || [ -n "$rest_b" ]; do
        head_a=${rest_a%%.*}
        head_b=${rest_b%%.*}
        rest_a=${rest_a#*.}
        rest_b=${rest_b#*.}

        if [ -z "$head_a" ] && [ -n "$head_b" ]; then
            return 0
        elif [ -n "$head_a" ] && [ -z "$head_b" ]; then
            return 1
        fi

        if [ "$head_a" = "$head_b" ]; then
            continue
        fi

        # If both are numbers then compare numerically
        if [ "$head_a" = "${head_a%[!0-9]*}" ] && [ "$head_b" = "${head_b%[!0-9]*}" ]; then
            [ "$head_a" -lt "$head_b" ] && return 0 || return 1
        # If only a is a number then return true (number has lower precedence than strings)
        elif [ "$head_a" = "${head_a%[!0-9]*}" ]; then
            return 0
        # If only b is a number then return false
        elif [ "$head_b" = "${head_b%[!0-9]*}" ]; then
            return 1
        # Finally if of identifiers is a number compare them lexically
        else
            test "$head_a" \< "$head_b" && return 0 || return 1
        fi
    done

    return 1
}

semver_gt()
{
    if semver_lt "$1" "$2" || semver_eq "$1" "$2"; then
        return 1
    else
        return 0
    fi
}

semver_le()
{
    semver_gt "$1" "$2" && return 1 || return 0
}

semver_ge()
{
    semver_lt "$1" "$2" && return 1 || return 0
}

semver_sort()
{
    if [ $# -le 1 ]; then
        echo "$1"
        return
    fi

    local pivot=$1
    local args_a=()
    local args_b=()

    shift 1

    for ver in "$@"; do
        if semver_le "$ver" "$pivot"; then
            args_a=( "${args_a[@]}" "$ver" )
        else
            args_b=( "$ver" "${args_b[@]}" )
        fi
    done

    args_a=( $(semver_sort "${args_a[@]}") )
    args_b=( $(semver_sort "${args_b[@]}") )
    echo "${args_a[@]}" "$pivot" "${args_b[@]}"
}

regex_match()
{
    local string="$1 "
    local regexp="$2"
    local match
    match="$(eval "echo '$string' | grep -E -o '^[ \t]*($regexp)[ \t]+'")";

    for i in $(seq 0 9); do
        unset "MATCHED_VER_$i"
        unset "MATCHED_NUM_$i"
    done
    unset REST

    if [ -z "$match" ]; then
        return 1
    fi

    local match_len=${#match}
    REST="${string:$match_len}"

    local part
    local i=1
    for part in $string; do
        local ver num
        ver="$(eval "echo '$part' | grep -E -o '$RE_VER'   | head -n 1 | sed 's/ \t//g'")";
        num=$(get_number "$ver")

        if [ -n "$ver" ]; then
            eval "MATCHED_VER_$i='$ver'"
            eval "MATCHED_NUM_$i='$num'"
            i=$(( i + 1 ))
        fi
    done

    return 0
}

# Normalizes rules string
#
# * replaces chains of whitespaces with single spaces
# * replaces whitespaces around hyphen operator with "_"
# * removes wildcards from version numbers (1.2.* -> 1.2)
# * replaces "x" with "*"
# * removes whitespace between operators and version numbers
# * removes leading "v" from version numbers
# * removes leading and trailing spaces
normalize_rules()
{
    echo " $1" \
        | sed 's/\\t/ /g' \
        | sed 's/	/ /g' \
        | sed 's/ \{2,\}/ /g' \
        | sed 's/ - /_-_/g' \
        | sed 's/\([~^<>=]\) /\1/g' \
        | sed 's/\([ _~^<>=]\)v/\1/g' \
        | sed 's/\.[xX*]//g' \
        | sed 's/[xX]/*/g' \
        | sed 's/^ //g' \
        | sed 's/ $//g'
}

# Reads rule from provided string
read_rule()
{
    RULEIND=$(( RULEIND + 1 ))

    local _rule _idnt _vers
    _rule="$( echo "$1 " | cut -d ' ' -f $RULEIND  )"
    _idnt="$( echo "$_rule" | sed "s/$BRE_VER/#/g" )"
    _vers="$( echo "$_rule" | grep -o "$BRE_VER"   )"

    # if rule is empty - there is no more rules
    if [ -z "$_rule" ]; then
        return 1
    fi

    local _i=1;
    for ver in $_vers; do
        eval "RULEVER_$_i='$ver'"
        _i=$(( _i + 1 ))
    done

    # set global variable
    eval "$2='$_idnt'"
}

resolve_rule()
{
    RULEIND=0

    local rules
    rules="$(normalize_rules "$1")"

    while read_rule "${rules:-all}" rule; do
        case "$rule" in
            '*')     echo "all";;
            '#')     echo "eq $RULEVER_1";;
            '=#')    echo "eq $RULEVER_1";;
            '<#')    echo "lt $RULEVER_1";;
            '>#')    echo "gt $RULEVER_1";;
            '<=#')   echo "le $RULEVER_1";;
            '>=#')   echo "ge $RULEVER_1";;
            '#_-_#') echo "ge $RULEVER_1"
                     echo "le $RULEVER_2";;
            '~#')    echo "tilde $RULEVER_1";;
            '^#')    echo "caret $RULEVER_1";;
            *)       return 1
        esac
    done
}

rule_eq()
{
    local rule_ver="$1"
    local tested_ver="$2"

    semver_eq "$tested_ver" "$rule_ver" && return 0 || return 1;
}

rule_le()
{
    local rule_ver="$1"
    local tested_ver="$2"

    semver_le "$tested_ver" "$rule_ver" && return 0 || return 1;
}

rule_lt()
{
    local rule_ver="$1"
    local tested_ver="$2"

    semver_lt "$tested_ver" "$rule_ver" && return 0 || return 1;
}

rule_ge()
{
    local rule_ver="$1"
    local tested_ver="$2"

    semver_ge "$tested_ver" "$rule_ver" && return 0 || return 1;
}

rule_gt()
{
    local rule_ver="$1"
    local tested_ver="$2"

    semver_gt "$tested_ver" "$rule_ver" && return 0 || return 1;
}

rule_tilde()
{
    local rule_ver="$1"
    local tested_ver="$2"

    if rule_ge "$rule_ver" "$tested_ver"; then
        local rule_major rule_minor
        rule_major=$(get_major "$rule_ver")
        rule_minor=$(get_minor "$rule_ver")

        if [ -n "$rule_minor" ] && rule_eq "$rule_major.$rule_minor" "$(get_number "$tested_ver")"; then
            return 0
        fi
        if [ -z "$rule_minor" ] && rule_eq "$rule_major" "$(get_number "$tested_ver")"; then
            return 0
        fi
    fi

    return 1
}

rule_caret()
{
    local rule_ver="$1"
    local tested_ver="$2"

    if rule_ge "$rule_ver" "$tested_ver"; then
        local rule_major
        rule_major="$(get_major "$rule_ver")"

        if [ "$rule_major" != "0" ] && rule_eq "$rule_major" "$(get_number "$tested_ver")"; then
            return 0
        fi
        if [ "$rule_major" = "0" ] && rule_eq "$rule_ver" "$(get_number "$tested_ver")"; then
            return 0
        fi
    fi

    return 1
}

rule_all()
{
    return 0
}


if [ $# -eq 0 ]; then
    echo "Usage:    $0 -r <rule> <version> [<version>... ]"
fi

force_allow_prerel=false
while getopts ar:h o; do
    case "$o" in
        a) force_allow_prerel=true ;;
        r) rules_string="$OPTARG||";;
        h|?) echo "Usage:    $0 -r <rule> <version> [<version>... ]"
    esac
done

shift $(( OPTIND-1 ))

# Sort versions
versions="$(semver_sort "$@")"

output=""

# Loop over sets of rules (sets of rules are separated with ||)
for ver in $versions; do
    rules_tail="$rules_string";

    while [ -n "$rules_tail" ]; do
        head="${rules_tail%%||*}"

        if [ "$head" = "$rules_tail" ]; then
            rules_string=""
        else
            rules_tail="${rules_tail#*||}"
        fi

        #if [ -z "$head" ] || [ -n "$(echo "$head" | grep -E -x '[ \t]*')" ]; then
            #group=$(( $group + 1 ))
            #continue
        #fi

        rules="$(resolve_rule "$head")"

        # If specified rule cannot be recognised - end with error
        if [ $? -eq 1 ]; then
            exit 1
        fi

        if ! echo "$ver" | grep -q -E -x "[v=]?[ \t]*$RE_VER"; then
            continue
        fi

        ver=$(echo "$ver" | grep -E -x "$RE_VER")

        success=true
        allow_prerel=false
        if $force_allow_prerel; then
          allow_prerel=true
        fi

        while read -r rule; do
            comparator="${rule%% *}"
            operand="${rule#* }"

            if [ -n "$(get_prerelease "$operand")" ] && semver_eq "$(get_number "$operand")" "$(get_number "$ver")" || [ "$rule" = "all" ]; then
                allow_prerel=true
            fi

            "rule_$comparator" "$operand" "$ver"
            if [ $? -eq 1 ]; then
                success=false
                break
            fi
        done \
<<EOF
$rules
EOF

        if $success; then
            if [ -z "$(get_prerelease "$ver")" ] || $allow_prerel; then
                output="$output$ver\n"
                break;
            fi
        fi
    done

    group=$(( group + 1 ))
done

if [ -n "$output" ]; then
    echo "$output"
fi
