// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "../ComposableTopDownERC1155Enumerable.sol";


contract ComposableTopDownERC1155EnumerableDev is ComposableTopDownERC1155Enumerable {

    uint256 public tokenCount = 0;

    function safeMint(address to) external virtual {
        unchecked {
            tokenCount++;
        }
        _safeMint(to, tokenCount, "");
    }
}
