#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char from[] = "MenhirLib";
static const char to[] = "CamlinternalMenhirLib";

static void die(const char *msg)
{
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

int main(int argc, char **argv)
{
  FILE *in, *out;
  int c;
  size_t matched = 0;

  if (argc != 3) die("usage: plan9-menhir-replace input output");

  in = fopen(argv[1], "rb");
  if (in == NULL) die("cannot open input");

  out = fopen(argv[2], "wb");
  if (out == NULL) die("cannot open output");

  while ((c = fgetc(in)) != EOF) {
    if ((unsigned char)c == (unsigned char)from[matched]) {
      matched++;
      if (from[matched] == '\0') {
        fputs(to, out);
        matched = 0;
      }
    } else {
      if (matched != 0) {
        fwrite(from, 1, matched, out);
        matched = 0;
      }
      if ((unsigned char)c == (unsigned char)from[0]) {
        matched = 1;
      } else {
        fputc(c, out);
      }
    }
  }

  if (matched != 0) fwrite(from, 1, matched, out);

  if (fclose(in) != 0) die("cannot close input");
  if (fclose(out) != 0) die("cannot close output");

  return 0;
}
