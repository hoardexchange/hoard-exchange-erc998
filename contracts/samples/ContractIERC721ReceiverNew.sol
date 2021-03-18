// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract ContractIERC721ReceiverNew is IERC721Receiver {
    bytes4 constant ERC721_RECEIVED = 0xcd740db5;

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC721_RECEIVED;
    }
}
