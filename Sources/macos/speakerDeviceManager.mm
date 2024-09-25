#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/AudioHardwareBase.h>
#include <CoreAudio/AudioServerPlugin.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <MacTypes.h>
#include <napi.h>
#include <stdio.h>

struct EventData {
  std::string *eventName = nullptr;
  std::string device;
  float volume;
  float decibels = 0.0f; // optional
};

struct VolumeListenerUnregisterObject {
  Boolean isUnregistered;
  OSStatus status;
  std::string errorMessage;
};

auto callback = [](Napi::Env env, Napi::Function jsCallback,
                   EventData *eventData) {
  Napi::Object eventResult = Napi::Object::New(env);
  eventResult.Set("eventName", (*(eventData->eventName)));
  eventResult.Set("device", eventData->device);
  eventResult.Set("volume", eventData->volume);
  // eventResult.Set("decibels", eventData->decibels);
  jsCallback.Call({eventResult});
  delete eventData->eventName;
  delete eventData;
};

class AudioManager : public Napi::ObjectWrap<AudioManager> {
public:
  static Napi::Object Init(Napi::Env env, Napi::Object exports);
  AudioManager(const Napi::CallbackInfo &info);
  ~AudioManager();

private:
  static Napi::FunctionReference constructor;

  Napi::Value StartMonitoring(const Napi::CallbackInfo &info);
  Napi::Value StopMonitoring(const Napi::CallbackInfo &info);
  Napi::Value SetVolume(const Napi::CallbackInfo &info);
  Napi::Value GetVolume(const Napi::CallbackInfo &info);
  Napi::Value SwitchAudioDevice(const Napi::CallbackInfo &info);
  Napi::Value GetDefaultAudioDeviceName(const Napi::CallbackInfo &info);
  Napi::Value GetAllAudioDeviceNames(const Napi::CallbackInfo &info);
  Napi::Value SetVirtualDeviceCustomProperty(const Napi::CallbackInfo &info);
  Napi::Value GetMuteState(const Napi::CallbackInfo &info);
  Napi::Value SetMuteState(const Napi::CallbackInfo &info);

  VolumeListenerUnregisterObject RemoveVolumeListener();

  static AudioDeviceID
  GetCurrentDefaultOutputDeviceId(AudioDeviceID &defaultOutputDevice);
  static Boolean GetDecibelValue(AudioDeviceID deviceId, Float32 &decibels);
  static std::string GetErrorDescription(OSStatus error);
  static OSStatus SetCustomProperty(AudioDeviceID deviceId,
                                    std::string customPropertyString);
  static OSStatus
  VolumeChangeListener(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                       const AudioObjectPropertyAddress *inAddresses,
                       void *inClientData);

  static AudioDeviceID GetAudioDeviceIdByName(const std::string &deviceName);
  static Boolean IsOutputDevice(AudioDeviceID deviceId);
  static std::vector<AudioDeviceID> GetAllAudioDevices();
  static std::string GetDeviceName(AudioDeviceID deviceId);
  static Napi::Value HandleAudioObjectError(const Napi::Env &env,
                                            OSStatus status,
                                            const std::string &errorMessage);

  Napi::ThreadSafeFunction tsfn;
  bool isMonitoring;
};

Napi::FunctionReference AudioManager::constructor;

Napi::Object AudioManager::Init(Napi::Env env, Napi::Object exports) {
  Napi::Function func = DefineClass(
      env, "AudioManager",
      {InstanceMethod("startVolumeMonitoring", &AudioManager::StartMonitoring),
       InstanceMethod("stopVolumeMonitoring", &AudioManager::StopMonitoring),
       InstanceMethod("setVolume", &AudioManager::SetVolume),
       InstanceMethod("getVolume", &AudioManager::GetVolume),
       InstanceMethod("switchAudioDevice", &AudioManager::SwitchAudioDevice),
       InstanceMethod("getDefaultAudioDeviceName",
                      &AudioManager::GetDefaultAudioDeviceName),
       InstanceMethod("getAllAudioDeviceNames",
                      &AudioManager::GetAllAudioDeviceNames),
       InstanceMethod("setVirtualDeviceCustomProperty",
                      &AudioManager::SetVirtualDeviceCustomProperty),
       InstanceMethod("getMuteState", &AudioManager::GetMuteState),
       InstanceMethod("setMuteState", &AudioManager::SetMuteState)});

  constructor = Napi::Persistent(func);
  constructor.SuppressDestruct();

  exports.Set("AudioManager", func);
  return exports;
}

