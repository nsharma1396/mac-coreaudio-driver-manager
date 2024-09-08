#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/AudioHardwareBase.h>
#include <CoreAudio/AudioServerPlugin.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <napi.h>
#include <stdio.h>

struct EventData {
  std::string *eventName = nullptr;
  std::string device;
  float volume;
};

auto callback = [](Napi::Env env, Napi::Function jsCallback,
                   EventData *eventData) {
  Napi::Object eventResult = Napi::Object::New(env);
  eventResult.Set("eventName", (*(eventData->eventName)));
  eventResult.Set("device", eventData->device);
  eventResult.Set("volume", eventData->volume);
  jsCallback.Call({eventResult});
  delete eventData->eventName;
  delete eventData;
};

class AudioMonitor : public Napi::ObjectWrap<AudioMonitor> {
public:
  static Napi::Object Init(Napi::Env env, Napi::Object exports);
  AudioMonitor(const Napi::CallbackInfo &info);

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

  static std::string GetErrorDescription(OSStatus error);

  static OSStatus SetCustomProperty(AudioDeviceID deviceId,
                                    std::string customPropertyString);

  static OSStatus
  VolumeChangeListener(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                       const AudioObjectPropertyAddress *inAddresses,
                       void *inClientData);

  Napi::ThreadSafeFunction tsfn;
  AudioObjectID defaultOutputDevice;
  bool isMonitoring;
};

Napi::FunctionReference AudioMonitor::constructor;

Napi::Object AudioMonitor::Init(Napi::Env env, Napi::Object exports) {
  Napi::Function func = DefineClass(
      env, "AudioMonitor",
      {InstanceMethod("startVolumeMonitoring", &AudioMonitor::StartMonitoring),
       InstanceMethod("stopVolumeMonitoring", &AudioMonitor::StopMonitoring),
       InstanceMethod("setVolume", &AudioMonitor::SetVolume),
       InstanceMethod("getVolume", &AudioMonitor::GetVolume),
       InstanceMethod("switchAudioDevice", &AudioMonitor::SwitchAudioDevice),
       InstanceMethod("getDefaultAudioDeviceName",
                      &AudioMonitor::GetDefaultAudioDeviceName),
       InstanceMethod("getAllAudioDeviceNames",
                      &AudioMonitor::GetAllAudioDeviceNames),
       InstanceMethod("setVirtualDeviceCustomProperty",
                      &AudioMonitor::SetVirtualDeviceCustomProperty),
       InstanceMethod("getMuteState", &AudioMonitor::GetMuteState),
       InstanceMethod("setMuteState", &AudioMonitor::SetMuteState)});

  constructor = Napi::Persistent(func);
  constructor.SuppressDestruct();

  exports.Set("AudioMonitor", func);
  return exports;
}

AudioMonitor::AudioMonitor(const Napi::CallbackInfo &info)
    : Napi::ObjectWrap<AudioMonitor>(info), isMonitoring(false) {
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster};

  UInt32 dataSize = sizeof(AudioDeviceID);
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                             NULL, &dataSize, &defaultOutputDevice);
}

// Utility function to get AudioDeviceID from device name
OSStatus GetAudioDeviceIdByName(NSString *deviceName, AudioDeviceID *deviceId) {
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMaster};

  UInt32 dataSize = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(
      kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
  if (status != noErr) {
    return status;
  }

  UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
  AudioDeviceID *devices = (AudioDeviceID *)malloc(dataSize);

  status = AudioObjectGetPropertyData(
      kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize, devices);
  if (status != noErr) {
    free(devices);
    return status;
  }

  for (UInt32 i = 0; i < deviceCount; ++i) {
    CFStringRef deviceNameCF = NULL;
    dataSize = sizeof(deviceNameCF);
    propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString;

    status = AudioObjectGetPropertyData(devices[i], &propertyAddress, 0, NULL,
                                        &dataSize, &deviceNameCF);
    if (status == noErr) {
      NSString *currentDeviceName = (__bridge NSString *)deviceNameCF;
      if ([currentDeviceName isEqualToString:deviceName]) {
        *deviceId = devices[i];
        CFRelease(deviceNameCF);
        free(devices);
        return noErr;
      }
      CFRelease(deviceNameCF);
    }
  }

  free(devices);
  return kAudioHardwareUnknownPropertyError;
}

