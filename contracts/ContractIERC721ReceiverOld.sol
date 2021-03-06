pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract ContractIERC721ReceiverOld is IERC721Receiver {
    bytes4 constant ERC721_RECEIVED_OLD = 0xf0b9e5ba;

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC721_RECEIVED_OLD;
    }
}