AudioManager::AudioManager(const Napi::CallbackInfo &info)
    : Napi::ObjectWrap<AudioManager>(info), isMonitoring(false) {}

AudioManager::~AudioManager() {
  if (isMonitoring) {
    RemoveVolumeListener();
  }
}

AudioDeviceID AudioManager::GetCurrentDefaultOutputDeviceId(
    AudioDeviceID &defaultOutputDevice) {
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster};

  UInt32 dataSize = sizeof(AudioDeviceID);

  OSStatus status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &dataSize, &defaultOutputDevice);
  if (status != noErr) {
    return 0;
  }

  return defaultOutputDevice;
}

std::string AudioManager::GetErrorDescription(OSStatus error) {
  switch (error) {
  case kAudioHardwareNoError:
    return "No Error";
    break;
  case kAudioHardwareNotRunningError:
    return "Hardware Not Running";
    break;
  case kAudioHardwareUnspecifiedError:
    return "Unspecified Error";
    break;
  case kAudioHardwareUnknownPropertyError:
    return "Unknown Property";
    break;
  case kAudioHardwareBadPropertySizeError:
    return "Bad Property Size";
    break;
  case kAudioHardwareIllegalOperationError:
    return "Illegal Operation";
    break;
  case kAudioHardwareBadObjectError:
    return "Bad Object";
    break;
  case kAudioHardwareBadDeviceError:
    return "Bad Device";
    break;
  case kAudioHardwareBadStreamError:
    return "Bad Stream";
    break;
  case kAudioHardwareUnsupportedOperationError:
    return "Unsupported Operation";
    break;
  case kAudioDeviceUnsupportedFormatError:
    return "Unsupported Format";
    break;
  case kAudioDevicePermissionsError:
    return "Permissions Error";
    break;
  default:
    return "Unknown Error";
  }
}

Boolean AudioManager::IsOutputDevice(AudioDeviceID deviceID) {
  OSStatus status;
  // Check if the device has output capabilities
  AudioObjectPropertyAddress streamConfigAddress = {
      kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  AudioBufferList *bufferList = NULL;
  UInt32 bufferListSize = 0;

  status = AudioObjectGetPropertyDataSize(deviceID, &streamConfigAddress, 0,
                                          NULL, &bufferListSize);
  if (status != noErr) {
    return false;
  }

  bufferList = (AudioBufferList *)malloc(bufferListSize);
  if (bufferList == NULL) {
    return false;
  }

  status = AudioObjectGetPropertyData(deviceID, &streamConfigAddress, 0, NULL,
                                      &bufferListSize, bufferList);
  if (status != noErr) {
    free(bufferList);
    return false;
  }

  Boolean isOutputDevice = bufferList->mNumberBuffers > 0;

  free(bufferList);
  return isOutputDevice;
}

std::vector<AudioDeviceID> AudioManager::GetAllAudioDevices() {
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  UInt32 dataSize = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(
      kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
  if (status != noErr) {
    return {};
  }

  UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
  std::vector<AudioDeviceID> audioDevices(deviceCount);

  status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &dataSize, audioDevices.data());
  if (status != noErr) {
    return {};
  }

  std::vector<AudioDeviceID> outputDevices;

  for (const auto &deviceID : audioDevices) {
    if (IsOutputDevice(deviceID)) {
      outputDevices.push_back(deviceID);
    }
  }

  return outputDevices;
}

AudioDeviceID
AudioManager::GetAudioDeviceIdByName(const std::string &deviceName) {
  NSString *deviceNameNS = [NSString stringWithUTF8String:deviceName.c_str()];
  auto devices = GetAllAudioDevices();

  for (const auto &deviceId : devices) {
    if (GetDeviceName(deviceId) == std::string([deviceNameNS UTF8String])) {
      return deviceId;
    }
  }

  return 0;
}

std::string AudioManager::GetDeviceName(AudioDeviceID deviceId) {
  CFStringRef deviceNameCF = NULL;
  UInt32 dataSize = sizeof(CFStringRef);
  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyDeviceNameCFString, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMaster};

  OSStatus status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0,
                                               NULL, &dataSize, &deviceNameCF);
  if (status != noErr) {
    return "";
  }

  NSString *deviceNameNS = (__bridge NSString *)deviceNameCF;
  std::string deviceName = [deviceNameNS UTF8String];
  CFRelease(deviceNameCF);

  return deviceName;
}

