/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*             Sebastien Hinderer, projet Gallium, INRIA Paris            */
/*                                                                        */
/*   Copyright 2016 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

/* Run programs with rediretions and timeouts under Unix */

#include <stdio.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <stdarg.h>
#include <signal.h>

#include "run.h"
#include "run_common.h"

#define COREFILENAME "core"

#ifndef SA_RESETHAND
#define SA_RESETHAND 0
#endif

#ifdef CAML_PLAN9_OCAMLTEST_FALLBACKS
extern char **environ;

static int ocamltest_env_name_matches(
  const char *entry, const char *name, size_t name_length)
{
  return strncmp(entry, name, name_length) == 0 && entry[name_length] == '=';
}

static int ocamltest_environ_length(void)
{
  int count = 0;
  if (environ != NULL) {
    while (environ[count] != NULL) count++;
  }
  return count;
}

static int ocamltest_setenv(const char *name, const char *value, int overwrite)
{
  int i, count, found = -1;
  size_t name_length = strlen(name);
  size_t value_length = strlen(value);
  char *entry;
  char **new_environ;

  count = ocamltest_environ_length();
  if (environ != NULL) {
    for (i = 0; i < count; i++) {
      if (ocamltest_env_name_matches(environ[i], name, name_length)) {
        if (!overwrite) return 0;
        found = i;
        break;
      }
    }
  }

  entry = malloc(name_length + value_length + 2);
  if (entry == NULL) return -1;
  memcpy(entry, name, name_length);
  entry[name_length] = '=';
  memcpy(entry + name_length + 1, value, value_length);
  entry[name_length + value_length + 1] = '\0';

  new_environ = malloc((count + (found == -1 ? 2 : 1)) * sizeof(char *));
  if (new_environ == NULL) {
    free(entry);
    return -1;
  }
  for (i = 0; i < count; i++)
    new_environ[i] = (i == found) ? entry : environ[i];
  if (found == -1) {
    new_environ[count] = entry;
    new_environ[count + 1] = NULL;
  } else {
    new_environ[count] = NULL;
  }
  environ = new_environ;
  return 0;
}

static int ocamltest_unsetenv(const char *name)
{
  int i, count, kept = 0;
  size_t name_length = strlen(name);
  char **new_environ;

  if (environ == NULL) return 0;
  count = ocamltest_environ_length();
  new_environ = malloc((count + 1) * sizeof(char *));
  if (new_environ == NULL) return -1;
  for (i = 0; i < count; i++) {
    if (!ocamltest_env_name_matches(environ[i], name, name_length))
      new_environ[kept++] = environ[i];
  }
  new_environ[kept] = NULL;
  environ = new_environ;
  return 0;
}

static void ocamltest_reset_fdinfo_for_exec(void)
{
  unlink("/env/_fdinfo");
  ocamltest_unsetenv("_fdinfo");
}

static const char *ocamltest_strsignal(int sig)
{
  static char unknown_signal[32];

  switch (sig) {
    case SIGHUP: return "SIGHUP";
    case SIGINT: return "SIGINT";
    case SIGQUIT: return "SIGQUIT";
    case SIGILL: return "SIGILL";
    case SIGABRT: return "SIGABRT";
    case SIGFPE: return "SIGFPE";
    case SIGKILL: return "SIGKILL";
    case SIGSEGV: return "SIGSEGV";
    case SIGPIPE: return "SIGPIPE";
    case SIGALRM: return "SIGALRM";
    case SIGTERM: return "SIGTERM";
    case SIGUSR1: return "SIGUSR1";
    case SIGUSR2: return "SIGUSR2";
    case SIGBUS: return "SIGBUS";
    case SIGCHLD: return "SIGCHLD";
    case SIGCONT: return "SIGCONT";
    case SIGSTOP: return "SIGSTOP";
    case SIGTSTP: return "SIGTSTP";
    case SIGTTIN: return "SIGTTIN";
    case SIGTTOU: return "SIGTTOU";
    case SIGVTALRM: return "SIGVTALRM";
    case SIGPROF: return "SIGPROF";
    default:
      snprintf(unknown_signal, sizeof(unknown_signal), "signal %d", sig);
      return unknown_signal;
  }
}

#define setenv ocamltest_setenv
#define unsetenv ocamltest_unsetenv
#define strsignal ocamltest_strsignal
#endif

static volatile int timeout_expired = 0;

#define error(...) \
error_with_location(__FILE__, __LINE__, settings, __VA_ARGS__)

/*
  APE cpp rejects gcc's comma-swallowing ", ## __VA_ARGS__" extension.
  The message argument is required, so ordinary variadic macros are enough.
*/

