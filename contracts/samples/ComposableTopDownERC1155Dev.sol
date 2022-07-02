// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "../ComposableTopDownERC1155.sol";


contract ComposableTopDownERC1155Dev is ComposableTopDownERC1155 {

    uint256 public tokenCount = 0;

    function safeMint(address to) external virtual {
        unchecked {
            tokenCount++;
        }
        _safeMint(to, tokenCount, "");
    }
}