Napi::Value
AudioManager::HandleAudioObjectError(const Napi::Env &env, OSStatus status,
                                     const std::string &errorMessage) {
  if (status != noErr) {
    Napi::Error::New(env, errorMessage + ": " + GetErrorDescription(status))
        .ThrowAsJavaScriptException();
    return env.Null();
  }
  return env.Undefined();
}

Napi::Value
AudioManager::GetAllAudioDeviceNames(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  auto devices = GetAllAudioDevices();

  Napi::Array deviceNames = Napi::Array::New(env, devices.size());
  for (size_t i = 0; i < devices.size(); ++i) {
    deviceNames.Set(i, Napi::String::New(env, GetDeviceName(devices[i])));
  }

  return deviceNames;
}

Napi::Value
AudioManager::GetDefaultAudioDeviceName(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  AudioDeviceID defaultOutputDevice;
  GetCurrentDefaultOutputDeviceId(defaultOutputDevice);

  if (defaultOutputDevice == 0) {
    return HandleAudioObjectError(env, kAudioHardwareBadDeviceError,
                                  "Failed to get default output device");
  }

  return Napi::String::New(env, GetDeviceName(defaultOutputDevice));
}

Boolean AudioManager::GetDecibelValue(AudioDeviceID deviceId,
                                      Float32 &decibels) {
  UInt32 decibelsSize;
  Boolean hasDecibels = false;
  OSStatus status;

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeDecibels, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  if (AudioObjectHasProperty(deviceId, &propertyAddress)) {
    status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, NULL,
                                            &decibelsSize);
    if (status == noErr) {
      status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                          &decibelsSize, &decibels);
      if (status == noErr) {
        hasDecibels = true;
      }
    }
  }
  return hasDecibels;
}

Napi::Value AudioManager::StartMonitoring(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (isMonitoring) {
    return env.Null();
  }

  Napi::Function jsCallback = info[0].As<Napi::Function>();
  tsfn = Napi::ThreadSafeFunction::New(env, jsCallback, "AudioManagerCallback",
                                       0, 1);

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  AudioDeviceID defaultOutputDevice;
  GetCurrentDefaultOutputDeviceId(defaultOutputDevice);

  if (defaultOutputDevice == 0) {
    return HandleAudioObjectError(env, kAudioHardwareBadDeviceError,
                                  "Failed to get default output device");
  }

  if (!AudioObjectHasProperty(defaultOutputDevice, &propertyAddress)) {
    return HandleAudioObjectError(
        env, kAudioHardwareUnknownPropertyError,
        "Default device does not has a output volume control");
  }

  OSStatus status = AudioObjectAddPropertyListener(
      defaultOutputDevice, &propertyAddress, VolumeChangeListener, this);

  if (status != noErr) {
    return HandleAudioObjectError(env, status, "Failed to start monitoring");
  }

  isMonitoring = true;
  return env.Null();
}

VolumeListenerUnregisterObject AudioManager::RemoveVolumeListener() {
  VolumeListenerUnregisterObject result;
  if (!isMonitoring) {
    result.errorMessage = "Not monitoring";
    result.status = noErr;
    result.isUnregistered = true;
    return result;
  }

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  AudioDeviceID defaultOutputDevice;
  GetCurrentDefaultOutputDeviceId(defaultOutputDevice);

  if (defaultOutputDevice == 0) {
    result.isUnregistered = false;
    result.status = kAudioHardwareBadDeviceError;
    result.errorMessage = "Failed to get default output device";
    return result;
  }

  if (!AudioObjectHasProperty(defaultOutputDevice, &propertyAddress)) {
    result.isUnregistered = false;
    result.status = kAudioHardwareUnknownPropertyError;
    result.errorMessage = "Default device does not has a output volume control";
    return result;
  }

  OSStatus status = AudioObjectRemovePropertyListener(
      defaultOutputDevice, &propertyAddress, VolumeChangeListener, this);

  if (status != noErr) {
    result.isUnregistered = false;
    result.status = status;
    result.errorMessage = "Failed to stop monitoring";
    return result;
  }

  isMonitoring = false;
  result.isUnregistered = true;
  result.status = noErr;
  result.errorMessage = "";
  return result;
}

