#include "dpapi_channel.h"

#include <windows.h>
#include <wincrypt.h>

#include <flutter/standard_method_codec.h>

#include <limits>
#include <vector>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDpapiChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "org.discourse.native/windows_dpapi",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const bool encrypt = call.method_name() == "encrypt";
        if (!encrypt && call.method_name() != "decrypt") {
          result->NotImplemented();
          return;
        }
        const auto* bytes = call.arguments()
                                ? std::get_if<std::vector<uint8_t>>(
                                      call.arguments())
                                : nullptr;
        if (!bytes || bytes->empty() ||
            bytes->size() > (std::numeric_limits<DWORD>::max)()) {
          result->Error("invalid_arguments", "Expected non-empty bytes");
          return;
        }
        DATA_BLOB input = {static_cast<DWORD>(bytes->size()),
                           const_cast<BYTE*>(bytes->data())};
        DATA_BLOB output = {};
        const BOOL succeeded =
            encrypt ? CryptProtectData(&input, L"Discourse Native credentials",
                                       nullptr, nullptr, nullptr,
                                       CRYPTPROTECT_UI_FORBIDDEN, &output)
                    : CryptUnprotectData(&input, nullptr, nullptr, nullptr,
                                         nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                                         &output);
        if (!succeeded) {
          const auto error = GetLastError();
          result->Error("dpapi_error", "Windows credential encryption failed (" +
                                         std::to_string(error) + ")");
          return;
        }
        std::vector<uint8_t> value(output.pbData,
                                   output.pbData + output.cbData);
        SecureZeroMemory(output.pbData, output.cbData);
        LocalFree(output.pbData);
        result->Success(flutter::EncodableValue(std::move(value)));
      });
  return channel;
}
