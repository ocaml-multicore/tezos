#! /usr/bin/env bash

usage () {
    cat >&2 <<EOF
usage: $0 [<action>] [FILES] [--ignore FILES]

Where <action> can be:

* --update-ocamlformat: update all the \`.ocamlformat\` files and
  git-commit (requires clean repo).
* --check-ocamlformat: check the above does nothing.
* --check-gitlab-ci-yml: check .gitlab-ci.yml has been updated.
* --check-scripts: check the .sh files
* --check-redirects: check docs/_build/_redirects.
* --help: display this and return 0.
EOF
}

## Testing for dependencies
if ! type ocamlformat > /dev/null 2>&-; then
  echo "ocamlformat is required but could not be found. Aborting."
  exit 1
fi
if ! type find > /dev/null 2>&-; then
  echo "find is required but could not be found. Aborting."
  exit 1
fi


set -e

say () {
    echo "$*" >&2
}


make_dot_ocamlformat () {
    local path="$1"
    cat > "$path" <<EOF
version=0.18.0
wrap-fun-args=false
let-binding-spacing=compact
field-space=loose
break-separators=after
space-around-arrays=false
space-around-lists=false
space-around-records=false
space-around-variants=false
dock-collection-brackets=true
space-around-records=false
sequence-style=separator
doc-comments=before
margin=80
module-item-spacing=sparse
parens-tuple=always
parens-tuple-patterns=always
EOF
}

declare -a source_directories

source_directories=(src docs/doc_gen tezt)

update_all_dot_ocamlformats () {
    if git diff --name-only HEAD --exit-code
    then
        say "Repository clean :thumbsup:"
    else
        say "Repository not clean, which is required by this script."
        exit 2
    fi
    interesting_directories=$(find "${source_directories[@]}" \( -name "*.ml" -o -name "*.mli"  \) -type f | sed 's:/[^/]*$::' | LC_COLLATE=C sort -u)
    for d in $interesting_directories ; do
        ofmt=$d/.ocamlformat
        case "$d" in
            src/proto_alpha/lib_protocol | \
            src/proto_demo_noops/lib_protocol )
                make_dot_ocamlformat "$ofmt"
                ;;
            src/proto_00{0..6}_*/lib_protocol )
                make_dot_ocamlformat "$ofmt"
                ( find "$d" -maxdepth 1 -name "*.ml*"  | LC_COLLATE=C sort > "$d/.ocamlformat-ignore" ; )
                git add "$d/.ocamlformat-ignore"
                ;;
            * )
                make_dot_ocamlformat "$ofmt"
                ;;
        esac
        git add "$ofmt"
    done
}

function shellcheck_script () {
    shellcheck --external-sources "$1"
}

check_scripts () {
    # Gather scripts
    scripts=$(find "${source_directories[@]}" packaging/ tests_python/ scripts/ docs/ -name "*.sh" -type f -print)
    exit_code=0

    # Check scripts do not contain the tab character
    tab="$(printf '%b' '\t')"
    for f in $scripts ; do
        if grep -q "$tab" "$f"; then
            say "$f has tab character(s)"
            exit_code=1
        fi
    done

    # Execute shellcheck
    ./scripts/shellcheck_version.sh || return 1  # Check shellcheck's version

    shellcheck_skips=""
    while read -r shellcheck_skip; do
      shellcheck_skips+=" $shellcheck_skip"
    done < "src/tooling/shellcheck_skips"

    for script in ${scripts}; do
        if [[ "${shellcheck_skips}" == *"${script}"* ]]; then
          # check whether the skipped script, in reality, is warning-free
          if shellcheck_script "${script}" > /dev/null; then
              say "$script shellcheck marked as SKIPPED but actually pass: update shellcheck_skips ❌️"
              exit_code=1
          else
              # script is skipped, we leave a log however, to incite
              # devs to enhance the scripts
              say "$script shellcheck SKIPPED ⚠️"
          fi
        else
          # script is not skipped, let's shellcheck it
          if shellcheck_script "${script}"; then
            say "$script shellcheck PASSED ✅"
          else
            say "$script shellcheck FAILED ❌"
            exit_code=1
          fi
        fi
    done
    # Check that shellcheck_skips doesn't contain a deprecated value
    for shellcheck_skip in ${shellcheck_skips}; do
        if [[ ! -e "${shellcheck_skip}" ]]; then
          say "$shellcheck_skip is mentioned in shellcheck_skips, but doesn't exist anymore"
          say "please delete it from shellcheck_skips"
          exit_code=1
        fi
    done
    # Done executing shellcheck

    exit $exit_code
}

check_redirects () {
    if [[ ! -f docs/_build/_redirects ]]; then
       say "check-redirects should be run after building the full documentation,"
       say "i.e. by running 'make -C docs all'"
       exit 1
    fi

    exit_code=0
    while read -r old new code; do
        re='^[0-9]+$'
        if ! [[ $code =~ $re && $code -ge 300 ]] ; then
            say "in docs/_redirects: redirect $old -> $new has erroneous status code \"$code\""
            exit_code=1
        fi
        dest_local=docs/_build${new}
        if [[ ! -f $dest_local ]]; then
            say "in docs/_redirects: redirect $old -> $new, $dest_local does not exist"
            exit_code=1
        fi
    done < docs/_build/_redirects
    exit $exit_code
}

update_gitlab_ci_yml () {
    # Check that a rule is not defined twice, which would result in the first
    # one being ignored. Gitlab linter doesn't warn for it

    repeated=$(find .gitlab-ci.yml .gitlab/ci/ -iname \*.yml -exec grep '^[^ #-]' \{\} \;  \
                   | sort \
                   | uniq --repeated)
    if [ -n "$repeated" ]; then
        echo ".gitlab-ci.yml contains repeated rules:"
        echo "$repeated"
        exit 1
    fi
}

if [ $# -eq 0 ] || [[ "$1" != --* ]]; then
    say "provide one action (see --help)"
    exit 1
else
    action="$1"
    shift
fi

check_clean=false
commit=
on_files=false

case "$action" in
    "--update-ocamlformat" )
        action=update_all_dot_ocamlformats
        commit="Update .ocamlformat files" ;;
    "--check-ocamlformat" )
        action=update_all_dot_ocamlformats
        check_clean=true ;;
    "--check-gitlab-ci-yml" )
        action=update_gitlab_ci_yml
        check_clean=true ;;
    "--check-scripts" )
        action=check_scripts ;;
    "--check-redirects" )
        action=check_redirects ;;
    "help" | "-help" | "--help" | "-h" )
        usage
        exit 0 ;;
    * )
        say "Error no action (arg 1 = '$action') provided"
        usage
        exit 2 ;;
esac

if $on_files; then
    declare -a input_files files ignored_files
    input_files=()
    while [ $# -gt 0 ]; do
        if [ "$1" = "--ignore" ]; then
            shift
            break
        fi
        input_files+=("$1")
        shift
    done

    if [ ${#input_files[@]} -eq 0 ]; then
        mapfile -t input_files <<< "$(find "${source_directories[@]}" \( -name "*.ml" -o -name "*.mli" -o -name "*.mlt" \) -type f -print)"
    fi

    ignored_files=("$@")

    # $input_files may contain `*.pp.ml{i}` files which can't be linted. They
    # are filtered by the following loop.
    #
    # Note: another option would be to filter them before calling the script
    # but it was more convenient to do it here.
    files=()
    for file in "${input_files[@]}"; do
        if [[ "$file" == *.pp.ml?(i) ]]; then continue; fi
        for ignored_file in "${ignored_files[@]}"; do
            if [[ "$file" =~ ^(.*/)?"$ignored_file"$ ]] ; then continue 2; fi
        done
        files+=("$file")
    done
    $action "${files[@]}"
else
    if [ $# -gt 0 ]; then usage; exit 1; fi
    $action
fi

if [ -n "$commit" ]; then
    git commit -m "$commit"
fi

if $check_clean; then
    echo "Files that differ but that shouldn't:"
    git diff --name-only HEAD --exit-code
    echo "(none, everything looks good)"
fi
