// t1_ncnn_server_multi.cpp -- multi-model localhost TCP inference server
// (2026-10-20, C2 baseline arm). Extends t1_ncnn_server.cpp (single NanoDet)
// to a model registry: ALL models preloaded at boot (avoids ncnn Net
// unload/reload lifecycle risk entirely), swap = O(1) table switch, "卸旧载新"
// semantics preserved at the runtime level (one resident active Net).
//
// Protocol (backward compatible):
//   legacy : [u32 len][blob]            len == 1228800 -> model_id 0
//   multi  : [u32 model_id][u32 len][blob]
//   reply  : [u32 out_len][blob]        out_len = model's OUT_FLOATS*4
//
// Config: argv[2] = registry file, one model per line, TAB-separated:
//   id<TAB>name<TAB>param_path<TAB>bin_path<TAB>input_name<TAB>output_name
// Output rows are passed through verbatim (decode stays in PS per SPEC C4).
//
// Build (board):
//   g++ -O2 -mfpu=neon -mfloat-abi=hard t1_ncnn_server_multi.cpp \
//       -I/home/xilinx/ncnn_build/src -I/home/xilinx/ncnn_build/build_neon2/src \
//       /home/xilinx/ncnn_build/build_neon2/src/libncnn.a -lpthread \
//       -o /home/xilinx/t1_models/t1_ncnn_server_multi
// Run: t1_ncnn_server_multi [port] [registry]   (default 5002, registry below)
#include <arpa/inet.h>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <netinet/in.h>
#include <string>
#include <sys/socket.h>
#include <unistd.h>
#include <vector>

#include "net.h"
#include "mat.h"

#define BLOB_FLOATS (320 * 320 * 3)
#define LEGACY_LEN  (BLOB_FLOATS * 4)

struct Model {
    int id;
    std::string name, param, bin, in_name, out_name;
    ncnn::Net net;
    int out_floats;
};

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

static std::vector<std::string> split_tab(const std::string& s) {
    std::vector<std::string> v;
    size_t lo = 0;
    while (true) {
        size_t hi = s.find('\t', lo);
        v.push_back(s.substr(lo, hi == std::string::npos ? hi : hi - lo));
        if (hi == std::string::npos) break;
        lo = hi + 1;
    }
    return v;
}

int main(int argc, char** argv) {
    int port = (argc > 1) ? atoi(argv[1]) : 5002;
    const char* reg_path = (argc > 2) ? argv[2]
        : "/home/xilinx/PSPL_YOLOV8N_RESIDENT/models/c2_registry.conf";

    // ---- registry load (ALL models resident = swap is a table switch) ----
    FILE* rf = fopen(reg_path, "r");
    if (!rf) { fprintf(stderr, "SERVER_REG_FAIL %s\n", reg_path); return 1; }
    std::vector<Model*> models;   // ncnn::Net is non-movable: heap-stable pointers
    char line[1024];
    while (fgets(line, sizeof(line), rf)) {
        if (line[0] == '#' || line[0] == '\n') continue;
        auto f = split_tab(line);
        if (f.size() < 6) { fprintf(stderr, "SERVER_REG_BADLINE %s", line); continue; }
        Model* m = new Model();
        m->id = atoi(f[0].c_str());
        m->name = f[1]; m->param = f[2]; m->bin = f[3];
        m->in_name = f[4]; m->out_name = f[5];
        if (m->net.load_param(m->param.c_str()) != 0 ||
            m->net.load_model(m->bin.c_str()) != 0) {
            fprintf(stderr, "SERVER_LOAD_FAIL id=%d %s\n", m->id, m->name.c_str());
            return 1;
        }
        m->net.opt.num_threads = 1;  // A9: 2-thread OMP thrash regression (ledger)
        models.push_back(m);
    }
    fclose(rf);
    if (models.empty()) { fprintf(stderr, "SERVER_REG_EMPTY\n"); return 1; }
    for (auto* m : models)  // per-model output size probe (1 dummy extract)
        fprintf(stderr, "SERVER_MODEL id=%d name=%s param=%s\n",
                m->id, m->name.c_str(), m->param.c_str());
    int active = 0;
    fprintf(stderr, "SERVER_READY port=%d models=%zu active=%d(%s)\n",
            port, models.size(), models[active]->id, models[active]->name.c_str());

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
            uint32_t w0 = 0, len = 0;
            bool feature_mode = false;
            if (!read_full(fd, &w0, 4)) break;
            if (w0 == LEGACY_LEN) {          // legacy framing -> model 0
                len = w0;
            } else {                         // multi framing: [model_id][len]
                uint32_t mid = w0;
                feature_mode = (mid & 0x80000000U) != 0;
                mid &= 0xFFU;
                if (!read_full(fd, &len, 4)) break;
                if (mid != (uint32_t)models[active]->id) {
                    size_t k = 0;
                    for (; k < models.size(); ++k)
                        if (models[k]->id == (int)mid) break;
                    if (k == models.size()) {
                        fprintf(stderr, "SERVER_BAD_MODEL %u\n", mid);
                        break;
                    }
                    int prev = models[active]->id;
                    auto t0 = std::chrono::steady_clock::now();
                    active = (int)k;
                    auto dt = std::chrono::duration_cast<std::chrono::microseconds>(
                        std::chrono::steady_clock::now() - t0).count();
                    fprintf(stderr, "SWAP %d->%d(%s) dt_us=%lld\n",
                            prev, models[active]->id,
                            models[active]->name.c_str(), (long long)dt);
                }
            }
            if (len != LEGACY_LEN) {
                fprintf(stderr, "SERVER_BAD_LEN %u\n", len);
                break;
            }
            if (!read_full(fd, in.data(), len)) break;
            Model& m = *models[active];
            ncnn::Mat mat(320, 320, 3, (void*)in.data());  // external mem, fp32
            ncnn::Extractor ex = m.net.create_extractor();
            ex.set_light_mode(false);  // retain model.15/18/21 features after output0
            ex.input(m.in_name.c_str(), mat);
            ncnn::Mat out;
            if (ex.extract(m.out_name.c_str(), out) != 0) {
                fprintf(stderr, "SERVER_EXTRACT_FAIL id=%d\n", m.id);
                break;
            }
            uint32_t olen = (uint32_t)(out.w * out.h * out.c) * 4;
            if (!write_full(fd, &olen, 4)) break;
            if (!write_full(fd, out.data, olen)) break;
            if (feature_mode) {
                if (m.id != 1) {
                    fprintf(stderr, "SERVER_FEATURES_UNSUPPORTED id=%d\n", m.id);
                    break;
                }
                const char* names[] = {
                    "/model.15/cv2/act/Mul_output_0",
                    "/model.18/cv2/act/Mul_output_0",
                    "/model.21/cv2/act/Mul_output_0"
                };
                const uint32_t expected[] = {102400, 51200, 25600};
                uint32_t feature_len = (102400 + 51200 + 25600) * 4;
                if (!write_full(fd, &feature_len, 4)) break;
                bool feature_ok = true;
                for (int i = 0; i < 3; ++i) {
                    ncnn::Mat feature;
                    if (ex.extract(names[i], feature) != 0 ||
                        (uint32_t)(feature.w * feature.h * feature.c) != expected[i]) {
                        fprintf(stderr, "SERVER_FEATURE_FAIL id=%d index=%d\n", m.id, i);
                        feature_ok = false;
                        break;
                    }
                    if (!write_full(fd, feature.data, expected[i] * 4)) {
                        feature_ok = false;
                        break;
                    }
                }
                if (!feature_ok) break;
            }
        }
        close(fd);
    }
    return 0;
}
