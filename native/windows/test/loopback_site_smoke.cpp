#include <httplib.h>

#include <cstdlib>
#include <iostream>
#include <string>

#include "loopback_site_server.h"

namespace {
void Require(bool valid, const char* label) {
  if (!valid) {
    std::cerr << "Failed: " << label << '\n';
    std::exit(EXIT_FAILURE);
  }
}
}  // namespace

int main() {
  const std::string html = "<!doctype html><title>PocketServer</title>";
  auto site = LoopbackSiteServer::Start(html);
  Require(site != nullptr, "bind IPv4 loopback");

  const auto& url = site->url();
  const std::string prefix = "http://127.0.0.1:";
  Require(url.rfind(prefix, 0) == 0, "use IPv4 loopback URL");
  const auto port = std::stoi(url.substr(prefix.size()));
  httplib::Client client("127.0.0.1", port);
  client.set_connection_timeout(1, 0);
  client.set_read_timeout(2, 0);

  auto response = client.Get("/");
  Require(response && response->status == 200 && response->body == html,
          "serve HTML");
  response = client.Get("/index.html");
  Require(response && response->status == 200 && response->body == html,
          "serve index");
  response = client.Head("/");
  Require(response && response->status == 200 && response->body.empty() &&
              response->get_header_value("Content-Length") ==
                  std::to_string(html.size()),
          "HEAD response");
  response = client.Get("/", httplib::Headers{{"Host", "example.invalid"}});
  Require(response && response->status == 400, "reject unexpected host");
  response = client.Get("/extra.txt");
  Require(response && response->status == 404, "serve no other paths");
  response = client.Post("/");
  Require(response && response->status == 405, "reject POST");

  site.reset();
  Require(!client.Get("/"), "close listener");
  Require(LoopbackSiteServer::Start("") == nullptr, "reject an empty page");
  Require(LoopbackSiteServer::Start(
              std::string(LoopbackSiteServer::kMaxPageBytes + 1, 'x')) ==
              nullptr,
          "reject oversized page");
  std::cout << "Loopback server smoke checks passed.\n";
}
