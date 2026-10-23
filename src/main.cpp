#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

static std::filesystem::path data_dir() {
#if defined(_WIN32)
  const char *base = std::getenv("LOCALAPPDATA");
  if (!base || !*base)
    base = std::getenv("APPDATA");
  std::filesystem::path dir = (base && *base)
                                  ? std::filesystem::path(base)
                                  : std::filesystem::temp_directory_path();
  dir /= "gilya";
#else
  const char *xdg = std::getenv("XDG_DATA_HOME");
  std::filesystem::path dir;
  if (xdg && *xdg) {
    dir = std::filesystem::path(xdg) / "gilya";
  } else {
    const char *home = std::getenv("HOME");
    std::filesystem::path h = (home && *home)
                                  ? std::filesystem::path(home)
                                  : std::filesystem::temp_directory_path();
    dir = h / ".local" / "share" / "gilya";
  }
#endif
  return dir / "entries";
}

static std::string fnv1a_hex(const std::string &s) {
  uint64_t h = 1469598103934665603ULL;
  for (unsigned char c : s) {
    h ^= c;
    h *= 1099511628211ULL;
  }
  char buf[17];
  std::snprintf(buf, sizeof(buf), "%016llx", (unsigned long long)h);
  return std::string(buf);
}

struct Entry {
  std::string key;
  std::filesystem::path blob;
  std::filesystem::path metafile;
  std::filesystem::path target;
};

static std::string trim(std::string s) {
  auto sp = [](unsigned char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
  };
  while (!s.empty() && sp((unsigned char)s.back()))
    s.pop_back();
  size_t i = 0;
  while (i < s.size() && sp((unsigned char)s[i]))
    ++i;
  return s.substr(i);
}

static std::vector<Entry> load_entries(const std::filesystem::path &store) {
  std::vector<Entry> out;
  std::error_code ec;
  if (!std::filesystem::exists(store, ec))
    return out;
  for (auto &de : std::filesystem::directory_iterator(store, ec)) {
    if (ec)
      break;
    const std::filesystem::path p = de.path();
    if (p.extension() != ".path")
      continue;
    std::string line;
    {
      std::ifstream in(p, std::ios::binary);
      std::getline(in, line);
    }
    std::string target = trim(line);
    if (target.empty())
      continue;
    Entry e;
    e.key = p.stem().u8string();
    e.metafile = p;
    e.blob = store / (e.key + ".blob");
    e.target = std::filesystem::u8path(target);
    out.push_back(std::move(e));
  }
  std::sort(out.begin(), out.end(), [](const Entry &a, const Entry &b) {
    return a.target.filename().u8string() < b.target.filename().u8string();
  });
  return out;
}

static std::string human_size(uintmax_t n) {
  const char *u[] = {"B", "KB", "MB", "GB", "TB"};
  double v = (double)n;
  int i = 0;
  while (v >= 1024.0 && i < 4) {
    v /= 1024.0;
    ++i;
  }
  std::ostringstream os;
  if (i == 0)
    os << n << " " << u[i];
  else
    os << std::fixed << std::setprecision(1) << v << " " << u[i];
  return os.str();
}

static std::string saved_time(const std::filesystem::path &blob) {
  std::error_code ec;
  auto ft = std::filesystem::last_write_time(blob, ec);
  if (ec)
    return "-";
  // Portable (approximate) file_time -> system_clock conversion for C++17.
  auto sys = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
      ft - std::filesystem::file_time_type::clock::now() +
      std::chrono::system_clock::now());
  std::time_t tt = std::chrono::system_clock::to_time_t(sys);
  std::tm tm{};
#if defined(_WIN32)
  localtime_s(&tm, &tt);
#else
  localtime_r(&tt, &tm);
#endif
  char buf[32];
  std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M", &tm);
  return buf;
}

static bool is_all(const std::string &a) { return a == "*" || a == "all"; }

// Match an argument against stored entries by basename or by full stored path.
static std::vector<const Entry *> match(const std::vector<Entry> &es,
                                        const std::string &arg) {
  std::vector<const Entry *> r;
  for (auto &e : es)
    if (e.target.filename().u8string() == arg || e.target.u8string() == arg)
      r.push_back(&e);
  return r;
}

static int cmd_remember(const std::filesystem::path &store,
                        const std::vector<std::string> &paths) {
  std::filesystem::create_directories(store);
  int rc = 0;
  for (auto &raw : paths) {
    std::filesystem::path src = std::filesystem::u8path(raw);
    std::error_code ec;
    if (!std::filesystem::exists(src, ec) ||
        !std::filesystem::is_regular_file(src, ec)) {
      std::cerr << "gilya: not a regular file: " << src.u8string() << "\n";
      rc = 1;
      continue;
    }
    std::filesystem::path abs =
        std::filesystem::weakly_canonical(std::filesystem::absolute(src), ec);
    if (ec)
      abs = std::filesystem::absolute(src);
    std::string key = fnv1a_hex(abs.u8string());
    std::filesystem::copy_file(
        src, store / (key + ".blob"),
        std::filesystem::copy_options::overwrite_existing);
    {
      std::ofstream o(store / (key + ".path"),
                      std::ios::binary | std::ios::trunc);
      o << abs.u8string() << "\n";
    }
    std::cout << "remembered  " << abs.filename().u8string() << "  ("
              << abs.u8string() << ")\n";
  }
  return rc;
}

