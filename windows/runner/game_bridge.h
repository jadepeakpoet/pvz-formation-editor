#ifndef RUNNER_GAME_BRIDGE_H_
#define RUNNER_GAME_BRIDGE_H_
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterGameBridge(flutter::BinaryMessenger *messenger);
#endif
