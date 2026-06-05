#!/bin/sh

# This script is related to the 'recvfrom_unix.ml' test.
# It checks whether PF_UNIX/SOCK_DGRAM supports routing a datagram to a
# pathname-bound socket and reporting the sender pathname with recvfrom.

tmpbase="${TMPDIR:-.}/ocamltest-unix-dgram-recvfrom-$$"
src="${tmpbase}.c"
exe="${tmpbase}"
err="${tmpbase}.err"

cleanup () {
  rm -f "$src" "$exe" "$err" "ocamltest-dgram-$$"
}

trap cleanup 0 1 2 3 15

cat > "$src" <<'EOF'
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <signal.h>

static char path[80];

static void on_alarm(int sig)
{
  (void)sig;
  _exit(3);
}

int main(void)
{
  int s;
  int n;
  int fromlen;
  char out = 't';
  char in = 0;
  struct sockaddr_un addr;
  struct sockaddr_un from;

  signal(SIGALRM, on_alarm);
  sprintf(path, "ocamltest-dgram-%ld", (long)getpid());
  unlink(path);

  s = socket(PF_UNIX, SOCK_DGRAM, 0);
  if (s < 0) return 3;

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strcpy(addr.sun_path, path);

  if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) return 3;

  alarm(3);
  n = sendto(s, &out, 1, 0, (struct sockaddr *)&addr, sizeof(addr));
  if (n != 1) return 3;

  memset(&from, 0, sizeof(from));
  fromlen = sizeof(from);
  n = recvfrom(s, &in, 1, 0, (struct sockaddr *)&from, &fromlen);
  alarm(0);

  unlink(path);
  close(s);

  if (n != 1 || in != 't') return 3;
  if (from.sun_family != AF_UNIX) return 3;
  if (strcmp(from.sun_path, path) != 0) return 3;

  return 0;
}
EOF

if ${CC:-cc} -D_BSD_EXTENSION -o "$exe" "$src" > /dev/null 2> "$err"; then
  :
elif c89 -D_BSD_EXTENSION -o "$exe" "$src" > /dev/null 2> "$err"; then
  :
else
  cat > "$ocamltest_response" <<EOF
-stdout
-stderr
EOF
  exit ${TEST_PASS}
fi

"$exe" > /dev/null 2> "$err"
case "$?" in
  0)
    cat > "$ocamltest_response" <<EOF
-stdout
-stderr
EOF
    exit ${TEST_PASS}
    ;;
  *)
    echo "PF_UNIX SOCK_DGRAM recvfrom sender addresses are not supported" \
      > "$ocamltest_response"
    exit ${TEST_SKIP}
    ;;
esac
