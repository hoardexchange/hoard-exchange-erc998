// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ContractIERC721ReceiverOld is ERC721, IERC721Receiver {
    bytes4 constant ERC721_RECEIVED_OLD = 0xf0b9e5ba;

    using Counters for Counters.Counter;

    Counters.Counter public _tokenIds;

    uint256 data = 1;

    constructor() public ERC721("NFT_OLD_RECEIVER", "NOR") {}

    function mint721(address _to) public returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        _safeMint(_to, newItemId);
        return newItemId;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC721_RECEIVED_OLD;
    }
}
