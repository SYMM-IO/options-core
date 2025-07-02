// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// Licensed under the SYMM Core Business Source License 1.1
// (c) 2023 Symmetry Labs AG
// https://docs.symm.io/legal-disclaimer/license
pragma solidity ^0.8.19;

/**
 * @title  TradeNFT
 * @notice ERC721-based NFT contract representing trade ownership within the Symmio protocol.
 *         Each NFT corresponds to a specific trade, with ownership transfers automatically
 *         synchronized between the NFT contract and the underlying Symmio protocol state.
 *
 * @dev    Core features include:
 *         • ERC721 enumerable NFTs representing individual trades
 *         • Bidirectional synchronization with Symmio protocol trade ownership
 *         • Mint-only access restricted to Symmio contract
 *         • Recursive transfer prevention during internal operations
 *         • Automatic trade ownership updates on NFT transfers
 *
 *         The contract maintains perfect consistency between NFT ownership and
 *         trade ownership in the Symmio protocol through coordinated transfer hooks.
 */

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/* ────────────────────────── External Interfaces ────────────────────────── */

/**
 * @title  ISymmio Interface
 * @notice Defines the interface for the Symmio contract trade transfer functionality.
 */
interface ISymmio {
	/**
	 * @notice Transfer trade ownership associated with an NFT.
	 * @param from    Current trade owner address.
	 * @param to      New trade owner address.
	 * @param tradeId Unique identifier of the trade/NFT.
	 */
	function transferTradeFromNFT(address from, address to, uint256 tradeId) external;
}

contract TradeNFT is ERC721Enumerable, Ownable {
	using Counters for Counters.Counter;

	/* ──────────────────────── Storage Variables ──────────────────────── */

	/// @notice Symmio contract instance for synchronizing trade ownership state.
	ISymmio public symmio;

	/// @notice Flag to prevent recursive calls during Symmio-initiated transfers.
	bool private transferInitiatedInSymmio;

	/* ─────────────────────────────── Events ─────────────────────────────── */

	/**
	 * @notice Emitted when a new Trade NFT is minted.
	 * @param owner   Address receiving the newly minted NFT.
	 * @param tokenId Unique identifier of the minted NFT.
	 */
	event TradeNFTMinted(address indexed owner, uint256 indexed tokenId);

	/**
	 * @notice Emitted when an NFT is transferred between addresses.
	 * @param tokenId Unique identifier of the transferred NFT.
	 * @param from    Address from which the NFT is transferred.
	 * @param to      Address to which the NFT is transferred.
	 */
	event TradeNFTTransferred(uint256 indexed tokenId, address indexed from, address indexed to);

	/* ─────────────────────────────── Errors ─────────────────────────────── */

	error InvalidSymmioAddress(); // Symmio address is zero
	error UnauthorizedSender(address sender, address requiredSender);

	/* ─────────────────────────── Initialization ─────────────────────────── */

	/**
	 * @notice Initialize the TradeNFT contract with Symmio integration.
	 * @param symmio_ Address of the deployed Symmio contract.
	 *
	 * @dev Reverts if `symmio_` is the zero address. NFTs use token IDs that
	 *      correspond directly to trade IDs in the Symmio protocol.
	 */
	constructor(address symmio_) ERC721("Trade Ownership NFT", "TRNFT") {
		if (symmio_ == address(0)) revert InvalidSymmioAddress();
		symmio = ISymmio(symmio_);
	}

	/* ───────────────────────── External Functions ───────────────────────── */

	/**
	 * @notice Mint a new NFT representing a specific trade.
	 * @param partyA      Address that will own the minted NFT.
	 * @param tradeId Trade ID from Symmio protocol (becomes NFT token ID).
	 *
	 * @dev Only callable by the Symmio contract. Emits TradeNFTMinted event.
	 */
	function mintNFTForTrade(address partyA, uint256 tradeId) external onlySymmio {
		_mint(partyA, tradeId);
		emit TradeNFTMinted(partyA, tradeId);
	}

	/**
	 * @notice Transfer NFT as initiated by the Symmio contract.
	 * @param from    Current owner address of the NFT.
	 * @param to      New owner address for the NFT.
	 * @param tokenId Unique identifier of the NFT to transfer.
	 *
	 * @dev Sets flag to bypass transfer hook logic and prevent recursive calls
	 *      during Symmio-initiated transfers.
	 */
	function transferNFTInitiatedInSymmio(address from, address to, uint256 tokenId) external onlySymmio {
		transferInitiatedInSymmio = true;
		_transfer(from, to, tokenId);
		transferInitiatedInSymmio = false;
	}

	/* ────────────────────────── Public Functions ────────────────────────── */

	/**
	 * @notice Check interface support for ERC-165 compatibility.
	 * @param interfaceId Interface identifier to check.
	 * @return bool True if the interface is supported, false otherwise.
	 *
	 * @dev Supports ERC721, ERC721Enumerable, and parent contract interfaces.
	 */
	function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
		return (interfaceId == type(IERC721).interfaceId ||
			interfaceId == type(ERC721Enumerable).interfaceId ||
			super.supportsInterface(interfaceId));
	}

	/* ───────────────────────── Internal Functions ───────────────────────── */

	/**
	 * @dev Hook called before any token transfer, including minting and burning.
	 *      Synchronizes trade ownership with Symmio protocol during user-initiated transfers.
	 *
	 * @param from      Address currently owning the token (zero during minting).
	 * @param to        Address receiving the token (zero during burning).
	 * @param tokenId   Unique identifier of the token being transferred.
	 * @param batchSize Number of tokens being transferred (typically 1).
	 *
	 * @dev When both `from` and `to` are non-zero and the transfer was not initiated
	 *      by Symmio, calls `symmio.transferTradeFromNFT` to update trade ownership
	 *      and emits TradeNFTTransferred event.
	 */
	function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
		super._beforeTokenTransfer(from, to, tokenId, batchSize);

		if (from != address(0) && to != address(0) && !transferInitiatedInSymmio) {
			symmio.transferTradeFromNFT(from, to, tokenId);
			emit TradeNFTTransferred(tokenId, from, to);
		}
	}

	/* ─────────────────────────────── Modifiers ─────────────────────────────── */

	/// @notice Restricts function calls to only the Symmio contract.
	modifier onlySymmio() {
		if (msg.sender != address(symmio)) revert UnauthorizedSender(msg.sender, address(symmio));
		_;
	}
}