static void myperror_with_location(
  const char *file, int line,
  const command_settings *settings,
  const char *msg, ...)
{
  va_list ap;
  Logger *logger = (settings->logger != NULL) ? settings->logger
                                              : defaultLogger;
  void *loggerData = settings->loggerData;
  va_start(ap, msg);
  mylog(logger, loggerData, "%s:%d: ", file, line);
  logger(loggerData, msg, ap);
  mylog(logger, loggerData, ": %s\n", strerror(errno));
  va_end(ap);
}

#define myperror(...) \
myperror_with_location(__FILE__, __LINE__, settings, __VA_ARGS__)

/* Same remark as for the error macro. */

#define child_error(...) \
  myperror(__VA_ARGS__); \
  goto child_failed;

static void open_error_with_location(
  const char *file, int line,
  const command_settings *settings,
  const char *msg)
{
  myperror_with_location(file, line, settings, "Can not open %s", msg);
}

#define open_error(filename) \
open_error_with_location(__FILE__, __LINE__, settings, filename)

static void realpath_error_with_location(
  const char *file, int line,
  const command_settings *settings,
  const char *msg)
{
  myperror_with_location(file, line, settings, "realpath(\"%s\") failed", msg);
}

#define realpath_error(filename) \
realpath_error_with_location(__FILE__, __LINE__, settings, filename)

static void stat_error_with_location(
  const char *file, int line,
  const command_settings *settings,
  const char *msg)
{
  myperror_with_location(file, line, settings, "stat(\"%s\") failed", msg);
}

#define stat_error(filename) \
stat_error_with_location(__FILE__, __LINE__, settings, filename)

static void handle_alarm(int sig)
{
  timeout_expired = 1;
}

static int paths_same_file(
  const command_settings *settings, const char * path1, const char * path2)
{
  int same_file = 0;
#ifdef __GLIBC__
  char *realpath1, *realpath2;
  realpath1 = realpath(path1, NULL);
  if (realpath1 == NULL)
    realpath_error(path1);
  realpath2 = realpath(path2, NULL);
  if (realpath2 == NULL)
  {
    free(realpath1);
    if (errno == ENOENT) return 0;
    else realpath_error(path2);
  }
#else
  struct stat stat1, stat2;
  if (stat(path1, &stat1) == -1)
    stat_error(path1);
  if (stat(path2, &stat2) == -1)
  {
    if (errno == ENOENT) return 0;
    else stat_error(path2);
  }
  if (stat1.st_dev == stat2.st_dev && stat1.st_ino == stat2.st_ino)
    same_file = 1;
#endif /* __GLIBC__ */
#ifdef __GLIBC__
  if (strcmp(realpath1, realpath2) == 0)
    same_file = 1;
  free(realpath1);
  free(realpath2);
#endif /* __GLIBC__ */
  return same_file;
}

static void update_environment(array local_env)
{
  array envp;
  for (envp = local_env; *envp != NULL; envp++) {
    char *pos_eq = strchr(*envp, '=');
    if (pos_eq != NULL) {
      char *name, *value;
      int name_length = pos_eq - *envp;
      int l = strlen(*envp);
      int value_length = l - (name_length +1);
      name = malloc(name_length+1);
      value = malloc(value_length+1);
      memcpy(name, *envp, name_length);
      name[name_length] = '\0';
      memcpy(value, pos_eq + 1, value_length);
      value[value_length] = '\0';
      setenv(name, value, 1); /* 1 means overwrite */
      free(name);
      free(value);
    } else {
      unsetenv(*envp);
    }
  }
}

/*
  This function should return an exitcode that can itself be returned
  to its father through the exit system call.
  So it returns 0 to report success and 1 to report an error

 */
static int run_command_child(const command_settings *settings)
{
  int stdin_fd = -1, stdout_fd = -1, stderr_fd = -1; /* -1 = no redir */
  int inputFlags = O_RDONLY;
  int outputFlags =
    O_CREAT | O_WRONLY | (settings->append ? O_APPEND : O_TRUNC);
  int inputMode = 0400, outputMode = 0666;

  if (setpgid(0, 0) == -1)
  {
    child_error("setpgid");
  }

  if (is_defined(settings->stdin_filename))
  {
    stdin_fd = open(settings->stdin_filename, inputFlags, inputMode);
    if (stdin_fd < 0)
    {
      open_error(settings->stdin_filename);
      goto child_failed;
    }
    if (dup2(stdin_fd, STDIN_FILENO) == -1)
    {
      child_error("dup2 for stdin");
    }
  }

  if (is_defined(settings->stdout_filename))
  {
    stdout_fd = open(settings->stdout_filename, outputFlags, outputMode);
    if (stdout_fd < 0) {
      open_error(settings->stdout_filename);
      goto child_failed;
    }
    if (dup2(stdout_fd, STDOUT_FILENO) == -1)
    {
      child_error("dup2 for stdout");
    }
  }

  if (is_defined(settings->stderr_filename))
  {
    if (stdout_fd != -1)
    {
      if (paths_same_file(
        settings, settings->stdout_filename,settings->stderr_filename))
        stderr_fd = stdout_fd;
    }
    if (stderr_fd == -1)
    {
      stderr_fd = open(settings->stderr_filename, outputFlags, outputMode);
      if (stderr_fd == -1)
      {
        open_error(settings->stderr_filename);
        goto child_failed;
      }
    }
    if (dup2(stderr_fd, STDERR_FILENO) == -1)
    {
      child_error("dup2 for stderr");
    }
  }

  update_environment(settings->envp);

#ifdef CAML_PLAN9_OCAMLTEST_FALLBACKS
  ocamltest_reset_fdinfo_for_exec();
#endif

  execvp(settings->program, settings->argv);

  myperror("Cannot execute %s", settings->program);

child_failed:
  return 1;
}

