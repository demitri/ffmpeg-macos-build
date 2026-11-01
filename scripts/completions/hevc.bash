# Bash completion for hevc-encode and hevc-queue.
# Install:  source /path/to/scripts/completions/hevc.bash     (e.g. from ~/.bashrc)
# Works on bash 3.2+ without the bash-completion package.

_hevc_media_files() {
    # Directories (so you can descend) plus files with common video extensions.
    local cur=$1 f
    local IFS=$'\n'
    for f in $(compgen -f -- "$cur"); do
        if [[ -d $f ]]; then
            printf '%s/\n' "$f"
        else
            case "$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')" in
                mpg|mpeg|wmv|asf|avi|mkv|mp4|m4v|mov|vob|ts|m2ts|flv|webm|ogv|3gp|divx) printf '%s\n' "$f" ;;
            esac
        fi
    done
}

_hevc_set_reply() {  # _hevc_set_reply "<words>" cur
    local IFS=$' \t\n'
    COMPREPLY=($(compgen -W "$1" -- "$2"))
}

_hevc_files_reply() {  # reply with media files/dirs for cur
    local IFS=$'\n'
    COMPREPLY=($(_hevc_media_files "$1"))
    type compopt >/dev/null 2>&1 && compopt -o filenames 2>/dev/null
    return 0
}

_hevc_job_ids() {  # ids of jobs in the given queue state dirs
    local q=${HEVC_QUEUE:-$HOME/hevc-queue} s f b
    for s in "$@"; do
        for f in "$q/$s"/*.json; do
            [[ -e $f ]] || continue
            b=${f##*/}
            printf '%s\n' "${b%%-*}"
        done
    done
}

_hevc_encode() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
    case $prev in
        --deint)   _hevc_set_reply "auto progressive interlaced telecine" "$cur"; return ;;
        --rate)    _hevc_set_reply "double single" "$cur"; return ;;
        --preset)  _hevc_set_reply "ultrafast superfast veryfast faster fast medium slow slower veryslow placebo" "$cur"; return ;;
        --outdir)  local IFS=$'\n'; COMPREPLY=($(compgen -d -- "$cur")); type compopt >/dev/null 2>&1 && compopt -o filenames 2>/dev/null; return ;;
        -o|--output) local IFS=$'\n'; COMPREPLY=($(compgen -f -- "$cur")); type compopt >/dev/null 2>&1 && compopt -o filenames 2>/dev/null; return ;;
        --crf|--size|--abitrate|--max-ratio|--threads) COMPREPLY=(); return ;;
    esac
    if [[ $cur == -* ]]; then
        _hevc_set_reply "--merge -o --output --outdir --crf --preset --deint --rate --8bit --size --abitrate --max-ratio --threads --scan -h --help" "$cur"
    else
        _hevc_files_reply "$cur"
    fi
}

_hevc_queue() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
    local sub="" i
    for ((i = 1; i < COMP_CWORD; i++)); do
        case ${COMP_WORDS[i]} in
            add|run|status|cancel|retry|pause|resume|set) sub=${COMP_WORDS[i]}; break ;;
        esac
    done
    if [[ -z $sub ]]; then
        _hevc_set_reply "add run status cancel retry pause resume set -h --help" "$cur"
        return
    fi
    case $sub in
        add)
            case $prev in
                --outdir) local IFS=$'\n'; COMPREPLY=($(compgen -d -- "$cur")); type compopt >/dev/null 2>&1 && compopt -o filenames 2>/dev/null; return ;;
                -o|--output) local IFS=$'\n'; COMPREPLY=($(compgen -f -- "$cur")); type compopt >/dev/null 2>&1 && compopt -o filenames 2>/dev/null; return ;;
                -x) COMPREPLY=(); return ;;
            esac
            if [[ $cur == -* ]]; then
                _hevc_set_reply "--merge -o --output --outdir --natural -y --yes -x" "$cur"
            else
                _hevc_files_reply "$cur"
            fi ;;
        run)    case $prev in -j|--jobs|-t|--threads) COMPREPLY=(); return ;; esac
                _hevc_set_reply "-j --jobs -t --threads --once" "$cur" ;;
        set)    case $prev in -j|--jobs|-t|--threads) COMPREPLY=(); return ;; esac
                _hevc_set_reply "-j --jobs -t --threads" "$cur" ;;
        status) _hevc_set_reply "-a --all" "$cur" ;;
        cancel) _hevc_set_reply "--all $(_hevc_job_ids pending)" "$cur" ;;
        retry)  [[ $prev == -x ]] && { COMPREPLY=(); return; }
                _hevc_set_reply "-x $(_hevc_job_ids failed)" "$cur" ;;
        pause|resume) COMPREPLY=() ;;
    esac
}

complete -F _hevc_encode hevc-encode
complete -F _hevc_queue hevc-queue
