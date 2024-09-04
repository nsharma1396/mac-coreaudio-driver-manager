const binary = require("@mapbox/node-pre-gyp");
const path = require("path");
const fs = require("fs");

const platformCompatibilityWarning = () =>
	console.log(`WARNING: Package only supports darwin platform`);

const bindingPath = binary.find(
	path.resolve(path.join(__dirname, "../package.json"))
);

const binding =
	fs.existsSync(bindingPath) && ["darwin"].includes(process.platform)
		? require(bindingPath)
		: {
				setVolume: platformCompatibilityWarning,
				getVolume: platformCompatibilityWarning,
				switchAudioDevice: platformCompatibilityWarning,
				getAllAudioDeviceNames: platformCompatibilityWarning,
				startVolumeMonitoring: platformCompatibilityWarning,
				stopVolumeMonitoring: platformCompatibilityWarning,
				getDefaultAudioDeviceName: platformCompatibilityWarning,
				setVirtualDeviceCustomProperty: platformCompatibilityWarning,
		  };

module.exports = binding;
