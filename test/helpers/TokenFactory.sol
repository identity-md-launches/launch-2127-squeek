// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekToken} from "../../src/SqueekToken.sol";

/// @dev Test fixture for an immediate deployer distinct from the transaction origin.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (SqueekToken) {
        return new SqueekToken{salt: salt}();
    }
}

/// @dev An ERC-20 transfer must not invoke recipient code.
contract RejectingRecipient {
    fallback() external {
        revert("unexpected callback");
    }
}
