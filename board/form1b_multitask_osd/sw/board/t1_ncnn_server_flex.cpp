// Flexible multi-model ncnn server for the three-task chain.
// Registry: id,name,param,bin,input_names,output_names[,w,h,c]
// Names and per-input dimensions are comma-separated. Reply for multi-output:
// [u32 count][u32 bytes0][blob0][u32 bytes1][blob1]...; single-output legacy unchanged.
#include <arpa/inet.h>
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

#define LEGACY_W 320
#define LEGACY_H 320
#define LEGACY_C 3
#define LEGACY_LEN (LEGACY_W * LEGACY_H * LEGACY_C * 4)

struct Model {
    int id;
    std::string name, param, bin;
    std::vector<std::string> inputs, outputs;
    std::vector<int> ws, hs, cs;
    ncnn::Net net;
};

static bool read_full(int fd, void* buf, size_t n) {
    char* p = (char*)buf;
    while (n) {
        ssize_t r = read(fd, p, n);
        if (r <= 0) return false;
        p += r; n -= r;
    }
    return true;
}
static bool write_full(int fd, const void* buf, size_t n) {
    const char* p = (const char*)buf;
    while (n) {
        ssize_t r = send(fd, p, n, MSG_NOSIGNAL);
        if (r <= 0) return false;
        p += r; n -= r;
    }
    return true;
}
static std::vector<std::string> split(const std::string& s, char delim) {
    std::vector<std::string> out;
    size_t lo = 0;
    while (true) {
        size_t hi = s.find(delim, lo);
        out.push_back(s.substr(lo, hi == std::string::npos ? hi : hi - lo));
        if (hi == std::string::npos) break;
        lo = hi + 1;
    }
    return out;
}
static std::vector<int> ints(const std::vector<std::string>& fields, int index,
                             size_t count, int fallback) {
    std::vector<int> out;
    if ((int)fields.size() > index) {
        auto parts = split(fields[index], ',');
        for (auto& s : parts) out.push_back(atoi(s.c_str()));
    }
    while (out.size() < count) out.push_back(fallback);
    return out;
}

int main(int argc, char** argv) {
    int port = argc > 1 ? atoi(argv[1]) : 5002;
    const char* reg_path = argc > 2 ? argv[2] : "/home/xilinx/three_task/c2_registry.conf";
    FILE* rf = fopen(reg_path, "r");
    if (!rf) { fprintf(stderr, "SERVER_REG_FAIL %s\n", reg_path); return 1; }
    std::vector<Model*> models;
    char line[4096];
    while (fgets(line, sizeof(line), rf)) {
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') continue;
        auto f = split(std::string(line), '\t');
        if (f.size() < 6) continue;
        for (auto& field : f) {
            while (!field.empty() && (field.back() == '\n' || field.back() == '\r'))
                field.pop_back();
        }
        Model* m = new Model();
        m->id = atoi(f[0].c_str()); m->name = f[1]; m->param = f[2]; m->bin = f[3];
        m->inputs = split(f[4], ','); m->outputs = split(f[5], ',');
        size_t n = m->inputs.size();
        m->ws = ints(f, 6, n, LEGACY_W);
        m->hs = ints(f, 7, n, LEGACY_H);
        m->cs = ints(f, 8, n, LEGACY_C);
        if (m->outputs.empty() || m->net.load_param(m->param.c_str()) != 0 ||
            m->net.load_model(m->bin.c_str()) != 0) {
            fprintf(stderr, "SERVER_LOAD_FAIL id=%d %s\n", m->id, m->name.c_str());
            return 1;
        }
        m->net.opt.num_threads = 1;
        models.push_back(m);
        fprintf(stderr, "SERVER_MODEL id=%d name=%s inputs=%zu outputs=%zu\n",
                m->id, m->name.c_str(), m->inputs.size(), m->outputs.size());
    }
    fclose(rf);
    if (models.empty()) return 1;
    fprintf(stderr, "SERVER_READY port=%d models=%zu\n", port, models.size());

    int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    sockaddr_in addr{}; addr.sin_family = AF_INET; addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    if (bind(ls, (sockaddr*)&addr, sizeof(addr)) || listen(ls, 1)) {
        fprintf(stderr, "SERVER_BIND_FAIL\n"); return 1;
    }
    while (true) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) continue;
        while (true) {
            uint32_t w0 = 0, len = 0, mid = 0;
            if (!read_full(fd, &w0, 4)) break;
            if (w0 == LEGACY_LEN) len = w0;
            else { mid = w0; if (!read_full(fd, &len, 4)) break; }
            Model* m = models[0];
            if (mid) {
                m = nullptr;
                for (auto* candidate : models) if (candidate->id == (int)mid) m = candidate;
                if (!m) { fprintf(stderr, "SERVER_BAD_MODEL %u\n", mid); break; }
            }
            size_t expected = 0;
            for (size_t i = 0; i < m->inputs.size(); ++i)
                expected += (size_t)m->ws[i] * m->hs[i] * m->cs[i] * 4;
            if (len != expected) {
                fprintf(stderr, "SERVER_BAD_LEN id=%d got=%u expected=%zu\n", m->id, len, expected);
                break;
            }
            std::vector<float> payload(len / 4);
            if (!read_full(fd, payload.data(), len)) break;
            std::vector<ncnn::Mat> outputs;
            bool failed = false;
            for (auto& name : m->outputs) {
                // This ncnn build cannot reliably extract several terminal
                // outputs from one Extractor. Use an independent forward pass
                // per requested output (same payload, identical semantics).
                ncnn::Extractor ex = m->net.create_extractor();
                size_t offset = 0;
                for (size_t i = 0; i < m->inputs.size(); ++i) {
                    ncnn::Mat in(m->ws[i], m->hs[i], m->cs[i], (void*)(payload.data() + offset));
                    int input_rc = ex.input(m->inputs[i].c_str(), in);
                    if (input_rc != 0)
                        fprintf(stderr, "SERVER_INPUT_FAIL id=%d input=%s rc=%d shape=%dx%dx%d\n",
                                m->id, m->inputs[i].c_str(), input_rc, m->ws[i], m->hs[i], m->cs[i]);
                    offset += (size_t)m->ws[i] * m->hs[i] * m->cs[i];
                }
                ncnn::Mat out;
                if (ex.extract(name.c_str(), out) != 0) {
                    fprintf(stderr, "SERVER_EXTRACT_FAIL id=%d out=%s\n", m->id, name.c_str());
                    failed = true; break;
                }
                outputs.push_back(out);
            }
            if (failed) break;
            uint32_t count = (uint32_t)outputs.size();
            if (count > 1 && !write_full(fd, &count, 4)) break;
            for (auto& out : outputs) {
                uint32_t bytes = (uint32_t)(out.w * out.h * out.c) * 4;
                if (!write_full(fd, &bytes, 4) || !write_full(fd, out.data, bytes)) { failed = true; break; }
            }
            if (failed) break;
        }
        close(fd);
    }
    return 0;
}
