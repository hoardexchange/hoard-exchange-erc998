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

### Compilation
```
etherlime compile --solcVersion=0.7.0 --runs 200
```

### Run Tests
```
etherlime test --skip-compilation --timeout 10000 --gas-report
```

### Run Tests with Coverage
``` 
etherlime coverage --solcVersion=0.7.0 --timeout 10000
```
