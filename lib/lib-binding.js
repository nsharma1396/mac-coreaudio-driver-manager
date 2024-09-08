const binary = require("@mapbox/node-pre-gyp");
const path = require("path");
const fs = require("fs");
const { NonDarwinAudioManager } = require("./nonDarwinAudioManager");

const bindingPath = binary.find(
	path.resolve(path.join(__dirname, "../package.json"))
);

const binding =
	fs.existsSync(bindingPath) && ["darwin"].includes(process.platform)
		? require(bindingPath)
		: {
				AudioManager: NonDarwinAudioManager,
		  };

module.exports = binding;
