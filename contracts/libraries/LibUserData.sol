// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/AppStorage.sol";

library LibUserData {
	function addCounter(bytes memory _data, uint256 _counter) internal pure returns (bytes memory) {
		bytes32 counterBytes = bytes32(uint256(_counter));

		bytes memory dataWithCounter = abi.encodePacked(_data, counterBytes);

		return dataWithCounter;
	}

	function getCounter(bytes memory dataWithCounter) internal pure returns (uint256) {
		require(dataWithCounter.length >= 32, "Not enough bytes");
		bytes32 counterBytes;
		assembly {
			counterBytes := mload(add(dataWithCounter, sub(dataWithCounter, 32)))
		}
		return uint256(counterBytes);
	}

	function getDataWithoutCounter(bytes memory dataWithCounter) internal pure returns (bytes memory) {
		require(dataWithCounter.length > 32, "Not enough bytes");

		uint256 dataLength = dataWithCounter.length - 32;
		bytes memory data = new bytes(dataLength);

		for (uint256 i = 0; i < dataLength; i++) {
			data[i] = dataWithCounter[i];
		}

		return data;
	}

	function incrementCounter(bytes memory dataWithCounter) internal pure returns (bytes memory) {
		require(dataWithCounter.length > 32, "Not enough bytes");

		uint256 currentCounter = getCounter(dataWithCounter);
		uint256 newCounter = currentCounter + 1;

		bytes memory newData = getDataWithoutCounter(dataWithCounter);
		bytes memory data = addCounter(newData, newCounter);
		return data;
	}
}