// get all audio devices
Napi::Value
AudioMonitor::GetAllAudioDeviceNames(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMaster};

  UInt32 dataSize = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(
      kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
  if (status != noErr) {
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return Napi::Array::New(env);
  }

  UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
  AudioDeviceID *audioDevices = (AudioDeviceID *)(malloc(dataSize));

  status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &dataSize, audioDevices);
  if (status != noErr) {
    free(audioDevices);
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return Napi::Array::New(env);
  }

  Napi::Array deviceNames = Napi::Array::New(env, deviceCount);

  for (UInt32 i = 0; i < deviceCount; ++i) {
    CFStringRef deviceNameCF = NULL;
    dataSize = sizeof(CFStringRef);
    propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString;

    status = AudioObjectGetPropertyData(audioDevices[i], &propertyAddress, 0,
                                        NULL, &dataSize, &deviceNameCF);
    if (status == noErr) {
      NSString *currentDeviceName = (__bridge NSString *)deviceNameCF;
      std::string deviceName = [currentDeviceName UTF8String];
      deviceNames.Set(i, Napi::String::New(env, deviceName));
      CFRelease(deviceNameCF);
    }
  }

  free(audioDevices);

  return deviceNames;
}

Napi::Value
AudioMonitor::GetDefaultAudioDeviceName(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster};

  UInt32 dataSize = sizeof(AudioDeviceID);
  AudioDeviceID defaultOutputDevice;

  OSStatus status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &dataSize, &defaultOutputDevice);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to get default output device")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString;
  CFStringRef deviceNameCF = NULL;
  dataSize = sizeof(CFStringRef);

  status = AudioObjectGetPropertyData(defaultOutputDevice, &propertyAddress, 0,
                                      NULL, &dataSize, &deviceNameCF);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to get default output device name")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  NSString *deviceNameNS = (__bridge NSString *)deviceNameCF;
  std::string deviceName = [deviceNameNS UTF8String];
  CFRelease(deviceNameCF);

  return Napi::String::New(env, deviceName);
}

Napi::Value AudioMonitor::StartMonitoring(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (isMonitoring) {
    return env.Null();
  }

  Napi::Function jsCallback = info[0].As<Napi::Function>();
  tsfn = Napi::ThreadSafeFunction::New(env, jsCallback, "AudioMonitorCallback",
                                       0, 1);

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  OSStatus status = AudioObjectAddPropertyListener(
      defaultOutputDevice, &propertyAddress, VolumeChangeListener, this);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to start monitoring")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  isMonitoring = true;
  return env.Null();
}

Napi::Value AudioMonitor::StopMonitoring(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (!isMonitoring) {
    return env.Null();
  }

  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  OSStatus status = AudioObjectRemovePropertyListener(
      defaultOutputDevice, &propertyAddress, VolumeChangeListener, this);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to stop monitoring")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  isMonitoring = false;
  tsfn.Release();
  return env.Null();
}

