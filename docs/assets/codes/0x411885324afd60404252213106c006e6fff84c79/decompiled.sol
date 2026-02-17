// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title            Decompiled Contract
/// @author           Jonathan Becker <jonathan@jbecker.dev>
/// @custom:version   heimdall-rs v0.9.2
///
/// @notice           This contract was decompiled using the heimdall-rs decompiler.
///                     It was generated directly by tracing the EVM opcodes from this contract.
///                     As a result, it may not compile or even be valid solidity code.
///                     Despite this, it should be obvious what each function does. Overall
///                     logic should have been preserved throughout decompiling.
///
/// @custom:github    You can find the open-source decompiler here:
///                       https://heimdall.rs

contract DecompiledContract {
    mapping(bytes32 => bytes32) storage_map_a;
    bool public isActive;
    mapping(bytes32 => bytes32) storage_map_e;
    uint256 public totalDeposits;
    mapping(bytes32 => bytes32) storage_map_d;
    
    event Event_381234db();
    event BatchTransferred(address, uint256);
    
    /// @custom:selector    0xf8b2cb4f
    /// @custom:signature   getBalance(address arg0) public view returns (uint256)
    /// @param              arg0 ["address", "uint160", "bytes20", "int160"]
    function getBalance(address arg0) public view returns (uint256) {
        require(arg0 == (address(arg0)));
        address var_a = address(arg0);
        var_b = 0x02;
        address var_c = storage_map_a[var_a];
        return storage_map_a[var_a];
    }
    
    /// @custom:selector    0xd0e30db0
    /// @custom:signature   deposit() public view
    function deposit() public view {
        require(bytes1(isActive / 0x010000000000000000000000000000000000000000), "Must send ETH");
        require(msg.value > 0, "Must send ETH");
        address var_a = address(msg.sender);
        var_b = 0x02;
        require(!(storage_map_a[var_a] > (storage_map_a[var_a] + msg.value)), "Must send ETH");
        var_a = 0x4e487b7100000000000000000000000000000000000000000000000000000000;
        var_c = 0x11;
        var_d = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        uint256 var_e = ((0x04 + var_f) + 0x20) - (0x04 + var_f);
        var_g = 0x0d;
        var_h = 0x4d7573742073656e642045544800000000000000000000000000000000000000;
        var_d = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_e = ((0x04 + var_f) + 0x20) - (0x04 + var_f);
        var_g = 0x0f;
        var_h = 0x5661756c74206973207061757365640000000000000000000000000000000000;
    }
    
    /// @custom:selector    0x29c68dc1
    /// @custom:signature   toggleActive() public
    function toggleActive() public {
        require(address(msg.sender) == (address(isActive / 0x01)), "Unauthorized");
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        uint256 var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0c;
        var_e = 0x556e617574686f72697a65640000000000000000000000000000000000000000;
        isActive = ((!bytes1(isActive / 0x010000000000000000000000000000000000000000)) * 0x010000000000000000000000000000000000000000) | (uint248(isActive));
        bytes1 var_a = !(!bytes1(isActive / 0x010000000000000000000000000000000000000000));
        emit Event_381234db(bytes1(isActive / 0x010000000000000000000000000000000000000000));
    }
    
    /// @custom:selector    0xed12e8ef
    /// @custom:signature   getVaultBalance() public view returns (uint256)
    function getVaultBalance() public view returns (uint256) {
        uint256 var_a = address(this).balance;
        return address(this).balance;
    }
    
    /// @custom:selector    0x27e235e3
    /// @custom:signature   balances(address arg0) public view returns (uint256)
    /// @param              arg0 ["address", "uint160", "bytes20", "int160"]
    function balances(address arg0) public view returns (uint256) {
        require(arg0 == (address(arg0)));
        var_a = 0x02;
        address var_b = arg0;
        address var_c = storage_map_d[var_b];
        return storage_map_d[var_b];
    }
    
    /// @custom:selector    0x2e1a7d4d
    /// @custom:signature   withdraw(uint256 arg0) public view
    /// @param              arg0 ["uint256", "bytes32", "int256"]
    function withdraw(uint256 arg0) public view {
        require(arg0 == arg0);
        require(bytes1(isActive / 0x010000000000000000000000000000000000000000), "Vault is paused");
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        uint256 var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0f;
        var_e = 0x5661756c74206973207061757365640000000000000000000000000000000000;
        require(arg0 > 0, "Insufficient balance");
        address var_f = address(msg.sender);
        var_g = 0x02;
        require(!(storage_map_e[var_f] < arg0), "Insufficient balance");
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x14;
        var_e = 0x496e73756666696369656e742062616c616e6365000000000000000000000000;
        var_f = address(msg.sender);
        var_g = 0x02;
        require(!((storage_map_e[var_f] - arg0) > storage_map_e[var_f]), "Amount must be > 0");
        var_f = 0x4e487b7100000000000000000000000000000000000000000000000000000000;
        var_h = 0x11;
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x12;
        var_e = 0x416d6f756e74206d757374206265203e20300000000000000000000000000000;
    }
    
    /// @custom:selector    0x88d695b2
    /// @custom:signature   batchTransfer(address[] arg0, uint256[] arg1) public view
    /// @param              arg0 ["uint256", "bytes32", "int256"]
    /// @param              arg1 ["uint256", "bytes32", "int256"]
    function batchTransfer(address[] arg0, uint256[] arg1) public view {
        require(!arg0 > 0xffffffffffffffff);
        require(!(arg0) > 0xffffffffffffffff);
        require(!arg1 > 0xffffffffffffffff);
        require(!(arg1) > 0xffffffffffffffff);
        require(address(msg.sender) == (address(isActive / 0x01)), "Unauthorized");
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        uint256 var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0c;
        var_e = 0x556e617574686f72697a65640000000000000000000000000000000000000000;
        require(bytes1(isActive / 0x010000000000000000000000000000000000000000), "Vault is paused");
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0f;
        var_e = 0x5661756c74206973207061757365640000000000000000000000000000000000;
        require(arg0 == (arg1), "Length mismatch");
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0f;
        var_e = 0x4c656e677468206d69736d617463680000000000000000000000000000000000;
        require(arg0 > 0);
        require(!0 < (arg0));
        require(0 < (arg1));
        require((0 + (arg1 + 0x20)) > 0);
        require(0 < (arg0));
        require(!(((0 + ((0x04 + arg0) + 0x20)) + 0x20) - (0 + ((0x04 + arg0) + 0x20))) < 0x20);
        require(((0 + (arg0 + 0x20)) + 0) == (address((0 + (arg0 + 0x20)) + 0)));
        require(address((0 + (arg0 + 0x20)) + 0) - 0, "Zero address");
        require(0 < (arg0), "Zero address");
        var_f = 0x4e487b7100000000000000000000000000000000000000000000000000000000;
        var_g = 0x32;
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0c;
        var_e = 0x5a65726f20616464726573730000000000000000000000000000000000000000;
        var_f = 0x4e487b7100000000000000000000000000000000000000000000000000000000;
        var_g = 0x32;
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0b;
        var_e = 0x5a65726f20616d6f756e74000000000000000000000000000000000000000000;
        var_f = 0x4e487b7100000000000000000000000000000000000000000000000000000000;
        var_g = 0x32;
        uint256 var_a = (arg0);
        emit BatchTransferred(address(msg.sender), (arg0));
        var_a = 0x08c379a000000000000000000000000000000000000000000000000000000000;
        var_b = ((0x04 + var_c) + 0x20) - (0x04 + var_c);
        var_d = 0x0c;
        var_e = 0x456d707479206172726179730000000000000000000000000000000000000000;
    }
}