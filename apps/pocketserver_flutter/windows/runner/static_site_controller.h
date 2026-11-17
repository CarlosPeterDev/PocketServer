#ifndef RUNNER_STATIC_SITE_CONTROLLER_H_
#define RUNNER_STATIC_SITE_CONTROLLER_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

#include "loopback_site_server.h"

class StaticSiteController {
 public:
  StaticSiteController(flutter::BinaryMessenger* messenger, HWND owner);
  ~StaticSiteController();

 private:
  void ChooseAndStart(flutter::MethodResult<flutter::EncodableValue>& result);

  HWND owner_;
  std::unique_ptr<LoopbackSiteServer> site_;
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};

#endif