Napi::Value AudioManager::StopMonitoring(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  VolumeListenerUnregisterObject result = RemoveVolumeListener();

  if (!result.isUnregistered) {
    return HandleAudioObjectError(env, result.status, result.errorMessage);
  }

  if (tsfn) {
    tsfn.Release();
    tsfn = nullptr;
  }

  return env.Null();
}

Napi::Value AudioManager::SetVolume(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 2 || !info[0].IsString() || !info[1].IsNumber()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  Float32 volume = info[1].As<Napi::Number>().FloatValue();

  AudioDeviceID deviceId = GetAudioDeviceIdByName(deviceName);
  if (deviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  if (!AudioObjectHasProperty(deviceId, &propertyAddress)) {
    return HandleAudioObjectError(
        env, kAudioHardwareUnknownPropertyError,
        "Device does not have a output volume control");
  }

  OSStatus status = AudioObjectSetPropertyData(deviceId, &propertyAddress, 0,
                                               NULL, sizeof(Float32), &volume);
  return HandleAudioObjectError(env, status, "Failed to set volume");
}

Napi::Value AudioManager::GetVolume(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();

  AudioDeviceID deviceId = GetAudioDeviceIdByName(deviceName);
  if (deviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  // Get the volume
  Float32 volume = 0.0f;
  UInt32 dataSize;
  OSStatus status;

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  if (!AudioObjectHasProperty(deviceId, &propertyAddress)) {
    return HandleAudioObjectError(
        env, kAudioHardwareUnknownPropertyError,
        "Device does not have a output volume control");
  }

  status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, NULL,
                                          &dataSize);

  if (status != noErr) {
    return HandleAudioObjectError(env, status, "Failed to get volume size");
  }

  status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                      &dataSize, &volume);

  if (status != noErr) {
    return HandleAudioObjectError(env, status, "Failed to get volume");
  }

  // Float32 decibels;
  // bool hasDecibels = GetDecibelValue(deviceId, decibels);

  Napi::Object volumeData = Napi::Object::New(env);
  volumeData.Set("volume", volume);
  // if (hasDecibels) {
  //   volumeData.Set("decibels", decibels);
  // }

  return Napi::Value(volumeData);
}

OSStatus AudioManager::SetCustomProperty(AudioDeviceID deviceId,
                                         std::string customPropertyString) {
  OSStatus status;
  UInt32 dataSize;

  AudioObjectPropertyAddress customPropertyAddress = {
      kAudioObjectPropertyCustomPropertyInfoList,
      kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};

  if (!AudioObjectHasProperty(deviceId, &customPropertyAddress)) {
    status = kAudioHardwareUnknownPropertyError;
    return status;
  }

  status = AudioObjectGetPropertyDataSize(deviceId, &customPropertyAddress, 0,
                                          NULL, &dataSize);

  if (status != noErr) {
    return status;
  }

  AudioServerPlugInCustomPropertyInfo *customPropertyInfo =
      (AudioServerPlugInCustomPropertyInfo *)(malloc(dataSize));

  if (customPropertyInfo == NULL) {
    return kAudioHardwareUnspecifiedError;
  }

  status = AudioObjectGetPropertyData(deviceId, &customPropertyAddress, 0, NULL,
                                      &dataSize, customPropertyInfo);

  if (status != noErr) {
    free(customPropertyInfo);
    return status;
  }

  AudioObjectPropertyAddress propertyAddress = {
      customPropertyInfo->mSelector, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  if (!AudioObjectHasProperty(deviceId, &propertyAddress)) {
    status = kAudioHardwareUnknownPropertyError;
    free(customPropertyInfo);
    return status;
  }

  Boolean isSettable = false;
  status =
      AudioObjectIsPropertySettable(deviceId, &propertyAddress, &isSettable);

  if (status != noErr) {
    free(customPropertyInfo);
    return status;
  }

  status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, NULL,
                                          &dataSize);

  if (status != noErr) {
    free(customPropertyInfo);
    return status;
  }

  // use customPropertyString to create this value
  CFStringRef customPropertyValue = CFStringCreateWithCString(
      NULL, customPropertyString.c_str(), kCFStringEncodingUTF8);

  status =
      AudioObjectSetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                 sizeof(CFStringRef), &customPropertyValue);

  CFRelease(customPropertyValue);

  free(customPropertyInfo);

  return status;
}

