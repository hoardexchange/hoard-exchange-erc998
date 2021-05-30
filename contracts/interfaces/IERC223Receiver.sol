// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IERC223Receiver {
  /**
   * @dev Standard ERC223 function that will handle incoming token transfers.
   *
   * @param _from  Token sender address.
   * @param _value Amount of tokens.
   * @param _data  Transaction metadata.
   */
  function tokenFallback(address _from, uint _value, bytes memory _data) external;
}