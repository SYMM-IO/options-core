import { parseEther } from "ethers"

export function e(value: string | number) {
	return parseEther(value + "")
}