/* Handles the termination of a process. Arguments:
 * The pid of the terminated process
 * Its termination status as returned by wait(2)
 * A string giving a prefix for the core file name.
   (the file will be called prefix.pid.core but may come from a
   different process)
 * Returns the code to return if this is the child process
 */
static int handle_process_termination(
  const command_settings *settings,
  pid_t pid, int status, const char *corefilename_prefix)
{
  int signal, core = 0;
  char *corestr;

  if (WIFEXITED(status)) return WEXITSTATUS(status);

  if ( !WIFSIGNALED(status) )
    error("Process %lld neither terminated normally nor received a" \
          "signal!?", (long long) pid);

  /* From here we know that the process terminated due to a signal */
  signal = WTERMSIG(status);
#ifdef WCOREDUMP
  core = WCOREDUMP(status);
#endif /* WCOREDUMP */
  corestr = core ? "" : "no ";
  fprintf(stderr,
    "Process %lld got signal %d(%s), %score dumped\n",
    (long long) pid, signal, strsignal(signal), corestr
  );

  if (core)
  {
    if ( access(COREFILENAME, F_OK) == -1)
      fprintf(stderr, "Could not find core file.\n");
    else {
      size_t corefile_len = strlen(corefilename_prefix) + 128;
      char * corefile = malloc(corefile_len);
      if (corefile == NULL)
        fprintf(stderr, "Out of memory while processing core file.\n");
      else {
        snprintf(corefile, corefile_len,
          "%s.%lld.core", corefilename_prefix, (long long) pid);
        if ( rename(COREFILENAME, corefile) == -1)
          fprintf(stderr, "The core file exists but could not be renamed.\n");
        else
          fprintf(stderr,"The core file has been renamed to %s\n", corefile);
        free(corefile);
      }
    }
  }

  return -signal;
}

static int run_command_parent(const command_settings *settings, pid_t child_pid)
{
  int waiting = 1, status, code, child_code = 0, timed_out = 0;
  pid_t pid;

  if (settings->timeout>0)
  {
    struct sigaction action;
    action.sa_handler = handle_alarm;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESETHAND;
    if (sigaction(SIGALRM, &action, NULL) == -1) myperror("sigaction");
    if (alarm(settings->timeout) == -1) myperror("alarm");
  }

  while (waiting)
  {
    pid = wait(&status);
    if (pid == -1)
    {
      switch (errno)
      {
        case EINTR:
          if ((settings->timeout > 0) && (timeout_expired))
          {
            timeout_expired = 0;
            timed_out = 1;
            mylog(
              settings->logger != NULL ? settings->logger : defaultLogger,
              settings->loggerData,
              "Timeout expired, killing all child processes\n");
            if (kill(-child_pid, SIGKILL) == -1) myperror("kill");
#ifdef CAML_PLAN9_OCAMLTEST_FALLBACKS
            if (kill(child_pid, SIGKILL) == -1 && errno != ESRCH)
              myperror("kill child");
#endif
          };
          break;
        case ECHILD:
          waiting = 0;
          break;
        default:
          myperror("wait");
      }
    } else { /* Got a pid */
      code = handle_process_termination(
        settings, pid, status, settings->program);
      if (pid == child_pid) child_code = code;
    }
  }

  if (settings->timeout > 0)
  {
    alarm(0);
    timeout_expired = 0;
  }

  return timed_out && child_code == 0 ? 1 : child_code;
}

int run_command(const command_settings *settings)
{
  pid_t child_pid = fork();

  switch (child_pid)
  {
    case -1:
      myperror("fork");
      return -1;
    case 0: /* child process */
      exit( run_command_child(settings) );
    default:
      return run_command_parent(settings, child_pid);
  }
}
