export const logger = {
	enabled: true,
	log: (...args: any[]) => {
		if (logger.enabled) {
			console.log(...args)
		}
	},
	disable: () => {
		logger.enabled = false
	},
	enable: () => {
		logger.enabled = true
	},
}
