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
}

declare class AudioManager {
	/**
	 * @description Starts monitoring the volume of the audio devices.
	 */
	startVolumeMonitoring: (
		volumeChangeCallback: (event: IVolumeChangeEvent) => void
	) => void;
	/**
	 * @description Stops monitoring the volume of the audio devices.
	 */
	stopVolumeMonitoring: () => void;
	/**
	 * @description Sets the volume of the audio device with the name `deviceName` to `volume`.
	 */
	setVolume: (deviceName: string, volume: number) => void;
	/**
	 * @description Returns the volume of the audio device with the name `deviceName`.
	 */
	getVolume: (deviceName: string) => void;
	/**
	 * @description Returns whether the audio device with the name `deviceName` is muted.
	 */
	getMuteState: (deviceName: string) => boolean;
	/**
	 * @description Mutes the audio device with the name `deviceName`.
	 */
	setMuteState: (deviceName: string, isMuted: boolean) => void;
	/**
	 * @description Switches the default audio device to the device with the name `deviceName`.
	 */
	switchAudioDevice: (deviceName: string) => void;
	/**
	 * @description Returns the name of the default audio device. [only output devices are returned currently]
	 */
	getDefaultAudioDeviceName: () => string;
	/**
	 * @description Returns the names of all audio devices.
	 */
	getAllAudioDeviceNames: () => string[];
	/**
	 * @description Finds the first custom property of the virtual device `deviceName` and attempts to set its value to `value`.
	 */
	setVirtualDeviceCustomProperty: (deviceName: string, value: string) => void;
}

export default AudioManager;
