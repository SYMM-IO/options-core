import { ethers } from "hardhat";

export function e(value: string | number) {
	return ethers.parseEther(value + "")
}
