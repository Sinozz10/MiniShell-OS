
/*
 * 
 *
 * Template file.
 * You will need to add more code here to execute the command table.
 *
 * NOTE: You are responsible for fixing any bugs this code may have!
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <string.h>
#include <signal.h>
#include <fcntl.h>
#include <time.h>
#include <glob.h>
#include <wordexp.h>
#include <vector>
#include <string>
#include <cctype>
#include <iostream>
#include <sstream>
#include <cerrno>
#include "command.h"
#include "tokenizer.h"
#include <algorithm>

// reap background zombie processes so they don't pile up
void zombie_handler(int sig)
{
    int saved_errno = errno;
    int pid;

    // wait for any child without blocking
    while ((pid = waitpid(-1, NULL, WNOHANG)) > 0)
    {
        int log_fd = open("log.txt", O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (log_fd >= 0){
            char msg[256];
            int len = snprintf(msg, sizeof(msg), "Child process %d terminated\n", pid);
            write(log_fd, msg, len);
            close(log_fd);
        }
    }
    errno = saved_errno;
}


void parse(std::vector<Token> &tokens)
{
    SimpleCommand *curr_cmd = new SimpleCommand();
    
    // flags for redirection state machine
    bool redir_out = false;
    bool redir_in = false;
    bool redir_err = false;
    bool redir_app = false;
    bool redir_both = false;

    for (const auto &tok : tokens){
        // printf("parsing: %s\n", tok.value.c_str()); // debug

        switch (tok.type){
            case TOKEN_EOF:
                if (curr_cmd->_numberOfArguments > 0) {
                    Command::_currentCommand.insertSimpleCommand(curr_cmd);
                } else {
                    delete curr_cmd;
                }
                break;
                
            case TOKEN_COMMAND:
            case TOKEN_ARGUMENT:
                if (redir_out){
                    Command::_currentCommand._outFile = strdup(tok.value.c_str());
                    redir_out = false;
                }else if (redir_in){
                    Command::_currentCommand._inputFile = strdup(tok.value.c_str());
                    redir_in = false;
                }else if (redir_err){
                    Command::_currentCommand._errFile = strdup(tok.value.c_str());
                    redir_err = false;
                }else if (redir_app){
                    Command::_currentCommand._outFile = strdup(tok.value.c_str());
                    Command::_currentCommand._append = 1;
                    redir_app = false;
                }else if (redir_both){
                    Command::_currentCommand._outFile = strdup(tok.value.c_str());
                    Command::_currentCommand._errFile = strdup(tok.value.c_str());
                    Command::_currentCommand._out_error = 1;
                    redir_both = false;
                }else{
                    // strip quotes if the user typed them
                    std::string clean_str = tok.value;
                    clean_str.erase(std::remove(clean_str.begin(), clean_str.end(), '\"'), clean_str.end());

                    // handle wildcards with the clean string
                    if (clean_str.find('*') != std::string::npos || clean_str.find('?') != std::string::npos){
                        glob_t res;
                        if (glob(clean_str.c_str(), GLOB_NOCHECK | GLOB_TILDE, NULL, &res) == 0){
                            for (size_t i = 0; i < res.gl_pathc; ++i){
                                curr_cmd->insertArgument(strdup(res.gl_pathv[i]));
                            }
                        }else{
                            curr_cmd->insertArgument(strdup(clean_str.c_str()));
                        }
                        globfree(&res);
                    }else{
                        curr_cmd->insertArgument(strdup(clean_str.c_str()));
                    }
                }
                break;

            case TOKEN_PIPE:
                Command::_currentCommand.insertSimpleCommand(curr_cmd);
                curr_cmd = new SimpleCommand();
                break;
            case TOKEN_REDIRECT:
                redir_out = true;
                break;
            case TOKEN_APPEND:
                redir_app = true;
                break;
            case TOKEN_INPUT:
                redir_in = true;
                break;
            case TOKEN_ERROR:
                redir_err = true;
                break;
            case TOKEN_REDIRECT_AND_ERROR:
                redir_both = true;
                break;
            case TOKEN_BACKGROUND:
                Command::_currentCommand._background = 1;
                break;
            default:
                break;
        }
    }
    
    if (Command::_currentCommand._numberOfSimpleCommands > 0){
        Command::_currentCommand.execute();
    }
}

SimpleCommand::SimpleCommand()
{
    _numberOfAvailableArguments = 5;
    _numberOfArguments = 0;
    _arguments = (char **)malloc(_numberOfAvailableArguments * sizeof(char *));
}

void SimpleCommand::insertArgument(char *argument)
{
    if (_numberOfAvailableArguments == _numberOfArguments + 1)
    {
        _numberOfAvailableArguments *= 2;
        _arguments = (char **)realloc(_arguments, _numberOfAvailableArguments * sizeof(char *));
    }

    _arguments[_numberOfArguments] = argument;
    _arguments[_numberOfArguments + 1] = NULL;
    _numberOfArguments++;
}

Command::Command()
{
    _numberOfAvailableSimpleCommands = 1;
    
    _simpleCommands = (SimpleCommand **)
        malloc(_numberOfAvailableSimpleCommands * sizeof(SimpleCommand *));

    _numberOfSimpleCommands = 0;
    _outFile = 0;
    _inputFile = 0;
    _errFile = 0;
    _append = 0;
    _background = 0;
    _out_error = 0;
}

void Command::insertSimpleCommand(SimpleCommand *simpleCommand)
{
    if (_numberOfAvailableSimpleCommands == _numberOfSimpleCommands)
    {
        _numberOfAvailableSimpleCommands *= 2;
        _simpleCommands = (SimpleCommand **)realloc(_simpleCommands,
                                                    _numberOfAvailableSimpleCommands * sizeof(SimpleCommand *));
    }

    _simpleCommands[_numberOfSimpleCommands] = simpleCommand;
    _numberOfSimpleCommands++;
}

void Command::clear()
{
    for (int i = 0; i < _numberOfSimpleCommands; i++)
    {
        for (int j = 0; j < _simpleCommands[i]->_numberOfArguments; j++)
        {
            free(_simpleCommands[i]->_arguments[j]);
        }
        free(_simpleCommands[i]->_arguments);
        free(_simpleCommands[i]);
    }

    if (_outFile) free(_outFile);
    if (_inputFile) free(_inputFile);
    if (_errFile) free(_errFile);

    _numberOfSimpleCommands = 0;
    _outFile = 0;
    _inputFile = 0;
    _errFile = 0;
    _out_error = 0;
    _append = 0;
    _background = 0;
}

void Command::print()
{
    printf("\n\n");
    printf("              COMMAND TABLE                \n");
    printf("\n");
    printf("  #   Simple Commands\n");
    printf("  --- ----------------------------------------------------------\n");

    for (int i = 0; i < _numberOfSimpleCommands; i++)
    {
        printf("  %-3d ", i);
        for (int j = 0; j < _simpleCommands[i]->_numberOfArguments; j++)
        {
            printf("\"%s\" \t", _simpleCommands[i]->_arguments[j]);
        }
    }

    printf("\n\n");
    printf("  Output       Input        Error        Err&Out       Background\n");
    printf("  ------------ ------------ ------------ ------------ ------------\n");
    printf("  %-12s %-12s %-12s %-12s %-12s\n", _outFile ? _outFile : "default",
           _inputFile ? _inputFile : "default", _errFile ? _errFile : "default", _out_error == 1 ? _errFile : "default"
           ,_background ? "YES" : "NO");
    printf("\n\n");
}

void Command::execute()
{
    if (_numberOfSimpleCommands == 0) return;

    print();

    // check built-ins first
    if (strcmp(_simpleCommands[0]->_arguments[0], "exit") == 0)
    {
        printf("Exiting myshell...\n");
        exit(0);
    }
    
    if (strcmp(_simpleCommands[0]->_arguments[0], "cd") == 0)
    {
        const char *dir = _simpleCommands[0]->_numberOfArguments > 1 ? _simpleCommands[0]->_arguments[1] : getenv("HOME");
        if (chdir(dir) < 0) {
            perror("cd error");
        }
        clear();
        return;    
    }

    // backup terminal FDs
    int tmp_in = dup(0);
    int tmp_out = dup(1);
    int tmp_err = dup(2);
    
    int current_in;

    if (_inputFile){
        current_in = open(_inputFile, O_RDONLY);
        if (current_in < 0) {
            perror("failed to open input");
            clear();
            return;
        }
    } else {
        current_in = dup(tmp_in);
    }

    int pid;
    for (int i = 0; i < _numberOfSimpleCommands; i++)
    {
        dup2(current_in, 0);
        close(current_in);

        int current_out;
        
        // last command handles the final output routing
        if (i == _numberOfSimpleCommands - 1)
        {
            if (_outFile){
                int flags = O_WRONLY | O_CREAT | (_append ? O_APPEND : O_TRUNC);
                current_out = open(_outFile, flags, 0666);
                if (current_out < 0) {
                    perror("output file err");
                    clear();
                    exit(1);
                }
            } else {
                current_out = dup(tmp_out);
            }
        } else {
            // setup pipe for next command in chain
            int p_fd[2];
            pipe(p_fd);
            current_out = p_fd[1];
            current_in = p_fd[0];
        }
        
        dup2(current_out, 1);
        close(current_out);

        // handle stderr for the last command
        if (_errFile && (i == _numberOfSimpleCommands - 1)){
            int e_flags = O_WRONLY | O_CREAT | (_out_error ? O_APPEND : O_TRUNC);
            int e_fd = open(_errFile, e_flags, 0666);
            if (e_fd >= 0){
                dup2(e_fd, 2);
                close(e_fd);
            }
        }

        fflush(stdout); // flush stdout before fork to avoid duplicate output (so no collision yhsal with parent and child)
        fflush(stderr); // flush stderr before fork to avoid duplicate output
        pid = fork();
        if (pid == 0){
            execvp(_simpleCommands[i]->_arguments[0], _simpleCommands[i]->_arguments);
            perror("execvp failed");
            exit(1);
        }
    }
    
    // reset IO back to terminal
    dup2(tmp_in, 0);
    dup2(tmp_out, 1);
    dup2(tmp_err, 2);
    close(tmp_in);
    close(tmp_out);
    close(tmp_err);

    if (!_background){
        // wait for the final child process to finish
        waitpid(pid, NULL, 0);
    }
    
    clear();
}

void Command::prompt()
{
    std::string input;
    while (true)
    {
        printf("myshell>");
        fflush(stdout);
        
        // handle Ctrl+D exit gracefully
        if (!std::getline(std::cin, input)) 
        {
            printf("\n");
            break;
        }
        
        if (input.empty()) continue;

        std::vector<Token> tokens = tokenize(input);
        parse(tokens);
    }
}

Command Command::_currentCommand;
SimpleCommand *Command::_currentSimpleCommand;

int main()
{
    signal(SIGINT, SIG_IGN); // bypass ctrl-c 
    
    struct sigaction sa;
    sa.sa_handler = zombie_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    
    if (sigaction(SIGCHLD, &sa, NULL) == -1)
    {
        perror("sigaction");
        exit(1);
    }
    
    Command::_currentCommand.prompt();
    return 0;
}