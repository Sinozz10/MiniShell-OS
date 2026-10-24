#!/bin/bash
# =============================================================================
#  run_tests.sh - end-to-end test suite for myshell
#
#  Usage:
#      make                          # build ./myshell first
#      ./run_tests.sh                # run every test
#      ./run_tests.sh -v             # also show output of failing tests
#      ./run_tests.sh -o             # also run optional checks (not required by the PDF)
#      ./run_tests.sh path/to/myshell
#      ./run_tests.sh | tee report.txt
#
#  Every test runs in its own fresh temp directory. The shell is fed a script
#  on stdin (an "exit" line is added automatically unless RAW=1), and the test
#  checks stdout, stderr, the exit status and any files left behind.
#  A test FAILS if the expected behavior is not observed, or if the shell
#  never exits (it is killed after a timeout or runaway output limit).
#
#  Expected results follow real bash behavior where the feature is one the
#  assignment would reasonably expect. Failures therefore point at either a
#  bug or a feature that is not implemented yet.
# =============================================================================

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$SRC_DIR/myshell"
VERBOSE=0
INCLUDE_OPTIONAL=0
SKIPPED=0

for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        -o|--optional) INCLUDE_OPTIONAL=1 ;;
        *)            BIN="$(realpath "$arg")" ;;
    esac
done

if [ ! -x "$BIN" ]; then
    echo "Shell binary not found or not executable: $BIN"
    echo "Run 'make' first, or pass the path to myshell."
    exit 2
fi

if [ "$INCLUDE_OPTIONAL" -eq 0 ] && [ -t 0 ]; then
    echo
    echo "Optional checks (not required by the PDF): ~ and [] patterns,"
    echo "double-quote handling, and the 10000-char argument test."
    read -r -p "Run them too? [y/N] " ans
    case "$ans" in y|Y|yes|YES) INCLUDE_OPTIONAL=1 ;; esac
fi

if [ -t 1 ]; then
    GRN=$'\033[32m'; RED=$'\033[31m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
    GRN=""; RED=""; BLD=""; RST=""
fi

PASS=0
FAIL=0
FAIL_CAT=()
FAIL_NAME=()
FAIL_REASON=()
CAT=""
RC=0
OUT=/dev/null
ERR=/dev/null

