// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract SampleERC1155 is ERC1155 {
    using Address for address;

    constructor(string memory uri_)
        public
        ERC1155(uri_)
    {}

    function mint(address account, uint256 id, uint256 amount) public {
        super._mint(account, id, amount, "");
    }

}