Napi::Value
AudioManager::SetVirtualDeviceCustomProperty(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  OSStatus status;

  if (info.Length() < 2 || !info[0].IsString() || !info[1].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  std::string customPropertyString = info[1].As<Napi::String>().Utf8Value();

  AudioDeviceID deviceId = GetAudioDeviceIdByName(deviceName);
  if (deviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  status = SetCustomProperty(deviceId, customPropertyString);

  if (status != noErr) {
    std::string errorMessage = GetErrorDescription(status);
    Napi::Error::New(env, "Failed to set custom property: " + errorMessage)
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  return Napi::Boolean::New(env, true);
}

Napi::Value AudioManager::SwitchAudioDevice(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();

  AudioDeviceID newDeviceId = GetAudioDeviceIdByName(deviceName);
  if (newDeviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  // Set the default output device
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster};

  OSStatus status =
      AudioObjectSetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, sizeof(AudioDeviceID), &newDeviceId);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to set default output device")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  return env.Null();
}

OSStatus AudioManager::VolumeChangeListener(
    AudioObjectID inObjectID, UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress *inAddresses, void *inClientData) {
  AudioManager *monitor = static_cast<AudioManager *>(inClientData);

  Float32 volume;
  UInt32 dataSize = sizeof(Float32);
  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  OSStatus status = AudioObjectGetPropertyData(inObjectID, &propertyAddress, 0,
                                               NULL, &dataSize, &volume);

  // Float32 decibels;
  // bool hasDecibels = GetDecibelValue(inObjectID, decibels);

  if (status == noErr) {
    // Get the device name
    std::string deviceName = GetDeviceName(inObjectID);
    EventData *eventData = new EventData();
    eventData->eventName = new std::string("volumeChange");
    eventData->device = deviceName;
    eventData->volume = volume;
    // if (hasDecibels) {
    //   eventData->decibels = decibels;
    // }
    if (monitor->tsfn) {
      monitor->tsfn.NonBlockingCall(eventData, callback);
    }
  }

  return noErr;
}

Napi::Value AudioManager::GetMuteState(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  OSStatus status;

  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();

  AudioDeviceID deviceId = GetAudioDeviceIdByName(deviceName);
  if (deviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  UInt32 muted;

  UInt32 muteSize;

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  if (!AudioObjectHasProperty(deviceId, &propertyAddress)) {
    Napi::Error::New(env, "Device does not has a mute control")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, NULL,
                                          &muteSize);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to get mute state size" +
                              GetErrorDescription(status))
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                      &muteSize, &muted);
  if (status != noErr) {
    Napi::Error::New(env,
                     "Failed to get mute state" + GetErrorDescription(status))
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  return Napi::Boolean::New(env, muted == 1);
}

Napi::Value AudioManager::SetMuteState(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  OSStatus status;

  if (info.Length() < 2 || !info[0].IsString() || !info[1].IsBoolean()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  bool muteState = info[1].As<Napi::Boolean>().Value();

  AudioDeviceID deviceId = GetAudioDeviceIdByName(deviceName);
  if (deviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  if (!AudioObjectHasProperty(deviceId, &propertyAddress)) {
    Napi::Error::New(env, "Device does not has a mute control")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  UInt32 muted = muteState ? 1 : 0;
  status = AudioObjectSetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                      sizeof(muted), &muted);
  if (status != noErr) {
    Napi::Error::New(env, "Failed to set mute state")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  return env.Undefined();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  return AudioManager::Init(env, exports);
}

NODE_API_MODULE(AudioManager, Init)