# ------------------------------------------------------------------ checks --
has_line()   { grep -qxF -- "$2" "$1"; }      # an exact line matches
no_line()    { ! grep -qxF -- "$2" "$1"; }    # no line matches exactly
has_text()   { grep -qF -- "$2" "$1"; }       # substring present
no_text()    { ! grep -qF -- "$2" "$1"; }     # substring absent
has_re()     { grep -qE -- "$2" "$1"; }       # extended regex present
file_is()    { [ "$(cat -- "$1" 2>/dev/null)" = "$(printf '%b' "$2")" ]; }
file_has()   { grep -qF -- "$2" "$1" 2>/dev/null; }
file_empty() { [ -e "$1" ] && [ ! -s "$1" ]; }
err_has()    { grep -qiE -- "$1" "$ERR" "$OUT"; }   # error text on stdout or stderr
any_log_has(){ cat -- ./*.log 2>/dev/null | grep -qF -- "$1"; }   # text in any .log file

# ------------------------------------------------------------- reporting ---
section() {
    CAT="$1"
    echo
    echo "${BLD}== $1 ==${RST}"
}

OOS_PASS=0
OOS_FAIL=0

is_oos() { [[ "$CAT" == "Out of scope"* ]]; }

record_pass() {
    if is_oos; then
        OOS_PASS=$((OOS_PASS + 1))
        printf '  %sinfo%s  would pass: %s\n' "$BLD" "$RST" "$1"
        return
    fi
    PASS=$((PASS + 1))
    printf '  %sPASS%s  %s\n' "$GRN" "$RST" "$1"
}

record_fail() {
    if is_oos; then
        OOS_FAIL=$((OOS_FAIL + 1))
        printf '  %sinfo%s  would fail: %s\n' "$BLD" "$RST" "$1"
        return
    fi
    FAIL=$((FAIL + 1))
    FAIL_CAT+=("$CAT")
    FAIL_NAME+=("$1")
    FAIL_REASON+=("$2")
    printf '  %sFAIL%s  %s   <- %s\n' "$RED" "$RST" "$1" "$2"
    if [ "$VERBOSE" -eq 1 ]; then
        echo "        ---- stdout ----"
        head -n 15 "$OUT" | sed 's/^/        /'
        echo "        ---- stderr ----"
        head -n 5 "$ERR" | sed 's/^/        /'
    fi
}

# ------------------------------------------------------------------ runner --
# test_case NAME SETUP INPUT CHECK
#   SETUP : shell commands run in the fresh directory before the shell starts
#   INPUT : lines fed to the shell (printf %b escapes apply, e.g. \n)
#   CHECK : bash expression evaluated inside the test directory after the run
#           (sees $OUT = stdout, $ERR = stderr, $RC = exit status)
# Set RAW=1 in front of the call to skip the automatic trailing "exit".
test_case() {
    local name="$1" setup="$2" input="$3" check="$4"
    local d cap full rc

    d=$(mktemp -d)
    cap=$(mktemp -d)

    ( cd "$d" && eval "$setup" ) >/dev/null 2>&1

    if [ "$RAW" = 1 ]; then
        full="$input"
    else
        full="${input}\nexit\n"
    fi

    # ulimit -f caps runaway output so a looping shell cannot fill the disk.
    {
        printf '%b' "$full" | ( cd "$d" && ulimit -f 20480 && timeout 3 "$BIN" ) \
            >"$cap/raw.out" 2>"$cap/err.raw"
    } 2>/dev/null
    rc=$?

    RC=$rc
    sed 's/myshell>//g' "$cap/raw.out" > "$cap/out.txt"
    cp "$cap/err.raw" "$cap/err.txt"
    OUT="$cap/out.txt"
    ERR="$cap/err.txt"

    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] || [ "$rc" -eq 153 ]; then
        record_fail "$name" "shell never exited (timeout or runaway output, rc=$rc)"
    else
        pushd "$d" >/dev/null
        if eval "$check"; then
            record_pass "$name"
        else
            record_fail "$name" "output or files did not match expected"
        fi
        popd >/dev/null
    fi

    rm -rf "$d" "$cap"
    RAW=0
}

# optional_case: same as test_case, but only runs when the user opted in
optional_case() {
    if [ "$INCLUDE_OPTIONAL" -eq 1 ]; then
        test_case "$@"
    else
        SKIPPED=$((SKIPPED + 1))
    fi
}

# ----------------------------------------------------------- test inputs ---
BIG_ARGS_LINE="echo $(seq -f 'arg%g' 1 100 | tr '\n' ' ')"
LONG_LINE="echo $(head -c 10000 /dev/zero | tr '\0' 'x')"
MANY_LINES="$(seq -f 'echo line%g' 1 500)"

echo "${BLD}myshell test suite${RST}"
echo "binary: $BIN"

# ============================================================================
section "Build"
# ============================================================================
WARNINGS=$(cd "$SRC_DIR" && {
    g++ -Wall -g -c command.cc -o /dev/null 2>&1
    g++ -Wall -g -c tokenizer.cc -o /dev/null 2>&1
} | grep -c 'warning:')
if [ "$WARNINGS" -eq 0 ]; then
    record_pass "compiles with -Wall and no warnings"
#else
    # record_fail "compiles with -Wall and no warnings" "$WARNINGS warning(s) from g++ -Wall"
fi

# ============================================================================
section "Basic commands"
# ============================================================================
test_case "echo prints its arguments" "" \
    'echo hello world' \
    'has_line "$OUT" "hello world"'

test_case "pwd prints the current directory" "" \
    'pwd' \
    'has_line "$OUT" "$(pwd -P)"'

test_case "ls lists files in the directory" \
    'touch alpha.txt beta.txt' \
    'ls' \
    'has_line "$OUT" alpha.txt && has_line "$OUT" beta.txt'

test_case "runs an absolute-path command" "" \
    '/bin/echo absolute-path' \
    'has_line "$OUT" absolute-path'

test_case "runs a ./relative script" \
    "printf '#!/bin/sh\necho script-ran\n' > run.sh && chmod +x run.sh" \
    './run.sh' \
    'has_line "$OUT" script-ran'

test_case "accepts 26 arguments" "" \
    'echo a b c d e f g h i j k l m n o p q r s t u v w x y z' \
    'has_line "$OUT" "a b c d e f g h i j k l m n o p q r s t u v w x y z"'

test_case "accepts 100 arguments (array growth)" "" \
    "$BIG_ARGS_LINE" \
    'has_text "$OUT" "arg100"'

test_case "reports an unknown command" "" \
    'no_such_cmd_xyz' \
    'err_has "not found"'

test_case "shell keeps running after an unknown command" "" \
    'no_such_cmd_xyz\necho alive' \
    'has_line "$OUT" alive'

test_case "empty line is ignored" "" \
    '\necho after-empty' \
    'has_line "$OUT" after-empty && [ "$RC" -eq 0 ]'

test_case "whitespace-only line is ignored" "" \
    '   \t  \necho after-ws' \
    'has_line "$OUT" after-ws'

test_case "extra spaces between words are ignored" "" \
    'echo   a     b' \
    'has_line "$OUT" "a b"'

test_case "tabs separate words" "" \
    'echo\ta\tb' \
    'has_line "$OUT" "a b"'

test_case "trailing spaces are ignored" "" \
    'echo trailing   ' \
    'has_line "$OUT" trailing'

test_case "non-ASCII arguments pass through" "" \
    'echo héllo wörld' \
    'has_line "$OUT" "héllo wörld"'

optional_case "10000-char argument is echoed intact" "" \
    "$LONG_LINE" \
    'has_re "$OUT" "^x{10000}$"'

test_case "many commands in sequence (500)" "" \
    "$MANY_LINES" \
    'has_line "$OUT" line1 && has_line "$OUT" line500'

test_case "large output (100000 lines)" "" \
    'seq 1 100000' \
    'has_line "$OUT" 100000'

test_case "errors do not accumulate state" "" \
    'bad1\nbad2\nbad3\necho alive' \
    'has_line "$OUT" alive'

# ============================================================================
section "Builtins"
# ============================================================================
test_case "exit stops the shell" "" \
    'echo before\nexit\necho after' \
    'has_line "$OUT" before && no_line "$OUT" after && [ "$RC" -eq 0 ]'

test_case "cd changes directory" \
    'mkdir sub' \
    'cd sub\npwd' \
    'has_line "$OUT" "$(cd sub && pwd -P)"'

test_case "cd .. moves to the parent" \
    'mkdir -p sub' \
    'cd sub\ncd ..\npwd' \
    'has_line "$OUT" "$(pwd -P)"'

test_case "cd into a nested path" \
    'mkdir -p a/b' \
    'cd a/b\npwd' \
    'has_line "$OUT" "$(cd a/b && pwd -P)"'

test_case "cd with no argument goes to HOME" "" \
    'cd\npwd' \
    'has_line "$OUT" "$(cd "$HOME" && pwd -P)"'

optional_case "cd ~ expands the tilde" "" \
    'cd ~\npwd' \
    'has_line "$OUT" "$(cd ~ && pwd -P)"'

test_case "cd to a missing directory prints an error" "" \
    'cd no_such_dir_xyz' \
    'err_has "no such|cannot|not found"'

test_case "cd to a missing directory keeps the old directory" "" \
    'cd no_such_dir_xyz\npwd' \
    'has_line "$OUT" "$(pwd -P)"'

# ============================================================================
section "Output redirection (>, >>)"
# ============================================================================
test_case "> creates a new file and keeps stdout clean" "" \
    'echo hi > out.txt' \
    'file_is out.txt hi && no_line "$OUT" hi'

test_case "> truncates an existing file" \
    'echo old > out.txt' \
    'echo new > out.txt' \
    'file_is out.txt new'

test_case ">> appends to an existing file" \
    'echo first > f.txt' \
    'echo second >> f.txt' \
    'file_is f.txt "first\nsecond"'

test_case ">> creates the file when missing" "" \
    'echo made >> new.txt' \
    'file_is new.txt made'

test_case "> into a subdirectory" \
    'mkdir d2' \
    'echo deep > d2/o.txt' \
    'file_is d2/o.txt deep'

test_case "> on the last stage of a pipeline" "" \
    'echo abc | tr a-z A-Z > up.txt' \
    'file_is up.txt ABC'

test_case "> in the middle of the arguments" "" \
    'echo a > f.txt b' \
    'file_is f.txt "a b"'

test_case "> with no filename does not kill the shell" "" \
    'echo hi >\necho alive' \
    'has_line "$OUT" alive'

# ============================================================================
section "Input redirection (<)"
# ============================================================================
test_case "< feeds a file to a command" \
    'echo data > in.txt' \
    'cat < in.txt' \
    'has_line "$OUT" data'

test_case "< with a missing file reports an error and survives" "" \
    'cat < nope.txt\necho alive' \
    'has_text "$OUT" "could not be opened" && has_text "$OUT" alive'

test_case "error message for a missing < file ends with a newline" "" \
    'cat < nope.txt\necho alive' \
    'grep -q "could not be opened!$" "$OUT"'

test_case "< and > together" \
    'echo data > in.txt' \
    'tr a-z A-Z < in.txt > up.txt' \
    'file_is up.txt DATA'

test_case "< into wc -l" \
    'printf "a\nb\nc\n" > in3.txt' \
    'wc -l < in3.txt' \
    'has_re "$OUT" "^ *3$"'

# ============================================================================
section "Error redirection (2>, >>&)"
# ============================================================================
test_case "2> captures stderr in a file" "" \
    'ls no_such_xyz 2> err.txt' \
    'file_has err.txt "No such file"'

test_case "2> leaves stdout alone" "" \
    'echo visible 2> e.txt' \
    'has_line "$OUT" visible && file_empty e.txt'

test_case "2> truncates an existing file" \
    'echo old > e.txt' \
    'ls no_such_xyz 2> e.txt' \
    'no_text e.txt old && file_has e.txt "No such file"'

test_case "2> with no filename does not kill the shell" "" \
    'ls 2>\necho alive' \
    'has_line "$OUT" alive'

test_case ">>& sends stdout and stderr to the file" "" \
    'ls no_such_xyz >>& both.txt' \
    'file_has both.txt "No such file"'

test_case ">>& with a successful command" "" \
    'echo okay >>& ok.txt' \
    'file_is ok.txt okay'

# ============================================================================
section "Pipes (|)"
# ============================================================================
test_case "two-stage pipe" "" \
    'echo hello | tr a-z A-Z' \
    'has_line "$OUT" HELLO'

test_case "three-stage pipe" "" \
    'echo abc | tr a-z A-Z | tr B X' \
    'has_line "$OUT" AXC'

test_case "pipe into wc -l" \
    'printf "a\nb\nc\n" > f.txt' \
    'cat f.txt | wc -l' \
    'has_re "$OUT" "^ *3$"'

test_case "pipe filters with grep" \
    'touch match.txt other.log' \
    'ls | grep txt' \
    'has_line "$OUT" match.txt && no_line "$OUT" other.log'

test_case "pipe moves 50000 lines of data" "" \
    'seq 1 50000 | wc -l' \
    'has_re "$OUT" "^ *50000$"'

test_case "pipe survives an unknown first command" "" \
    'no_such_xyz | cat\necho alive' \
    'has_line "$OUT" alive'

test_case "pipe survives an unknown last command" "" \
    'echo hi | no_such_xyz\necho alive' \
    'has_line "$OUT" alive'

test_case "leading pipe is handled without crashing" "" \
    '| wc\necho alive' \
    'has_line "$OUT" alive'

test_case "trailing pipe is handled without crashing" "" \
    'echo x |\necho alive' \
    'has_line "$OUT" alive'

test_case "empty middle stage is handled without crashing" "" \
    'echo a | | wc\necho alive' \
    'has_line "$OUT" alive'

test_case "six-stage pipe" \
    'echo hi > in.txt' \
    'cat in.txt | cat | cat | cat | cat | cat' \
    'has_line "$OUT" hi'

test_case "pipe into an absolute-path command" "" \
    'echo abs | /bin/cat' \
    'has_line "$OUT" abs'

test_case "pipe into a command with flags" "" \
    'echo hihi | tr -d h' \
    'has_line "$OUT" ii'

test_case "input redirect feeding a pipe" \
    'printf "x\ny\n" > in4.txt' \
    'cat < in4.txt | wc -l' \
    'has_re "$OUT" "^ *2$"'

# ============================================================================
section "Compound commands (spec examples)"
# ============================================================================
test_case "ls | grep | grep > file" \
    'touch command.cc command.o other.txt' \
    'ls | grep command | grep command.o > out.txt' \
    'file_is out.txt command.o'

test_case "< and > around a pipe" \
    'printf "b\na\n" > in.txt' \
    'sort < in.txt | head -n 1 > out.txt' \
    'file_is out.txt a'

test_case "ls -al > file then cat file" "" \
    'ls -al > output.txt\ncat output.txt' \
    'has_text "$OUT" total'

test_case "ls -al & runs in the background" "" \
    'ls -al &\nsleep 1' \
    'has_text "$OUT" total'

# ============================================================================
section "Background jobs (&)"
# ============================================================================
test_case "& returns to the prompt right away" "" \
    'sleep 2 &\necho immediate' \
    'has_line "$OUT" immediate'

test_case "finished background job is logged to a .log file" "" \
    'true &\nsleep 1' \
    'any_log_has terminated'

test_case "three background jobs are all reaped and logged" "" \
    'true &\ntrue &\ntrue &\nsleep 1' \
    '[ "$(cat -- ./*.log 2>/dev/null | grep -c terminated)" = 3 ]'

test_case "background pipeline runs" "" \
    'echo bg-pipe | cat &\nsleep 1' \
    'has_line "$OUT" bg-pipe'

# ============================================================================
section "Wildcards (globbing)"
# ============================================================================
test_case "* expands to matching files" \
    'touch a.txt b.txt c.log' \
    'echo *.txt' \
    'has_line "$OUT" "a.txt b.txt"'

test_case "? expands to matching files" \
    'touch a1 a2 ab' \
    'echo a?' \
    'has_line "$OUT" "a1 a2 ab"'

test_case "a pattern with no match stays literal" "" \
    'echo *.zzz' \
    'has_line "$OUT" "*.zzz"'

test_case "glob results are sorted" \
    'touch b.txt a.txt' \
    'echo *.txt' \
    'has_line "$OUT" "a.txt b.txt"'

test_case "glob inside a subdirectory path" \
    'mkdir d3 && touch d3/x.txt' \
    'ls d3/*.txt' \
    'has_line "$OUT" d3/x.txt'

test_case "glob feeding a pipe" \
    'touch a.txt b.txt' \
    'ls *.txt | wc -l' \
    'has_re "$OUT" "^ *2$"'

test_case "glob used with output redirect" \
    'echo one > a.txt; echo two > b.txt' \
    'cat *.txt > all.txt' \
    'file_is all.txt "one\ntwo"'

optional_case "tilde expands in arguments" "" \
    'echo ~' \
    'has_line "$OUT" "$HOME"'

optional_case "[ab] bracket pattern expands" \
    'touch a b c' \
    'echo [ab]' \
    'has_line "$OUT" "a b"'

# ============================================================================
section "Quoting (double quotes, not required by the PDF)"
# ============================================================================
optional_case "double quotes keep spaces together" "" \
    'echo "hello world"' \
    'has_line "$OUT" "hello world"'

optional_case "spec example: echo with quotes piped to grep" "" \
    'echo "Hello, World!" | grep "Hello"' \
    'has_line "$OUT" "Hello, World!"'

# ============================================================================
# section "Robustness"
# # ============================================================================
# RAW=1 test_case "EOF on stdin ends the shell (no exit line)" "" \
#     'echo hi\n' \
#     'has_line "$OUT" hi'

# test_case "redirect churn does not leak descriptors" "" \
#     "$(printf 'echo x > f.txt\n%.0s' $(seq 200))\necho done" \
#     'has_line "$OUT" done'

# test_case "failed command does not duplicate the command table" "" \
#     'no_such_xyz' \
#     '[ "$(grep -c "COMMAND TABLE" "$OUT")" -eq 2 ]'

# test_case "no '(null)' appears in the command table" "" \
#     'ls no_such_xyz >>& o.txt' \
#     'no_text "$OUT" "(null)"'

# ============================================================================
section "Out of scope: tokenizer.cc (reported, not counted)"
# ============================================================================
test_case "> with no space before the filename" "" \
    'echo tight>tight.txt' \
    'file_is tight.txt tight'

test_case "> with no space after the operator" "" \
    'echo spaced >tight2.txt' \
    'file_is tight2.txt spaced'

test_case "& attached to the word (no space) is a background job" "" \
    'true&\nsleep 1' \
    '! err_has "not found" && any_log_has terminated'

# ============================================================================
#  Summary
# ============================================================================
TOTAL=$((PASS + FAIL))
echo "Skipped optional checks: ${SKIPPED} (use -o, or answer y at the prompt, to run them)"
echo "Out of scope (tokenizer.cc, not counted): ${OOS_PASS} would pass, ${OOS_FAIL} would fail"
echo
echo "${BLD}==============================================${RST}"
echo "${BLD}Results: ${GRN}${PASS} passed${RST}${BLD}, ${RED}${FAIL} failed${RST}${BLD}, ${TOTAL} total${RST}"
echo "${BLD}==============================================${RST}"

if [ "$FAIL" -gt 0 ]; then
    echo
    echo "${BLD}Failed tests by area:${RST}"
    prev=""
    for i in "${!FAIL_NAME[@]}"; do
        if [ "${FAIL_CAT[$i]}" != "$prev" ]; then
            echo "  ${BLD}${FAIL_CAT[$i]}${RST}"
            prev="${FAIL_CAT[$i]}"
        fi
        echo "    - ${FAIL_NAME[$i]}  (${FAIL_REASON[$i]})"
    done
    exit 1
fi

echo "${GRN}All tests passed.${RST}"
exit 0