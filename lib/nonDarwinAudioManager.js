const platformCompatibilityWarning = () =>
	console.log(`WARNING: Package only supports darwin platform`);
class NonDarwinAudioManager {
	setVolume() {
		platformCompatibilityWarning();
	}

	getVolume() {
		platformCompatibilityWarning();
	}

	switchAudioDevice() {
		platformCompatibilityWarning();
	}

	getAllAudioDeviceNames() {
		platformCompatibilityWarning();
	}

	startVolumeMonitoring() {
		platformCompatibilityWarning();
	}

	stopVolumeMonitoring() {
		platformCompatibilityWarning();
	}

	getDefaultAudioDeviceName() {
		platformCompatibilityWarning();
	}

	setVirtualDeviceCustomProperty() {
		platformCompatibilityWarning();
	}

	getMuteState() {
		platformCompatibilityWarning();
	}

	setMuteState() {
		platformCompatibilityWarning();
	}
}
exports.NonDarwinAudioManager = NonDarwinAudioManager;
