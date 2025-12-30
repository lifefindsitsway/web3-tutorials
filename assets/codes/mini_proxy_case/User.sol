// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice 用 “Logic 的 ABI” 去调用 Proxy
interface ILogic {
    function setValue(uint256 newValue) external returns (bool);
    function value() external view returns (uint256);
}

/// @notice 用户合约：模拟 “用户 -> Proxy -> fallback -> delegatecall -> 写 Proxy storage” 的完整流程
contract User {
    event DebugCalldata(bytes returnData);
    event DebugReturn(bool success, bytes returnData);

    /// @dev 低级调用 Proxy：让它必然触发 fallback(bytes)
    function callSetValueViaProxy(address proxy, uint256 newValue) 
        public
        returns (bool success, bytes memory returnData, bool decodedBool) 
    {
        // 1) 构造 calldata: selector + ABI(newValue)
        bytes memory data = abi.encodeCall(ILogic.setValue, (newValue));
        emit DebugCalldata(data);
        
        // 2) Proxy 没有 setValue 函数 -> 命中 fallback(bytes)
        // 3) fallback 内部 sload IMPLEMENTATION_SLOT 取 impl
        // 4) fallback 内部 delegatecall(data) 转发到 Logic
        (success, returnData) = proxy.call(data);
        emit DebugReturn(success, returnData);

        require(success, "proxy.call failed");

        // 5) setValue 返回 bool，returnData 里会包含 ABI 编码后的返回值
        decodedBool = abi.decode(returnData, (bool));
    }

    /// @notice 演示函数：一次性跑完，并对比 Proxy 和 Logic 的 value
    /// @param proxy 你的 SimpleProxy 合约地址
    /// @param logic 你的 Logic 合约地址（用于对比：它自己的 storage 是否变化）
    /// @param newValue 要设置的新值
    /// @return proxyValue 通过 Proxy 读取到的 value（应当等于 newValue）
    /// @return logicValue 直接读取 Logic 合约的 value（通常仍为 0，除非你直接调用过 Logic）
    /// @return returnedBool setValue 的返回值（应为 true）
    function demo(address proxy, address logic, uint256 newValue) 
        public
        returns (uint256 proxyValue, uint256 logicValue, bool returnedBool)
    {
        // 发起 “用户 -> Proxy -> delegatecall -> Logic 代码” 的调用
        (, , returnedBool) = callSetValueViaProxy(proxy, newValue);

        // 证明：delegatecall 把 value 写进了 Proxy 的 slot 0
        // 这里用 Logic 的 ABI 去读 Proxy：Proxy 没有 value()，仍会走 fallback -> delegatecall 到 Logic 的 getter
        proxyValue = ILogic(proxy).value();

        // 对比：Logic 自己的 storage 通常不会变（因为前面是 delegatecall，不是 call）
        logicValue = ILogic(logic).value();
    }

    /// @notice 可选：直接调用 Logic（不经过 Proxy），用于对比行为
    function callSetValueDirectlyOnLogic(address logic, uint256 newValue) public returns (bool) {
        return ILogic(logic).setValue(newValue);
    }
}