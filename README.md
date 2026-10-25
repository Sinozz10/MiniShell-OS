# Minishell - Operating Systems Lab 3

A custom, fully functional Unix shell implemented in C++ from scratch. This project demonstrates core operating system concepts including process creation, pipe communication, file descriptor manipulation, standard I/O redirection, and signal handling.

## Features Implemented

*   **Command Execution:** Executes standard Unix commands (e.g., `ls`, `grep`, `echo`) using `fork()` and `execvp()`.
*   **Piping (`|`):** Supports multi-stage pipelines, seamlessly passing the `stdout` of one command to the `stdin` of the next (e.g., `ls -al | grep .cc | wc -l`). Includes safety checks to prevent core dumps on empty pipe segments.
*   **I/O Redirection:**
    *   `<` : Redirect standard input from a file.
    *   `>` : Redirect standard output to a file (overwrite).
    *   `>>` : Redirect standard output to a file (append).
    *   `2>` : Redirect standard error to a file.
    *   `>>&` : Redirect both standard output and standard error to a file.
*   **Background Processing (`&`):** Executes jobs in the background without blocking the shell's prompt. 
*   **Zombie Process Reaping:** Implements a `SIGCHLD` signal handler to asynchronously reap terminated background child processes and log their termination to `myshell.log`.
*   **Signal Handling:** Overrides default terminal signals, specifically ignoring `SIGINT` (Ctrl+C) to prevent accidental shell termination.
*   **Wildcard Expansion (Globbing):** Evaluates `*` and `?` wildcards dynamically before passing arguments to `execvp`.
*   **Built-in Commands:**
    *   `cd [directory]` : Changes the current working directory. Defaults to `$HOME` if no arguments are provided.
    *   `exit` : Safely terminates the shell.
*   **Quotation Handling:** Cleans and parses string arguments encased in double-quotes (`""`) to accurately pass data to processes.

## Project Structure

*   `command.cc` / `command.h`: The core engine of the shell. Contains the `SimpleCommand` and `Command` classes responsible for mapping file descriptors, executing processes, routing pipes, handling signals, and evaluating built-ins.
*   `tokenizer.cc` / `tokenizer.h`: The lexical scanner that parses raw user input strings and categorizes them into actionable tokens (`TOKEN_COMMAND`, `TOKEN_PIPE`, `TOKEN_REDIRECT`, etc.).
*   `Makefile`: The build automation script to easily compile the source files into the final executable.
*   `run_tests.sh`: An automated bash testing script that verifies the shell's adherence to the lab requirements.

## Prerequisites & Compilation

This project requires a standard Linux environment (like Ubuntu) with the GCC/G++ compiler installed.

To compile the shell, simply run the following command in the project directory:
```bash
make
```
To clean up object files and existing logs, run:
```bash
make clean
```

## Usage

Start the shell by executing the compiled binary:
```bash
./myshell
```

### Example Commands:
```bash
myshell> ls -al > output.txt
myshell> cat < output.txt | grep "myshell"
myshell> echo "Hello, World!" | grep "Hello"
myshell> sleep 5 &
myshell> cd /tmp
myshell> exit
```

## Automated Testing

This repository includes a testing script (`run_tests.sh`) to evaluate the shell against 80 rigorous edge-case and functional tests. 

To run the test suite with verbose output:
```bash
./run_tests.sh -v
```

## Author
**Student ID:** 9610
**Course:** Operating Systems
