// t1_ncnn_server.cpp -- localhost TCP NanoDet inference server (2026-10-19).
// Why this exists: pyncnn build needs ninja/pip wheel infra the board lacks;
// the A9-proven NEON libncnn.a (build_neon2, 0.973s/frame single-thread)
// is already on disk. A tiny TCP server reuses it instead of rebuilding
// all of ncnn. One client connection at a time; framing = uint32 LE length
// prefix. Request payload = 320*320*3 fp32 CHW blob (1228800 bytes, exactly
// the t1_preproc dst buffer). Reply payload = 2125*39 fp32 (row-major,
// same layout as cv2.dnn output reshaped (len(grids), -1)).
//
// Build (board):
//   g++ -O2 -mfpu=neon -mfloat-abi=hard t1_ncnn_server.cpp \
//       -I/home/xilinx/ncnn_build/src -I/home/xilinx/ncnn_build/build_neon2/src \
//       /home/xilinx/ncnn_build/build_neon2/src/libncnn.a -lpthread \
//       -o /home/xilinx/t1_models/t1_ncnn_server
// Run:  t1_ncnn_server [port]        (default 5002, binds 127.0.0.1)
#include <arpa/inet.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <vector>

#include "net.h"
#include "mat.h"

#define BLOB_FLOATS (320 * 320 * 3)
#define OUT_FLOATS  (2125 * 39)

static bool read_full(int fd, void* buf, size_t n) {
    char* p = (char*)buf;
    while (n > 0) {
        ssize_t r = read(fd, p, n);
        if (r <= 0) return false;
        p += r; n -= (size_t)r;
    }
    return true;
}

static bool write_full(int fd, const void* buf, size_t n) {
    const char* p = (const char*)buf;
    while (n > 0) {
        ssize_t r = send(fd, p, n, MSG_NOSIGNAL);
        if (r <= 0) return false;
        p += r; n -= (size_t)r;
    }
    return true;
}

int main(int argc, char** argv) {
    int port = (argc > 1) ? atoi(argv[1]) : 5002;
    const char* param = (argc > 2) ? argv[2]
        : "/home/xilinx/t1_models/nanodet-plus-m_320-gesture7-v5.ncnn.param";
    const char* bin = (argc > 3) ? argv[3]
        : "/home/xilinx/t1_models/nanodet-plus-m_320-gesture7-v5.ncnn.bin";

    ncnn::Net net;
    if (net.load_param(param) != 0 || net.load_model(bin) != 0) {
        fprintf(stderr, "SERVER_LOAD_FAIL\n");
        return 1;
    }
    net.opt.num_threads = 1;   // A9: 2-thread OMP thrash regression (ledger)
    fprintf(stderr, "SERVER_READY port=%d\n", port);

    int ls = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    if (bind(ls, (sockaddr*)&addr, sizeof(addr)) != 0 || listen(ls, 1) != 0) {
        fprintf(stderr, "SERVER_BIND_FAIL\n");
        return 1;
    }

    std::vector<float> in(BLOB_FLOATS);
    while (true) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) continue;
        while (true) {
            uint32_t len = 0;
            if (!read_full(fd, &len, 4)) break;
            if (len != BLOB_FLOATS * 4) {
                fprintf(stderr, "SERVER_BAD_LEN %u\n", len);
                break;
            }
            if (!read_full(fd, in.data(), len)) break;
            ncnn::Mat m(320, 320, 3, (void*)in.data());  // external mem, fp32
            ncnn::Extractor ex = net.create_extractor();
            ex.input("data", m);
            ncnn::Mat out;
            if (ex.extract("output", out) != 0) {
                fprintf(stderr, "SERVER_EXTRACT_FAIL\n");
                break;
            }
            if (out.w * out.h * out.c != OUT_FLOATS) {
                fprintf(stderr, "SERVER_BAD_OUT %dx%dx%d\n", out.w, out.h, out.c);
                break;
            }
            uint32_t olen = OUT_FLOATS * 4;
            if (!write_full(fd, &olen, 4)) break;
            if (!write_full(fd, out.data, olen)) break;
        }
        close(fd);
    }
    return 0;
}
