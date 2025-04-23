// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// Licensed under the SYMM Core Business Source License 1.1
// (c) 2023 Symmetry Labs AG
// https://docs.symm.io/legal-disclaimer/license

pragma solidity ^0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @title ISymmio Interface
 * @notice Defines the interface for the Symmio contract, including the trade transfer functionality.
 */
interface ISymmio {
	/**
	 * @notice Transfers the trade ownership associated with an NFT.
	 * @param from The address of the current owner.
	 * @param to The address of the new owner.
	 * @param tradeId The unique identifier of the trade/NFT.
	 */
	function transferTradeFromNFT(address from, address to, uint256 tradeId) external;
}

/**
 * @title TradeNFT
 * @notice ERC721-based NFT contract that represents the ownership of trades within the Symmio protocol.
 * @dev This contract integrates with the Symmio contract to ensure that trade ownership is kept in sync with NFT transfers.
 */
contract TradeNFT is ERC721Enumerable, Ownable {
	using Counters for Counters.Counter;

	// Custom errors
	error InvalidSymmioAddress();
	error CallerNotSymmio(address caller, address symmioAddress);

	// ==================== STATE VARIABLES ====================
	/// @dev Counter used to generate unique token identifiers. Token IDs start at 1.
	Counters.Counter private _tokenIdCounter;

	/// @notice The instance of the Symmio contract used for synchronizing trade state with NFT transfers.
	ISymmio public symmio;

	/// @dev A flag used to prevent recursive calls during internal transfer operations initiated by Symmio.
	bool private transferInitiatedInSymmio;

	// ==================== EVENTS ====================
	/**
	 * @notice Emitted when a new Trade NFT is minted.
	 * @param owner The address that receives the newly minted NFT.
	 * @param tokenId The unique identifier of the minted NFT.
	 */
	event PositionNFTMinted(address indexed owner, uint256 indexed tokenId);

	/**
	 * @notice Emitted when an NFT is transferred between addresses.
	 * @param tokenId The unique identifier of the transferred NFT.
	 * @param from The address from which the NFT is transferred.
	 * @param to The address to which the NFT is transferred.
	 */
	event PositionNFTTransferred(uint256 indexed tokenId, address indexed from, address indexed to);

	// ==================== CONSTRUCTOR ====================
	/**
	 * @notice Initializes the TradeNFT contract with a reference to the Symmio contract.
	 * @param symmio_ The address of the deployed Symmio contract.
	 * @dev Reverts if `symmio_` is the zero address. The token ID counter starts at 1 to avoid using token ID 0.
	 */
	constructor(address symmio_) ERC721("Trade Ownership NFT", "TRNFT") {
		if (symmio_ == address(0)) revert InvalidSymmioAddress();
		symmio = ISymmio(symmio_);
		_tokenIdCounter.increment();
	}

	// ==================== MODIFIERS ====================
	/**
	 * @notice Restricts function calls to only the Symmio contract.
	 * @dev Reverts if called by an address other than the Symmio contract.
	 */
	modifier onlySymmio() {
		if (msg.sender != address(symmio)) revert CallerNotSymmio(msg.sender, address(symmio));
		_;
	}

	// ==================== EXTERNAL FUNCTIONS ====================

	/**
	 * @notice Mints a new NFT representing a specific trade.
	 * @dev This function can only be called by the Symmio contract. It emits a {PositionNFTMinted} event upon minting.
	 * @param to The address that will own the minted NFT.
	 * @return tokenId The unique identifier of the minted NFT.
	 */
	function mintNFTForTrade(address to) external onlySymmio returns (uint256 tokenId) {
		tokenId = _tokenIdCounter.current();
		_tokenIdCounter.increment();

		_mint(to, tokenId);
		emit PositionNFTMinted(to, tokenId);

		return tokenId;
	}

	/**
	 * @notice Transfers an NFT from one address to another as initiated by the Symmio contract.
	 * @dev This function sets a flag to bypass the usual transfer hook logic to prevent recursive calls.
	 * @param from The current owner's address of the NFT.
	 * @param to The new owner's address for the NFT.
	 * @param tokenId The unique identifier of the NFT to transfer.
	 */
	function transferNFTInitiatedInSymmio(address from, address to, uint256 tokenId) external onlySymmio {
		transferInitiatedInSymmio = true;
		_transfer(from, to, tokenId);
		transferInitiatedInSymmio = false;
	}

	// ==================== INTERNAL FUNCTIONS ====================

	/**
	 * @dev Hook that is called before any token transfer, including minting and burning.
	 * @notice When a user-initiated transfer occurs (i.e., not during minting, burning, or an internal Symmio-initiated transfer),
	 * the function calls the Symmio contract to update the trade ownership state accordingly.
	 * @param from The address which currently owns the token (or zero address during minting).
	 * @param to The address that will receive the token (or zero address during burning).
	 * @param tokenId The unique identifier of the token being transferred.
	 * @param batchSize The number of tokens being transferred (typically 1 for standard transfers).
	 * @dev If `from` and `to` are both non-zero and the transfer was not initiated by the Symmio contract,
	 * it calls `symmio.transferTradeFromNFT` and emits a {PositionNFTTransferred} event.
	 */
	function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
		super._beforeTokenTransfer(from, to, tokenId, batchSize);

		if (from != address(0) && to != address(0) && !transferInitiatedInSymmio) {
			symmio.transferTradeFromNFT(from, to, tokenId);
			emit PositionNFTTransferred(tokenId, from, to);
		}
	}

	// ==================== PUBLIC FUNCTIONS ====================

	/**
	 * @notice Checks whether the contract implements the interface defined by `interfaceId`.
	 * @param interfaceId The identifier of the interface as specified in ERC-165.
	 * @return bool True if the interface is supported, false otherwise.
	 * @dev This contract supports ERC721, ERC721Enumerable, and any additional interfaces implemented by parent contracts.
	 */
	function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
		return (interfaceId == type(IERC721).interfaceId ||
			interfaceId == type(ERC721Enumerable).interfaceId ||
			super.supportsInterface(interfaceId));
	}
}
