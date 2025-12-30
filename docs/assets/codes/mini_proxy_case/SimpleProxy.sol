// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract SimpleProxy {
    bytes32 private constant IMPLEMENTATION_SLOT = 
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address _implementation) {
        assembly {
            sstore(IMPLEMENTATION_SLOT, _implementation)
        }
    }

    fallback(bytes calldata data) external payable returns (bytes memory) {
        address impl;
        assembly {
            impl := sload(IMPLEMENTATION_SLOT)
        }

        (bool success, bytes memory result) = impl.delegatecall(data);
        require(success, "Delegatecall failed");
        return result;
    }
}