Napi::Value AudioMonitor::SetVolume(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 2 || !info[0].IsString() || !info[1].IsNumber()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  Float32 volume = info[1].As<Napi::Number>().FloatValue();

  NSString *deviceNameNS = [NSString stringWithUTF8String:deviceName.c_str()];

  AudioDeviceID deviceId = 0;
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMaster};

  UInt32 dataSize = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(
      kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
  if (status != noErr) {
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
  AudioDeviceID *audioDevices = (AudioDeviceID *)(malloc(dataSize));

  status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &dataSize, audioDevices);
  if (status != noErr) {
    free(audioDevices);
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  for (UInt32 i = 0; i < deviceCount; ++i) {
    CFStringRef deviceNameCF = NULL;
    dataSize = sizeof(CFStringRef);
    propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString;

    status = AudioObjectGetPropertyData(audioDevices[i], &propertyAddress, 0,
                                        NULL, &dataSize, &deviceNameCF);
    if (status == noErr) {
      NSString *currentDeviceName = (__bridge NSString *)deviceNameCF;
      if ([currentDeviceName isEqualToString:deviceNameNS]) {
        deviceId = audioDevices[i];
        CFRelease(deviceNameCF);
        break;
      }
      CFRelease(deviceNameCF);
    }
  }

  free(audioDevices);

  if (deviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  // Check if the device has a main volume control
  propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
  propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
  propertyAddress.mElement = kAudioObjectPropertyElementMaster;

  if (!AudioObjectHasProperty(deviceId, &propertyAddress)) {
    Napi::Error::New(env, "Device does not have a main volume control")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // Set the volume
  status = AudioObjectSetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                      sizeof(Float32), &volume);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to set volume").ThrowAsJavaScriptException();
    return env.Null();
  }

  return env.Null();
}

Napi::Value AudioMonitor::GetVolume(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  NSString *deviceNameNS = [NSString stringWithUTF8String:deviceName.c_str()];

  AudioDeviceID deviceId = 0;
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMaster};

  UInt32 dataSize = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(
      kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
  if (status != noErr) {
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
  AudioDeviceID *audioDevices = (AudioDeviceID *)(malloc(dataSize));

  status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &dataSize, audioDevices);
  if (status != noErr) {
    free(audioDevices);
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  for (UInt32 i = 0; i < deviceCount; ++i) {
    CFStringRef deviceNameCF = NULL;
    dataSize = sizeof(CFStringRef);
    propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString;

    status = AudioObjectGetPropertyData(audioDevices[i], &propertyAddress, 0,
                                        NULL, &dataSize, &deviceNameCF);
    if (status == noErr) {
      NSString *currentDeviceName = (__bridge NSString *)deviceNameCF;
      if ([currentDeviceName isEqualToString:deviceNameNS]) {
        deviceId = audioDevices[i];
        CFRelease(deviceNameCF);
        break;
      }
      CFRelease(deviceNameCF);
    }
  }

  free(audioDevices);

  if (deviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  // Get the volume
  Float32 volume = 0.0f;
  propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
  propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
  propertyAddress.mElement = kAudioObjectPropertyElementMaster;

  dataSize = sizeof(Float32);
  status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                      &dataSize, &volume);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to get volume").ThrowAsJavaScriptException();
    return env.Null();
  }

  return Napi::Number::New(env, volume);
}

std::string AudioMonitor::GetErrorDescription(OSStatus error) {
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

OSStatus AudioMonitor::SetCustomProperty(AudioDeviceID deviceId,
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

  status = AudioObjectGetPropertyData(deviceId, &customPropertyAddress, 0, NULL,
                                      &dataSize, customPropertyInfo);

  if (status != noErr) {
    return status;
  }

  AudioObjectPropertyAddress propertyAddress = {
      customPropertyInfo->mSelector, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  if (!AudioObjectHasProperty(deviceId, &propertyAddress)) {
    status = kAudioHardwareUnknownPropertyError;
    return status;
  }

  Boolean isSettable = false;
  status =
      AudioObjectIsPropertySettable(deviceId, &propertyAddress, &isSettable);

  if (status != noErr) {
    return status;
  }

  status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, NULL,
                                          &dataSize);

  if (status != noErr) {
    return status;
  }

  CFStringRef canBeDefaultKey = CFStringCreateWithCString(
      NULL, customPropertyString.c_str(), kCFStringEncodingUTF8);

  status = AudioObjectSetPropertyData(deviceId, &propertyAddress, 0, NULL,
                                      sizeof(CFStringRef), &canBeDefaultKey);
  return status;
}

Napi::Value
AudioMonitor::SetVirtualDeviceCustomProperty(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  OSStatus status;

  if (info.Length() < 2 || !info[0].IsString() || !info[1].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  NSString *deviceNameNS = [NSString stringWithUTF8String:deviceName.c_str()];
  std::string customPropertyString = info[1].As<Napi::String>().Utf8Value();

  AudioDeviceID deviceId;
  status = GetAudioDeviceIdByName(deviceNameNS, &deviceId);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to get audio device ID")
        .ThrowAsJavaScriptException();
    return env.Null();
  }
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

Napi::Value AudioMonitor::SwitchAudioDevice(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  NSString *deviceNameNS = [NSString stringWithUTF8String:deviceName.c_str()];

  AudioDeviceID newDeviceId = 0;
  AudioObjectPropertyAddress propertyAddress = {
      kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMaster};

  UInt32 dataSize = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(
      kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize);
  if (status != noErr) {
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
  AudioDeviceID *audioDevices = (AudioDeviceID *)(malloc(dataSize));

  status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &dataSize, audioDevices);
  if (status != noErr) {
    free(audioDevices);
    Napi::Error::New(env, "Failed to get audio devices")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  for (UInt32 i = 0; i < deviceCount; ++i) {
    CFStringRef deviceNameCF = NULL;
    dataSize = sizeof(CFStringRef);
    propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString;

    status = AudioObjectGetPropertyData(audioDevices[i], &propertyAddress, 0,
                                        NULL, &dataSize, &deviceNameCF);
    if (status == noErr) {
      NSString *currentDeviceName = (__bridge NSString *)deviceNameCF;
      if ([currentDeviceName isEqualToString:deviceNameNS]) {
        newDeviceId = audioDevices[i];
        CFRelease(deviceNameCF);
        break;
      }
      CFRelease(deviceNameCF);
    }
  }

  free(audioDevices);

  if (newDeviceId == 0) {
    Napi::Error::New(env, "Device not found").ThrowAsJavaScriptException();
    return env.Null();
  }

  // Set the default output device
  propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
  propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
  propertyAddress.mElement = kAudioObjectPropertyElementMaster;

  status =
      AudioObjectSetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, sizeof(AudioDeviceID), &newDeviceId);

  if (status != noErr) {
    Napi::Error::New(env, "Failed to set default output device")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  return env.Null();
}

OSStatus AudioMonitor::VolumeChangeListener(
    AudioObjectID inObjectID, UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress *inAddresses, void *inClientData) {
  AudioMonitor *monitor = static_cast<AudioMonitor *>(inClientData);

  Float32 volume;
  UInt32 dataSize = sizeof(Float32);
  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

  OSStatus status = AudioObjectGetPropertyData(inObjectID, &propertyAddress, 0,
                                               NULL, &dataSize, &volume);

  if (status == noErr) {
    // Get the device name
    CFStringRef deviceNameCF = NULL;
    dataSize = sizeof(CFStringRef);
    propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString;

    status = AudioObjectGetPropertyData(inObjectID, &propertyAddress, 0, NULL,
                                        &dataSize, &deviceNameCF);
    if (status == noErr) {
      NSString *deviceNameNS = (__bridge NSString *)deviceNameCF;
      std::string deviceName = [deviceNameNS UTF8String];
      // print volume to console
      printf("Volume: %f\n", volume);
      EventData *eventData = new EventData();
      eventData->eventName = new std::string("volumeChange");
      eventData->device = deviceName;
      eventData->volume = volume;
      monitor->tsfn.NonBlockingCall(eventData, callback);
    }
  }

  return noErr;
}

Napi::Value AudioMonitor::GetMuteState(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  NSString *deviceNameNS = [NSString stringWithUTF8String:deviceName.c_str()];

  AudioDeviceID deviceId;
  OSStatus status = GetAudioDeviceIdByName(deviceNameNS, &deviceId);
  if (status != noErr) {
    Napi::Error::New(env, "Failed to get audio device ID")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  Boolean muted;
  UInt32 muteSize = sizeof(muted);
  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

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

  return Napi::Boolean::New(env, muted);
}

Napi::Value AudioMonitor::SetMuteState(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 2 || !info[0].IsString() || !info[1].IsBoolean()) {
    Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
    return env.Null();
  }

  std::string deviceName = info[0].As<Napi::String>().Utf8Value();
  bool muteState = info[1].As<Napi::Boolean>().Value();
  NSString *deviceNameNS = [NSString stringWithUTF8String:deviceName.c_str()];

  AudioDeviceID deviceId;
  OSStatus status = GetAudioDeviceIdByName(deviceNameNS, &deviceId);
  if (status != noErr) {
    Napi::Error::New(env, "Failed to get audio device ID")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  UInt32 muted = muteState ? 1 : 0;
  AudioObjectPropertyAddress propertyAddress = {
      kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMaster};

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
  return AudioMonitor::Init(env, exports);
}

NODE_API_MODULE(audiomonitor, Init)
