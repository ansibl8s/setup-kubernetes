#!/bin/bash

__debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__my_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref cur prev words cword
}

__index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__handle_reply()
{
    __debug "${FUNCNAME}"
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            COMPREPLY=( $(compgen -W "${allflags[*]}" -- "$cur") )
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ $COMPREPLY == *= ]] || compopt +o nospace
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions=("${must_have_one_flag[@]}")
    elif [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    else
        completions=("${commands[@]}")
    fi
    COMPREPLY=( $(compgen -W "${completions[*]}" -- "$cur") )

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        declare -F __custom_func >/dev/null && __custom_func
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1
}

__handle_flag()
{
    __debug "${FUNCNAME}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __debug "${FUNCNAME}: looking for ${flagname}"
    if __contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # skip the argument to a two word flag
    if __contains_word "${words[c]}" "${two_word_flags[@]}"; then
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    # skip the flag itself
    c=$((c+1))

}

__handle_noun()
{
    __debug "${FUNCNAME}: c is $c words[c] is ${words[c]}"

    if __contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__handle_command()
{
    __debug "${FUNCNAME}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]}"
    else
        next_command="_${words[c]}"
    fi
    c=$((c+1))
    __debug "${FUNCNAME}: looking for ${next_command}"
    declare -F $next_command >/dev/null && $next_command
}

__handle_word()
{
    if [[ $c -ge $cword ]]; then
        __handle_reply
        return
    fi
    __debug "${FUNCNAME}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __handle_flag
    elif __contains_word "${words[c]}" "${commands[@]}"; then
        __handle_command
    else
        __handle_noun
    fi
    __handle_word
}

# call kubectl get $1,
__kubectl_parse_get()
{
    local template
    template="{{ range .items  }}{{ .metadata.name }} {{ end }}"
    local kubectl_out
    if kubectl_out=$(kubectl get -o template --template="${template}" "$1" 2>/dev/null); then
        COMPREPLY=( $( compgen -W "${kubectl_out[*]}" -- "$cur" ) )
    fi
}

__kubectl_get_resource()
{
    if [[ ${#nouns[@]} -eq 0 ]]; then
        return 1
    fi
    __kubectl_parse_get "${nouns[${#nouns[@]} -1]}"
}

__kubectl_get_resource_pod()
{
    __kubectl_parse_get "pod"
}

__kubectl_get_resource_rc()
{
    __kubectl_parse_get "rc"
}

# $1 is the name of the pod we want to get the list of containers inside
__kubectl_get_containers()
{
    local template
    template="{{ range .spec.containers  }}{{ .name }} {{ end }}"
    __debug "${FUNCNAME} nouns are ${nouns[*]}"

    local len="${#nouns[@]}"
    if [[ ${len} -ne 1 ]]; then
        return
    fi
    local last=${nouns[${len} -1]}
    local kubectl_out
    if kubectl_out=$(kubectl get -o template --template="${template}" pods "${last}" 2>/dev/null); then
        COMPREPLY=( $( compgen -W "${kubectl_out[*]}" -- "$cur" ) )
    fi
}

# Require both a pod and a container to be specified
__kubectl_require_pod_and_container()
{
    if [[ ${#nouns[@]} -eq 0 ]]; then
        __kubectl_parse_get pods
        return 0
    fi;
    __kubectl_get_containers
    return 0
}

__custom_func() {
    case ${last_command} in
        kubectl_get | kubectl_describe | kubectl_delete | kubectl_label | kubectl_stop)
            __kubectl_get_resource
            return
            ;;
        kubectl_logs)
            __kubectl_require_pod_and_container
            return
            ;;
        kubectl_exec)
            __kubectl_get_resource_pod
            return
            ;;
        kubectl_rolling-update)
            __kubectl_get_resource_rc
            return
            ;;
        *)
            ;;
    esac
}

_kubectl_get()
{
    last_command="kubectl_get"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("--export")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--label-columns=")
    two_word_flags+=("-L")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--watch")
    flags+=("-w")
    flags+=("--watch-only")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("componentstatus")
    must_have_one_noun+=("daemonset")
    must_have_one_noun+=("deployment")
    must_have_one_noun+=("endpoints")
    must_have_one_noun+=("event")
    must_have_one_noun+=("horizontalpodautoscaler")
    must_have_one_noun+=("ingress")
    must_have_one_noun+=("job")
    must_have_one_noun+=("limitrange")
    must_have_one_noun+=("namespace")
    must_have_one_noun+=("node")
    must_have_one_noun+=("persistentvolume")
    must_have_one_noun+=("persistentvolumeclaim")
    must_have_one_noun+=("pod")
    must_have_one_noun+=("podtemplate")
    must_have_one_noun+=("replicationcontroller")
    must_have_one_noun+=("resourcequota")
    must_have_one_noun+=("secret")
    must_have_one_noun+=("service")
    must_have_one_noun+=("serviceaccount")
    must_have_one_noun+=("thirdpartyresource")
}

_kubectl_describe()
{
    last_command="kubectl_describe"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--selector=")
    two_word_flags+=("-l")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("daemonset")
    must_have_one_noun+=("deployment")
    must_have_one_noun+=("endpoints")
    must_have_one_noun+=("horizontalpodautoscaler")
    must_have_one_noun+=("ingress")
    must_have_one_noun+=("job")
    must_have_one_noun+=("limitrange")
    must_have_one_noun+=("namespace")
    must_have_one_noun+=("node")
    must_have_one_noun+=("persistentvolume")
    must_have_one_noun+=("persistentvolumeclaim")
    must_have_one_noun+=("pod")
    must_have_one_noun+=("replicationcontroller")
    must_have_one_noun+=("resourcequota")
    must_have_one_noun+=("secret")
    must_have_one_noun+=("service")
    must_have_one_noun+=("serviceaccount")
}

_kubectl_create_namespace()
{
    last_command="kubectl_create_namespace"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dry-run")
    flags+=("--generator=")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--save-config")
    flags+=("--schema-cache-dir=")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_create_secret_docker-registry()
{
    last_command="kubectl_create_secret_docker-registry"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--docker-email=")
    flags+=("--docker-password=")
    flags+=("--docker-server=")
    flags+=("--docker-username=")
    flags+=("--dry-run")
    flags+=("--generator=")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--save-config")
    flags+=("--schema-cache-dir=")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--docker-email=")
    must_have_one_flag+=("--docker-password=")
    must_have_one_flag+=("--docker-username=")
    must_have_one_noun=()
}

_kubectl_create_secret_generic()
{
    last_command="kubectl_create_secret_generic"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--dry-run")
    flags+=("--from-file=")
    flags+=("--from-literal=")
    flags+=("--generator=")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--save-config")
    flags+=("--schema-cache-dir=")
    flags+=("--type=")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_create_secret()
{
    last_command="kubectl_create_secret"
    commands=()
    commands+=("docker-registry")
    commands+=("generic")

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_create()
{
    last_command="kubectl_create"
    commands=()
    commands+=("namespace")
    commands+=("secret")

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--save-config")
    flags+=("--schema-cache-dir=")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--filename=")
    must_have_one_flag+=("-f")
    must_have_one_noun=()
}

_kubectl_replace()
{
    last_command="kubectl_replace"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cascade")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--force")
    flags+=("--grace-period=")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--save-config")
    flags+=("--schema-cache-dir=")
    flags+=("--timeout=")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--filename=")
    must_have_one_flag+=("-f")
    must_have_one_noun=()
}

_kubectl_patch()
{
    last_command="kubectl_patch"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--patch=")
    two_word_flags+=("-p")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--patch=")
    must_have_one_flag+=("-p")
    must_have_one_noun=()
}

_kubectl_delete()
{
    last_command="kubectl_delete"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("--cascade")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--grace-period=")
    flags+=("--ignore-not-found")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--selector=")
    two_word_flags+=("-l")
    flags+=("--timeout=")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("componentstatus")
    must_have_one_noun+=("daemonset")
    must_have_one_noun+=("deployment")
    must_have_one_noun+=("endpoints")
    must_have_one_noun+=("event")
    must_have_one_noun+=("horizontalpodautoscaler")
    must_have_one_noun+=("ingress")
    must_have_one_noun+=("job")
    must_have_one_noun+=("limitrange")
    must_have_one_noun+=("namespace")
    must_have_one_noun+=("node")
    must_have_one_noun+=("persistentvolume")
    must_have_one_noun+=("persistentvolumeclaim")
    must_have_one_noun+=("pod")
    must_have_one_noun+=("podtemplate")
    must_have_one_noun+=("replicationcontroller")
    must_have_one_noun+=("resourcequota")
    must_have_one_noun+=("secret")
    must_have_one_noun+=("service")
    must_have_one_noun+=("serviceaccount")
    must_have_one_noun+=("thirdpartyresource")
}

_kubectl_edit()
{
    last_command="kubectl_edit"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--save-config")
    flags+=("--windows-line-endings")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_apply()
{
    last_command="kubectl_apply"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--schema-cache-dir=")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--filename=")
    must_have_one_flag+=("-f")
    must_have_one_noun=()
}

_kubectl_namespace()
{
    last_command="kubectl_namespace"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_logs()
{
    last_command="kubectl_logs"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--container=")
    two_word_flags+=("-c")
    flags+=("--follow")
    flags+=("-f")
    flags+=("--interactive")
    flags+=("--limit-bytes=")
    flags+=("--previous")
    flags+=("-p")
    flags+=("--since=")
    flags+=("--since-time=")
    flags+=("--tail=")
    flags+=("--timestamps")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_rolling-update()
{
    last_command="kubectl_rolling-update"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--container=")
    flags+=("--deployment-label-key=")
    flags+=("--dry-run")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--image=")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--poll-interval=")
    flags+=("--rollback")
    flags+=("--schema-cache-dir=")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--timeout=")
    flags+=("--update-period=")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--filename=")
    must_have_one_flag+=("-f")
    must_have_one_flag+=("--image=")
    must_have_one_noun=()
}

_kubectl_scale()
{
    last_command="kubectl_scale"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--current-replicas=")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--replicas=")
    flags+=("--resource-version=")
    flags+=("--timeout=")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--replicas=")
    must_have_one_noun=()
}

_kubectl_cordon()
{
    last_command="kubectl_cordon"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_drain()
{
    last_command="kubectl_drain"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--grace-period=")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_uncordon()
{
    last_command="kubectl_uncordon"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_attach()
{
    last_command="kubectl_attach"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--container=")
    two_word_flags+=("-c")
    flags+=("--stdin")
    flags+=("-i")
    flags+=("--tty")
    flags+=("-t")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_exec()
{
    last_command="kubectl_exec"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--container=")
    two_word_flags+=("-c")
    flags+=("--pod=")
    two_word_flags+=("-p")
    flags+=("--stdin")
    flags+=("-i")
    flags+=("--tty")
    flags+=("-t")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_port-forward()
{
    last_command="kubectl_port-forward"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--pod=")
    two_word_flags+=("-p")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_proxy()
{
    last_command="kubectl_proxy"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--accept-hosts=")
    flags+=("--accept-paths=")
    flags+=("--address=")
    flags+=("--api-prefix=")
    flags+=("--disable-filter")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--reject-methods=")
    flags+=("--reject-paths=")
    flags+=("--unix-socket=")
    two_word_flags+=("-u")
    flags+=("--www=")
    two_word_flags+=("-w")
    flags+=("--www-prefix=")
    two_word_flags+=("-P")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_run()
{
    last_command="kubectl_run"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--attach")
    flags+=("--command")
    flags+=("--dry-run")
    flags+=("--env=")
    flags+=("--expose")
    flags+=("--generator=")
    flags+=("--hostport=")
    flags+=("--image=")
    flags+=("--labels=")
    two_word_flags+=("-l")
    flags+=("--leave-stdin-open")
    flags+=("--limits=")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--overrides=")
    flags+=("--port=")
    flags+=("--replicas=")
    two_word_flags+=("-r")
    flags+=("--requests=")
    flags+=("--restart=")
    flags+=("--rm")
    flags+=("--save-config")
    flags+=("--service-generator=")
    flags+=("--service-overrides=")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--stdin")
    flags+=("-i")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--tty")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--image=")
    must_have_one_noun=()
}

_kubectl_expose()
{
    last_command="kubectl_expose"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--container-port=")
    flags+=("--create-external-load-balancer")
    flags+=("--dry-run")
    flags+=("--external-ip=")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--generator=")
    flags+=("--labels=")
    two_word_flags+=("-l")
    flags+=("--load-balancer-ip=")
    flags+=("--name=")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--overrides=")
    flags+=("--port=")
    flags+=("--protocol=")
    flags+=("--save-config")
    flags+=("--selector=")
    flags+=("--session-affinity=")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--target-port=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--type=")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_autoscale()
{
    last_command="kubectl_autoscale"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cpu-percent=")
    flags+=("--dry-run")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--generator=")
    flags+=("--max=")
    flags+=("--min=")
    flags+=("--name=")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--save-config")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--max=")
    must_have_one_noun=()
}

_kubectl_label()
{
    last_command="kubectl_label"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("--dry-run")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--overwrite")
    flags+=("--resource-version=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("componentstatus")
    must_have_one_noun+=("daemonset")
    must_have_one_noun+=("deployment")
    must_have_one_noun+=("endpoints")
    must_have_one_noun+=("event")
    must_have_one_noun+=("horizontalpodautoscaler")
    must_have_one_noun+=("ingress")
    must_have_one_noun+=("job")
    must_have_one_noun+=("limitrange")
    must_have_one_noun+=("namespace")
    must_have_one_noun+=("node")
    must_have_one_noun+=("persistentvolume")
    must_have_one_noun+=("persistentvolumeclaim")
    must_have_one_noun+=("pod")
    must_have_one_noun+=("podtemplate")
    must_have_one_noun+=("replicationcontroller")
    must_have_one_noun+=("resourcequota")
    must_have_one_noun+=("secret")
    must_have_one_noun+=("service")
    must_have_one_noun+=("serviceaccount")
    must_have_one_noun+=("thirdpartyresource")
}

_kubectl_annotate()
{
    last_command="kubectl_annotate"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--overwrite")
    flags+=("--resource-version=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config_view()
{
    last_command="kubectl_config_view"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--flatten")
    flags+=("--merge")
    flags+=("--minify")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--raw")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config_set-cluster()
{
    last_command="kubectl_config_set-cluster"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--embed-certs")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--server=")
    flags+=("--alsologtostderr")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config_set-credentials()
{
    last_command="kubectl_config_set-credentials"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--embed-certs")
    flags+=("--password=")
    flags+=("--token=")
    flags+=("--username=")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--user=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config_set-context()
{
    last_command="kubectl_config_set-context"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    flags+=("--namespace=")
    flags+=("--user=")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config_set()
{
    last_command="kubectl_config_set"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config_unset()
{
    last_command="kubectl_config_unset"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config_use-context()
{
    last_command="kubectl_config_use-context"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_config()
{
    last_command="kubectl_config"
    commands=()
    commands+=("view")
    commands+=("set-cluster")
    commands+=("set-credentials")
    commands+=("set-context")
    commands+=("set")
    commands+=("unset")
    commands+=("use-context")

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--kubeconfig=")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_cluster-info()
{
    last_command="kubectl_cluster-info"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_api-versions()
{
    last_command="kubectl_api-versions"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_version()
{
    last_command="kubectl_version"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--client")
    flags+=("-c")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_explain()
{
    last_command="kubectl_explain"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--recursive")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

_kubectl_convert()
{
    last_command="kubectl_convert"
    commands=()

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__handle_filename_extension_flag json|yaml|yml")
    flags+=("--local")
    flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--output-version=")
    flags+=("--schema-cache-dir=")
    flags+=("--show-all")
    flags+=("-a")
    flags+=("--sort-by=")
    flags+=("--template=")
    two_word_flags+=("-t")
    flags+=("--validate")
    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_flag+=("--filename=")
    must_have_one_flag+=("-f")
    must_have_one_noun=()
}

_kubectl()
{
    last_command="kubectl"
    commands=()
    commands+=("get")
    commands+=("describe")
    commands+=("create")
    commands+=("replace")
    commands+=("patch")
    commands+=("delete")
    commands+=("edit")
    commands+=("apply")
    commands+=("namespace")
    commands+=("logs")
    commands+=("rolling-update")
    commands+=("scale")
    commands+=("cordon")
    commands+=("drain")
    commands+=("uncordon")
    commands+=("attach")
    commands+=("exec")
    commands+=("port-forward")
    commands+=("proxy")
    commands+=("run")
    commands+=("expose")
    commands+=("autoscale")
    commands+=("label")
    commands+=("annotate")
    commands+=("config")
    commands+=("cluster-info")
    commands+=("api-versions")
    commands+=("version")
    commands+=("explain")
    commands+=("convert")

    flags=()
    two_word_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--api-version=")
    flags+=("--certificate-authority=")
    flags+=("--client-certificate=")
    flags+=("--client-key=")
    flags+=("--cluster=")
    flags+=("--context=")
    flags+=("--insecure-skip-tls-verify")
    flags+=("--kubeconfig=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-flush-frequency=")
    flags+=("--logtostderr")
    flags+=("--match-server-version")
    flags+=("--namespace=")
    flags+=("--password=")
    flags+=("--server=")
    two_word_flags+=("-s")
    flags+=("--stderrthreshold=")
    flags+=("--token=")
    flags+=("--user=")
    flags+=("--username=")
    flags+=("--v=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
}

__start_kubectl()
{
    local cur prev words cword
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __my_init_completion || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("kubectl")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local last_command
    local nouns=()

    __handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -F __start_kubectl kubectl
else
    complete -o nospace -F __start_kubectl kubectl
fi

# ex: ts=4 sw=4 et filetype=sh
