# Composable Non-Fungible Tokens (cNFTs)

Based on https://github.com/mattlockyer/composables-998

## How to run?

### Prerequisites
[node.js](https://nodejs.org/en/) >= v12.2.0

[etherlime](https://github.com/LimeChain/etherlime) >= v2.3.4

For more information on `etherlime`, check [here](https://etherlime.gitbook.io/etherlime/).

```
npm install -g etherlime
```

### Clone repository
```
git clone https://github.com/limechain/hoard-exchange-erc998.git
```

### Install
```
cd hoard-exchange-erc-998
npm install
```

### Run ganache
```
etherlime ganache
```

### Compilation
```
etherlime compile --solcVersion=0.7.0 --runs 200
```

### Run Tests
```
etherlime test --skip-compilation --timeout 20000 --gas-report
```

### Run Tests with Coverage
``` 
etherlime coverage --solcVersion=0.7.0 --timeout 20000
```

## Gas Usages

### Composable to Composable
* `safeTransferChild(4)` ~ 86 505 gas
* `safeTransferChild(5)` ~ 92 204 gas
* `safeTransferFrom(4)` ~ 50 526 gas
* `transferERC20` ~ 64 790 gas
* `transferERC223` ~ 67 038 gas
* `transferFrom` ~ 44 914 gas

### ComposableTopDown to ComposableTopDown
* `safeTransferChild(4)` ~ 60 100 gas
* `safeTransferChild(5)` ~ 169 000 gas
* `safeTransferFrom(4)` ~ 207 007 gas
* `transferERC20` ~ 64 790 gas
* `transferERC223` ~ 112 149 gas

`NB!` Gas estimations include first-time storage allocation and storage deallocation.
