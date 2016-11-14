
_format_count() {
    if [ ${1} == 1 ]; then
        echo "${1} ${2}"
    else
        echo "${1} ${2}s"
    fi
}

_trim_test_prefix() {
    echo "$1" | sed 's/^test_//'
}

_file_base_name() {
    echo ${1%.*}
}

if [ -z "${RUN_SINGLE_TEST:-""}" ]; then
  TEST_ROOT="test"
  SOURCE_ROOT=${1:-"src"}

  echo ""
  echo "Running Simple Bash Tests"
  echo "-------------------------"
  echo ""

  registry="$(mktemp -d "/tmp/workspace.registry.XXXXXXXX")"
  test_count=0

  for f in $(find ${TEST_ROOT} -name "test_*"); do
    TEST_ROOT_DIR=$PWD/${TEST_ROOT} RUN_SINGLE_TEST=1 $0 ${SOURCE_ROOT} ${f} ${registry} || fail "${f} failed."

    new_tests=$(cat ${registry}/test_count)
    test_count=$((${test_count} + ${new_tests}))
  done

  if [ -f ${registry}/failures_output ]; then
    cat ${registry}/failures_output
  fi
  echo ""
  echo "-------------------------"
  echo "Ran "$(_format_count ${test_count} "test")
  echo ""
  failure_count=$(cat ${registry}/failures_count)
  if [ ${failure_count} -eq 0 ]; then
    echo ">>> SUCCESS <<<"
    echo ""
    exit 0
  else
    echo ">>> FAILURE ("$(_format_count ${failure_count} "error")") <<<"
    echo ""
    exit 1
  fi
fi


SOURCE_ROOT=$1
TEST_FILE=$2
REGISTRY=$3

source ${TEST_FILE} || fail "Unable to read ${TEST_FILE}."

all_functions=$(typeset -F | sed "s/declare -f //")
tests=$(echo "${all_functions}" | grep "^test_" || true)
setup=$(echo "${all_functions}" | grep "^setup$" || true)
teardown=$(echo "${all_functions}" | grep "^teardown" || true)


_setup_workspace() {
    workspace="$(mktemp -d "/tmp/workspace.$(basename ${TEST_FILE}).XXXXXXXX")"
    cp -aR ${SOURCE_ROOT}/* ${workspace}/

    mocks="$(mktemp -d "${workspace}/mocks.XXXXXXXX")"
    original_path=${PATH}
    export PATH="$mocks:${PATH}"
}


_cleanup() {
    if [ -n ${teardown} ]; then
        ${teardown}
    fi

    export PATH="${original_path}"
    expectation_failure=$(cat ${workspace}/expectation_failure 2>/dev/null || true)

    rm -rf ${workspace}

    if [ -n "${expectation_failure}" ]; then
        echo "FAILURE : ${expectation_failure}"
        exit 1
    fi
}

trap _cleanup INT TERM EXIT

test_count=0
failures=0

assertion_failed() {
    touch ${workspace}/.assertion_error
    echo -e "$1"
    return 1
}

for test in ${tests}; do
    _setup_workspace

    pushd ${workspace} >/dev/null

    if [ -n ${setup} ]; then
        ${setup}
    fi

    test_name=$(_trim_test_prefix $(_file_base_name $(basename ${TEST_FILE}))).$(_trim_test_prefix ${test})
    printf ${test_name}...

    failed=0

    ${test} > ${workspace}/test_output || true

    if [ ! -f ${workspace}/.assertion_error ]; then
        echo "OK"
    else
        echo "FAILED"
        failures=$((${failures} + 1))
        cat >> ${REGISTRY}/failures_output <<FAILURE

=========================
FAIL: ${test_name}
-------------------------
$(cat ${workspace}/test_output)
-------------------------
FAILURE

    fi
    test_count=$((${test_count} + 1))

    _cleanup
    popd >/dev/null
done

echo ${test_count} > ${REGISTRY}/test_count
echo ${failures} > ${REGISTRY}/failures_count

trap - INT TERM EXIT
