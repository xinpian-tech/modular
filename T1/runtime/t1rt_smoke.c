/*===--------------------------------------------------------------------===*\
 * Copyright (c) 2026, Xinpian Tech. All rights reserved.
 *
 * Licensed under the Apache License v2.0 with LLVM Exceptions:
 * https://llvm.org/LICENSE.txt
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
\*===--------------------------------------------------------------------===*/

/* t1rt_smoke: drive libT1RT end to end with the compiler-produced saxpy ELF,
 * no Mojo involved (verification point C+D of the minimal kernel plan). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Ctx Ctx;
typedef struct Buf Buf;
typedef struct Fn Fn;
typedef struct Tm Tm;

extern const char *AsyncRT_DeviceContext_create(const Ctx **, const char *, int);
extern const char *AsyncRT_DeviceContext_createBuffer_async(const Buf **, void **, const Ctx *, size_t, size_t);
extern const char *AsyncRT_DeviceContext_HtoD_async(const Ctx *, const Buf *, const void *);
extern const char *AsyncRT_DeviceContext_DtoH_async(const Ctx *, void *, const Buf *);
extern const char *AsyncRT_DeviceContext_loadFunction(const Fn **, const Ctx *, const char *, const char *, const char *, size_t, int32_t, const char *, int32_t);
extern const char *AsyncRT_DeviceContext_enqueueFunctionDirect(const Ctx *, const Fn *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, void *, uint32_t, void **, uint32_t, uint64_t *);
extern const char *AsyncRT_DeviceContext_synchronize(const Ctx *);
extern const char *AsyncRT_DeviceContext_startTimer(const Tm **, const Ctx *);
extern const char *AsyncRT_DeviceContext_stopTimer(int64_t *, const Ctx *, const Tm *);

#define CHECK(x)                                                               \
  do {                                                                         \
    const char *err_ = (x);                                                    \
    if (err_) {                                                                \
      fprintf(stderr, "FAIL %s: %s\n", #x, err_);                              \
      return 1;                                                                \
    }                                                                          \
  } while (0)

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: smoke <kernel.elf> <entry-symbol-file>\n");
    return 2;
  }
  FILE *f = fopen(argv[1], "rb");
  fseek(f, 0, SEEK_END);
  long elf_len = ftell(f);
  fseek(f, 0, SEEK_SET);
  char *elf = malloc(elf_len);
  if (fread(elf, 1, elf_len, f) != (size_t)elf_len) return 2;
  fclose(f);
  /* the mangled symbol, first line of the file */
  f = fopen(argv[2], "rb");
  static char sym[4096];
  if (!fgets(sym, sizeof sym, f)) return 2;
  sym[strcspn(sym, "\n")] = 0;
  fclose(f);

  enum { N = 64 };
  const Ctx *ctx;
  CHECK(AsyncRT_DeviceContext_create(&ctx, "t1", 0));

  const Buf *bx, *by, *bo;
  void *dx, *dy, *do_;
  CHECK(AsyncRT_DeviceContext_createBuffer_async(&bx, &dx, ctx, N, 4));
  CHECK(AsyncRT_DeviceContext_createBuffer_async(&by, &dy, ctx, N, 4));
  CHECK(AsyncRT_DeviceContext_createBuffer_async(&bo, &do_, ctx, N, 4));

  float x[N], y[N], out[N], a = 2.5f;
  for (int i = 0; i < N; i++) {
    x[i] = (float)i;
    y[i] = 100.0f + (float)i;
  }
  CHECK(AsyncRT_DeviceContext_HtoD_async(ctx, bx, x));
  CHECK(AsyncRT_DeviceContext_HtoD_async(ctx, by, y));

  const Fn *fn;
  CHECK(AsyncRT_DeviceContext_loadFunction(&fn, ctx, "smoke", sym, elf,
                                           elf_len, 0, "none", 3));

  const Tm *tm;
  CHECK(AsyncRT_DeviceContext_startTimer(&tm, ctx));

  int32_t n = N;
  void *args[5] = {&dx, &dy, &do_, &a, &n};
  uint64_t sizes[5] = {8, 8, 8, 4, 4};
  CHECK(AsyncRT_DeviceContext_enqueueFunctionDirect(
      ctx, fn, 1, 1, 1, 1, 1, 1, 0, NULL, 0, args, 5, sizes));
  CHECK(AsyncRT_DeviceContext_synchronize(ctx));

  int64_t cycles = 0;
  CHECK(AsyncRT_DeviceContext_stopTimer(&cycles, ctx, tm));

  CHECK(AsyncRT_DeviceContext_DtoH_async(ctx, out, bo));

  int bad = 0;
  for (int i = 0; i < N; i++) {
    float want = a * x[i] + y[i];
    if (out[i] != want) {
      if (bad < 5)
        fprintf(stderr, "MISMATCH [%d]: got %f want %f\n", i, out[i], want);
      bad++;
    }
  }
  if (bad) {
    fprintf(stderr, "FAILED: %d mismatches\n", bad);
    return 1;
  }
  printf("SAXPY OK on T1: n=%d, kernel cycles=%ld\n", N, (long)cycles);
  return 0;
}
