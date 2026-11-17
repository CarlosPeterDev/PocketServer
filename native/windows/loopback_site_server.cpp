#include "loopback_site_server.h"

#include <httplib.h>

#include <system_error>
#include <utility>

LoopbackSiteServer::LoopbackSiteServer()
    : server_(std::make_unique<httplib::Server>()) {}

std::unique_ptr<LoopbackSiteServer> LoopbackSiteServer::Start(std::string html) {
  if (html.empty() || html.size() > kMaxPageBytes) {
    return nullptr;
  }

  auto site = std::unique_ptr<LoopbackSiteServer>(new LoopbackSiteServer());
  auto& server = *site->server_;
  server.new_task_queue = [] { return new httplib::ThreadPool(2, 2, 8); };
  server.set_keep_alive_max_count(1);
  server.set_read_timeout(2, 0);
  server.set_write_timeout(2, 0);
  server.set_payload_max_length(8192);
  server.set_default_headers({
      {"Cache-Control", "no-store"},
      {"X-Content-Type-Options", "nosniff"},
      {"Referrer-Policy", "no-referrer"},
  });

  const int port = server.bind_to_any_port("127.0.0.1");
  if (port < 0) {
    return nullptr;
  }

  const std::string host = "127.0.0.1:" + std::to_string(port);
  site->url_ = "http://" + host + "/";
  server.set_pre_routing_handler(
      [host](const httplib::Request& request, httplib::Response& response) {
        using Result = httplib::Server::HandlerResponse;
        if (request.get_header_value_count("Host") != 1 ||
            request.get_header_value("Host") != host) {
          response.status = 400;
          return Result::Handled;
        }
        if (request.method != "GET" && request.method != "HEAD") {
          response.status = 405;
          response.set_header("Allow", "GET, HEAD");
          return Result::Handled;
        }
        if (request.target != "/" && request.target != "/index.html") {
          response.status = 404;
          return Result::Handled;
        }
        return Result::Unhandled;
      });

  server.Get(R"(/(?:index\.html)?)",
             [html = std::move(html)](const httplib::Request&,
                                      httplib::Response& response) {
               response.set_content(html, "text/html; charset=utf-8");
             });
  try {
    site->worker_ = std::thread([engine = site->server_.get()] {
      try {
        engine->listen_after_bind();
      } catch (const std::system_error&) {
        engine->stop();
      }
    });
  } catch (const std::system_error&) {
    return nullptr;
  }
  return site;
}

LoopbackSiteServer::~LoopbackSiteServer() {
  server_->stop();
  if (worker_.joinable()) {
    worker_.join();
  }
}
