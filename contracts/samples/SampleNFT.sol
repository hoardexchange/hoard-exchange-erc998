// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../interfaces/IERC721ReceiverOld.sol";

contract SampleNFT is ERC721 {
    using Address for address;
    using Counters for Counters.Counter;

    Counters.Counter public _tokenIds;
    mapping(string => bool) public hashes;

    uint256 data = 1;

    //old version
    bytes4 constant ERC721_RECEIVED_OLD = 0xf0b9e5ba;

    constructor() ERC721("Sample NFT", "NFT") {}

    /// wrapper on minting new 721
    function mint721(address _to, string memory _hash)
        public
        returns (uint256)
    {
        require(hashes[_hash] != true);
        hashes[_hash] = true;

        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        _safeMint(_to, newItemId);
        return newItemId;
    }

    function safeTransferFromOld(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "SampleNFT: transfer caller is not owner nor approved"
        );

        _transfer(from, to, tokenId);

        require(
            _checkOnERC721ReceivedOld(from, to, tokenId, _data),
            "SampleNFT: transfer to non ERC721Receiver implementer"
        );
    }

    /// @dev mocked for ComposableTopDown safeTransferChild(4)
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        safeTransferFrom(from, to, tokenId, abi.encode(data));
    }

    function _checkOnERC721ReceivedOld(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata =
            to.functionCall(
                abi.encodeWithSelector(
                    IERC721ReceiverOld(to).onERC721Received.selector,
                    from,
                    tokenId,
                    _data
                ),
                "SampleNFT: transfer to non ERC721Receiver implementer"
            );
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == ERC721_RECEIVED_OLD);
    }
}
