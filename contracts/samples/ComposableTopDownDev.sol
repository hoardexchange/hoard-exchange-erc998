// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "../ComposableTopDown.sol";


contract ComposableTopDownDev is ComposableTopDown {

    uint256 public tokenCount = 0;

    function safeMint(address to) external virtual {
        unchecked {
            tokenCount++;
        }
        _safeMint(to, tokenCount, "");
    }
}
