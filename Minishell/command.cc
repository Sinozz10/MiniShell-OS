
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

//This fn is to handle signal from child proccesses
void signchld_handler(int sig)
{
    int saved_errno = errno;
    int pid;

    while ((pid = waitpid(-1, NULL, WNOHANG)) > 0)
    {
        int logger = open("log.txt", O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (logger >= 0){
            char message[256];
            int len = snprintf(message, sizeof(message), "Child process %d terminated\n", pid);
            write(logger, message, len);
            close(logger);
        }
    }
    errno = saved_errno;
}


void parse(std::vector<Token> &tokens)
{
    SimpleCommand *currentSimpleCommand = new SimpleCommand();
    bool expectout = false, expectin = false, expecterr = false, expectappend = false, expectoutanderr = false;

    for (const auto &token : tokens){
        switch (token.type){
            case TOKEN_EOF:
                if (currentSimpleCommand->_numberOfArguments > 0){
                    Command::_currentCommand.insertSimpleCommand(currentSimpleCommand);
                }else{
                    delete currentSimpleCommand;
                }
                break;
            case TOKEN_COMMAND:
            case TOKEN_ARGUMENT:
                if (expectout){
                    Command::_currentCommand._outFile = strdup(token.value.c_str());
                    expectout = false;
                }else if (expectin){
                    Command::_currentCommand._inputFile = strdup(token.value.c_str());
                    expectin = false;
                }else if (expecterr){
                    Command::_currentCommand._errFile = strdup(token.value.c_str());
                    expecterr = false;
                }else if (expectappend){
                    Command::_currentCommand._outFile = strdup(token.value.c_str());
                    Command::_currentCommand._append = 1;
                    expectappend = false;
                }else if (expectoutanderr){
                    Command::_currentCommand._outFile = strdup(token.value.c_str());
                    Command::_currentCommand._errFile = strdup(token.value.c_str());
                    Command::_currentCommand._out_error = 1;
                    expectoutanderr = false;
                }else{
                    if (token.value.find('*') != std::string::npos || token.value.find('?') != std::string::npos){
                        glob_t result;
                        if (glob(token.value.c_str(), GLOB_NOCHECK | GLOB_TILDE, NULL, &result) == 0){
                            for (size_t i = 0; i < result.gl_pathc; ++i){
                                currentSimpleCommand->insertArgument(strdup(result.gl_pathv[i]));
                            }
                        }else{
                            currentSimpleCommand->insertArgument(strdup(token.value.c_str()));
                        }
                        globfree(&result);
                    }else{
                        currentSimpleCommand->insertArgument(strdup(token.value.c_str()));
                    }
                } // <--- THIS WAS THE MISSING BRACE!
                break;

            case TOKEN_PIPE:
                Command::_currentCommand.insertSimpleCommand(currentSimpleCommand);
                currentSimpleCommand = new SimpleCommand();
                break;
            case TOKEN_REDIRECT:
                expectout = true;
                break;
            case TOKEN_APPEND:
                expectappend = true;
                break;
            case TOKEN_INPUT:
                expectin = true;
                break;
            case TOKEN_ERROR:
                expecterr = true;
                break;
            case TOKEN_REDIRECT_AND_ERROR:
                expectoutanderr = true;
                break;
            case TOKEN_BACKGROUND:
                Command::_currentCommand._background = 1;
                break;
            default:
                break;
        }
    } // Closes the switch statement
    
    // Now safely OUTSIDE the for loop!
    if (Command :: _currentCommand._numberOfSimpleCommands > 0){
        Command:: _currentCommand.execute();
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
        _arguments = (char **)realloc(_arguments,
                                      _numberOfAvailableArguments * sizeof(char *));
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

    if (_outFile)
    {
        free(_outFile);
    }

    if (_inputFile)
    {
        free(_inputFile);
    }

    if (_errFile)
    {
        free(_errFile);
    }

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
    if (_numberOfSimpleCommands == 0)
    {
        return;
    }

    print();

    if (strcmp(_simpleCommands[0]->_arguments[0], "exit") == 0)
    {
        printf("Exiting myshell...\n");
        exit(0);
    }
    
    if (strcmp(_simpleCommands[0]->_arguments[0], "cd") == 0)
    {
        const char *directory = _simpleCommands[0]->_numberOfArguments > 1 ? _simpleCommands[0]->_arguments[1] : getenv("HOME");

        if (chdir(directory) < 0)
        {
            perror("cd");
        }
        clear();
        return;    
    }

    int default_in = dup(0);
    int default_out = dup(1);
    int default_err = dup(2);
    int fdin;


    if (_inputFile){
        fdin = open(_inputFile, O_RDONLY);
        if (fdin < 0)
        {
            perror("failed to open input file");
            clear();
            return;
        }
    }else{
        fdin = dup(default_in);
    }

    int pid;
    for (int i = 0; i < _numberOfSimpleCommands; i++)
    {
        dup2(fdin, 0);
        close(fdin);

        int fdout;
        if (i == _numberOfSimpleCommands - 1)
        {
            if (_outFile){
                int flags = O_WRONLY | O_CREAT | (_append ? O_APPEND : O_TRUNC);
                fdout = open(_outFile, flags, 0666);
                if (fdout < 0)
                {
                    perror("failed to open output file");
                    clear();
                    exit(1);
                }
            }else{
                fdout = dup(default_out);
            }
        }else{
            int pipefd[2];
            pipe(pipefd);
            fdout = pipefd[1];
            fdin = pipefd[0];
        }
        dup2(fdout, 1);
        close(fdout);

        if (_errFile && (i == _numberOfSimpleCommands - 1)){
            int flags = O_WRONLY | O_CREAT | (_out_error ? O_APPEND : O_TRUNC);
            int fderr = open(_errFile, flags, 0666);
            if (fderr >= 0){
                dup2(fderr, 2);
                close(fderr);
        }
        }

        pid = fork();
        if (pid == 0){
            execvp(_simpleCommands[i]->_arguments[0], _simpleCommands[i]->_arguments);
            perror("execvp failed");
            exit(1);
        }
    }
    dup2(default_in, 0);
    dup2(default_out, 1);
    dup2(default_err, 2);
    close(default_in);
    close(default_out);
    close(default_err);

    if (!_background){
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
        if (!std::getline(std::cin, input)) //Handle EOF (Ctrl+D) to exit the shell
        {
            printf("\n");
            break;
        }
        std::vector<Token> tokens = tokenize(input);
        parse(tokens);
    }
}

Command Command::_currentCommand;
SimpleCommand *Command::_currentSimpleCommand;

int main()
{
    signal(SIGINT, SIG_IGN);
    
    signal(SIGCHLD, signchld_handler);
    struct sigaction sa;
    sa.sa_handler = signchld_handler;
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
