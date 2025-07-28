// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import { SchnorrSign } from "../types/MuonTypes.sol";

contract FakeOracle {
	function getPrice(address token, address collateral) external view returns (uint256) {
		return 1e18;
	}

	function verifyTSSAndGW(bytes32 _data, bytes calldata _reqId, SchnorrSign calldata _signature, bytes calldata _gatewaySignature) external view {}
}
