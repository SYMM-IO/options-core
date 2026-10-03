// Hardhat 3 options always have a default. "" stands for "not given" on options that used to be required.
export function requireArg(value: string, name: string): string {
	if (value === "") throw new Error(`Missing required option --${name}`)
	return value
}
