// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SchnorrSign } from "../../types/MuonTypes.sol";

/// @dev Verifies the digest produced by the real protocol, unlike FakeOracle.
contract NativeBucketStrictOracle {
	bytes32 public expectedHash;
	error UnexpectedOracleHash(bytes32 actual, bytes32 expected);

	function setExpectedHash(bytes32 value) external {
		expectedHash = value;
	}

	function getPrice(address, address) external pure returns (uint256) {
		return 1e18;
	}

	function verifyTSSAndGW(bytes32 value, bytes calldata, SchnorrSign calldata, bytes calldata) external view {
		if (value != expectedHash) revert UnexpectedOracleHash(value, expectedHash);
	}
}
