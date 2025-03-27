// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library LibUserData {
	// Custom errors
	error InsufficientBytes(uint256 providedLength, uint256 requiredLength);

	function addCounter(bytes memory _data, uint256 _counter) internal pure returns (bytes memory) {
		bytes32 counterBytes = bytes32(uint256(_counter));
		bytes memory dataWithCounter = abi.encodePacked(_data, counterBytes);
		return dataWithCounter;
	}

	function getCounter(bytes memory dataWithCounter) internal pure returns (uint256) {
		if (dataWithCounter.length < 32) revert InsufficientBytes(dataWithCounter.length, 32);

		bytes32 counterBytes;
		assembly {
			counterBytes := mload(add(dataWithCounter, sub(mload(dataWithCounter), 32)))
		}
		return uint256(counterBytes);
	}

	function getDataWithoutCounter(bytes memory dataWithCounter) internal pure returns (bytes memory) {
		if (dataWithCounter.length <= 32) revert InsufficientBytes(dataWithCounter.length, 33);

		uint256 dataLength = dataWithCounter.length - 32;
		bytes memory data = new bytes(dataLength);
		for (uint256 i = 0; i < dataLength; i++) {
			data[i] = dataWithCounter[i];
		}
		return data;
	}

	function incrementCounter(bytes memory dataWithCounter) internal pure returns (bytes memory) {
		if (dataWithCounter.length <= 32) revert InsufficientBytes(dataWithCounter.length, 33);

		uint256 currentCounter = getCounter(dataWithCounter);
		uint256 newCounter = currentCounter + 1;
		bytes memory newData = getDataWithoutCounter(dataWithCounter);
		bytes memory data = addCounter(newData, newCounter);
		return data;
	}
}
