# mac-coreaudio-driver-manager

AudioManager.js is a Node.js addon library that allows you to monitor and control audio devices. It supports various functionalities such as starting/stopping volume monitoring, setting/getting volume levels, switching audio devices, and updating custom property in the driver.
_Only output devices are supported currently_

## Installation

You can install mac-coreaudio-driver-manager using npm:

```bash
npm install mac-coreaudio-driver-manager
```

## API Usage

mac-coreaudio-driver-manager exports an `AudioManager` class that provides various methods to interact with audio devices.

```typescript
import AudioManager from "mac-coreaudio-driver-manager";

OR;

const AudioManager = require("mac-coreaudio-driver-manager");
```

### Class: `AudioManager`

#### Methods

- `startVolumeMonitoring(volumeChangeCallback: (event: IVolumeChangeEvent) => void): void`

  - Starts monitoring the volume of the audio devices.
  - `volumeChangeCallback`: A callback function that is called when a volume change event occurs.
  - throws an error if operation is not supported

- `stopVolumeMonitoring(): void`

  - Stops monitoring the volume of the audio devices.
  - throws an error if operation is not supported

- `setVolume(deviceName: string, volume: number): void`

  - Sets the volume of the audio device with the name `deviceName` to `volume`.
  - throws an error if operation is not supported

- `getVolume(deviceName: string): {volume: number; decibels: number}`

  - Returns the volume of the audio device with the name `deviceName`.
  - throws an error if operation is not supported

- `getMuteState(deviceName: string) => boolean`

  - Gets the mute state for the device with the `deviceName`
  - throws an error if operation is not supported

- `setMuteState(deviceName: string, isMuted: boolean) => void`

  - Sets the mute state for the device with the `deviceName`
  - throws an error if operation is not supported

- `switchAudioDevice(deviceName: string): void`

  - Switches the default audio device to the device with the name `deviceName`.
  - throws an error if operation is not supported

- `getDefaultAudioDeviceName(): string`

  - Returns the name of the default audio device. (Only output devices are returned currently)
  - throws an error if operation is not supported

- `getAllAudioDeviceNames(): string[]`

  - Returns the names of all audio devices.
  - throws an error if operation is not supported

- `setVirtualDeviceCustomProperty(deviceName: string, value: string): void`
  - Finds the first custom property of the virtual device `deviceName` and attempts to set its value to `value`.

### Interfaces: `IVolumeChangeEvent`

```typescript
export interface IVolumeChangeEvent {
	/**
	 * @description Name of the event.
	 */
	eventName: "volumeChange";
	/**
	 * @description Name of the audio device.
	 */
	device: string;
	/**
	 * @description Volume level of the audio device.
	 */
	volume: number;
	/**
	 * @description Decibel level of the audio device.
	 **/
	decibels?: number;
}
```

### Example Usage

Here's a basic example of how to use the `AudioManager` class:

```javascript
const AudioManager = require("AudioManager");

const AudioManager = new AudioManager();

// Start monitoring volume changes
AudioManager.startVolumeMonitoring((event) => {
	console.log(`Volume changed on device ${event.device}: ${event.volume}`);
});

// Set volume for a specific device
AudioManager.setVolume("Device A", 50);

// Get volume for a specific device
const volume = AudioManager.getVolume("Device A");
console.log(`Volume for Device A: ${volume}`);

// Switch to a different audio device
AudioManager.switchAudioDevice("Device B");

// Get the default audio device name
const defaultDevice = AudioManager.getDefaultAudioDeviceName();
console.log(`Default audio device: ${defaultDevice}`);

// Get all audio device names
const allDevices = AudioManager.getAllAudioDeviceNames();
console.log(`All audio devices: ${allDevices.join(", ")}`);

// Set a custom property for a virtual device
AudioManager.setVirtualDeviceCustomProperty("Virtual Device", "Custom Value");

// Stop monitoring volume changes
AudioManager.stopVolumeMonitoring();
```
