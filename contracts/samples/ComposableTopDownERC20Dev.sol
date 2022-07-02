// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "../ComposableTopDownERC20.sol";


contract ComposableTopDownERC20Dev is ComposableTopDownERC20 {

    uint256 public tokenCount = 0;

    function safeMint(address to) external virtual {
        unchecked {
            tokenCount++;
        }
        _safeMint(to, tokenCount, "");
    }
}
