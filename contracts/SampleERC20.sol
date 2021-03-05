pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IERC223Receiver.sol";

contract SampleERC20 is ERC20 {
    using Address for address;

    constructor(string memory tokenName, string memory tokenSymbol)
        public
        ERC20(tokenName, tokenSymbol)
    {}

    function mint(address account, uint256 amount) public {
        super._mint(account, amount);
    }

    function transfer(
        address _to,
        uint256 _value,
        bytes memory _data
    ) external {
        _transfer(msg.sender, _to, _value);

        if (_to.isContract()) {
            // Require proper transaction handling.
            IERC223Receiver receiver = IERC223Receiver(_to);
            receiver.tokenFallback(msg.sender, _value, _data);
        }
    }
}