static int cmd_ls(const std::filesystem::path &store) {
  auto es = load_entries(store);
  if (es.empty()) {
    std::cout << "(nothing remembered)\n";
    return 0;
  }
  size_t w = 4;
  for (auto &e : es)
    w = std::max(w, e.target.filename().u8string().size());
  std::cout << std::left << std::setw((int)w) << "NAME" << "  " << std::setw(9)
            << "SIZE" << "  " << std::setw(16) << "SAVED"
            << "  " << "PATH\n";
  for (auto &e : es) {
    std::error_code ec;
    uintmax_t sz = std::filesystem::file_size(e.blob, ec);
    std::string sz_s = ec ? std::string("-") : human_size(sz);
    std::cout << std::left << std::setw((int)w)
              << e.target.filename().u8string() << "  " << std::setw(9) << sz_s
              << "  " << std::setw(16) << saved_time(e.blob) << "  "
              << e.target.u8string() << "\n";
  }
  return 0;
}

static int cmd_get(const std::filesystem::path &store,
                   const std::vector<std::string> &args) {
  auto es = load_entries(store);
  if (es.empty()) {
    std::cerr << "gilya: nothing remembered\n";
    return 1;
  }
  int rc = 0;
  auto restore = [&](const Entry &e) {
    std::error_code ec;
    if (e.target.has_parent_path())
      std::filesystem::create_directories(e.target.parent_path(), ec);
    std::filesystem::copy_file(
        e.blob, e.target, std::filesystem::copy_options::overwrite_existing,
        ec);
    if (ec) {
      std::cerr << "gilya: failed to restore " << e.target.u8string() << ": "
                << ec.message() << "\n";
      rc = 1;
    } else {
      std::cout << "restored    " << e.target.filename().u8string() << "  ("
                << e.target.u8string() << ")\n";
    }
  };
  for (auto &a : args) {
    if (is_all(a)) {
      for (auto &e : es)
        restore(e);
      continue;
    }
    auto m = match(es, a);
    if (m.empty()) {
      std::cerr << "gilya: no remembered file named '" << a
                << "' (try: gilya ls)\n";
      rc = 1;
      continue;
    }
    for (auto *e : m)
      restore(*e);
  }
  return rc;
}

static int cmd_rm(const std::filesystem::path &store,
                  const std::vector<std::string> &args) {
  auto es = load_entries(store);
  if (es.empty()) {
    std::cerr << "gilya: nothing remembered\n";
    return 1;
  }
  int rc = 0;
  auto erase = [&](const Entry &e) {
    std::error_code e1, e2;
    std::filesystem::remove(e.blob, e1);
    std::filesystem::remove(e.metafile, e2);
    std::cout << "forgot      " << e.target.filename().u8string() << "  ("
              << e.target.u8string() << ")\n";
  };
  for (auto &a : args) {
    if (is_all(a)) {
      for (auto &e : es)
        erase(e);
      continue;
    }
    auto m = match(es, a);
    if (m.empty()) {
      std::cerr << "gilya: no remembered file named '" << a
                << "' (try: gilya ls)\n";
      rc = 1;
      continue;
    }
    for (auto *e : m)
      erase(*e);
  }
  return rc;
}

static int usage() {
  std::cerr << "gilya - remember files and restore them later\n\n"
               "Usage:\n"
               "  gilya <path>...            remember one or more files\n"
               "  gilya ls                   list remembered files\n"
               "  gilya get <name|*|all>...  restore by name, or everything\n"
               "  gilya rm  <name|*|all>...  forget  by name, or everything\n\n"
               "In a shell, quote the star:  gilya get '*'   (or use: gilya "
               "get all)\n";
  return 2;
}

int main(int argc, char **argv) {
  try {
    if (argc < 2)
      return usage();
    const std::filesystem::path store = data_dir();
    const std::string cmd = argv[1];
    std::vector<std::string> rest;
    for (int i = 2; i < argc; ++i)
      rest.push_back(argv[i]);

    if (cmd == "ls")
      return cmd_ls(store);
    if (cmd == "get")
      return rest.empty() ? usage() : cmd_get(store, rest);
    if (cmd == "rm")
      return rest.empty() ? usage() : cmd_rm(store, rest);
    if (cmd == "help" || cmd == "-h" || cmd == "--help")
      return usage();

    // Anything else: treat every argument as a path to remember.
    std::vector<std::string> paths;
    paths.push_back(cmd);
    for (auto &r : rest)
      paths.push_back(r);
    return cmd_remember(store, paths);
  } catch (const std::exception &e) {
    std::cerr << "gilya: error: " << e.what() << "\n";
    return 1;
  }
}