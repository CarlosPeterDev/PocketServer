#ifndef POCKETSERVER_LOOPBACK_SITE_SERVER_H_
#define POCKETSERVER_LOOPBACK_SITE_SERVER_H_

#include <cstddef>
#include <memory>
#include <string>
#include <thread>

namespace httplib {
class Server;
}

class LoopbackSiteServer {
 public:
  static constexpr std::size_t kMaxPageBytes = 1024 * 1024;

  static std::unique_ptr<LoopbackSiteServer> Start(std::string html);
  ~LoopbackSiteServer();

  const std::string& url() const { return url_; }

 private:
  LoopbackSiteServer();
  std::unique_ptr<httplib::Server> server_;
  std::string url_;
  std::thread worker_;
};

#endif
