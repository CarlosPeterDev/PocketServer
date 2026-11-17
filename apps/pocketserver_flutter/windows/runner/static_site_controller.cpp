#include "static_site_controller.h"

#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <filesystem>
#include <fstream>
#include <utility>
#include <string>
#include <system_error>

StaticSiteController::StaticSiteController(flutter::BinaryMessenger* messenger,
                                           HWND owner)
    : owner_(owner),
      channel_(messenger, "com.pocketserver.app/static_site",
               &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "chooseAndStart") {
      ChooseAndStart(*result);
    } else if (call.method_name() == "stop") {
      site_.reset();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

StaticSiteController::~StaticSiteController() {
  channel_.SetMethodCallHandler(nullptr);
}

void StaticSiteController::ChooseAndStart(
    flutter::MethodResult<flutter::EncodableValue>& result) {
  Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(dialog.GetAddressOf())))) {
    result.Error("picker_unavailable", "Unable to open the document picker");
    return;
  }

  const COMDLG_FILTERSPEC filters[] = {{L"HTML files", L"*.html;*.htm"}};
  if (FAILED(dialog->SetOptions(FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST |
                                FOS_NOCHANGEDIR)) ||
      FAILED(dialog->SetFileTypes(1, filters))) {
    result.Error("picker_unavailable", "Unable to configure the document picker");
    return;
  }

  const HRESULT shown = dialog->Show(owner_);
  if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    result.Success();
    return;
  }

  Microsoft::WRL::ComPtr<IShellItem> item;
  PWSTR raw_path = nullptr;
  if (FAILED(shown) || FAILED(dialog->GetResult(item.GetAddressOf())) ||
      FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw_path))) {
    result.Error("file_unavailable", "Unable to open the selected document");
    return;
  }
  std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> path(raw_path, CoTaskMemFree);
  const std::filesystem::path file(path.get());
  std::error_code file_error;
  const auto size = std::filesystem::file_size(file, file_error);
  if (file_error || size == 0 || size > LoopbackSiteServer::kMaxPageBytes) {
    result.Error("file_unavailable", "Choose a nonempty HTML file up to 1 MiB");
    return;
  }

  std::ifstream input(file, std::ios::binary);
  std::string html(LoopbackSiteServer::kMaxPageBytes + 1, '\0');
  if (!input) {
    result.Error("file_unavailable", "Unable to open the selected document");
    return;
  }
  input.read(html.data(), static_cast<std::streamsize>(html.size()));
  if (input.bad() || input.gcount() <= 0 ||
      static_cast<std::size_t>(input.gcount()) > LoopbackSiteServer::kMaxPageBytes) {
    result.Error("file_unavailable", "Choose a nonempty HTML file up to 1 MiB");
    return;
  }
  html.resize(static_cast<std::size_t>(input.gcount()));

  auto next = LoopbackSiteServer::Start(std::move(html));
  if (!next) {
    result.Error("server_unavailable", "Could not start local hosting");
    return;
  }
  site_ = std::move(next);
  result.Success(flutter::EncodableValue(site_->url()));
}
