# Account Abstraction

- [Account Abstraction](#account-abstraction)
  - [What is Account Abstraction?](#what-is-account-abstraction)
  - [What's this repo show?](#whats-this-repo-show)
  - [What does this repo not show?](#what-does-this-repo-not-show)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Installation](#installation)
- [Quickstart](#quickstart)
  - [Vanilla Foundry](#vanilla-foundry)
    - [Deploy](#deploy)
    - [User operation - Arbitrum](#user-operation-interactions)

## What is Account Abstraction?

EoAs are now smart contracts. That's all account abstraction is.

But what does that mean?

Right now, every single transaction in web3 stems from a single private key. 

> account abstraction means that not only the execution of a transaction can be arbitrarily complex computation logic as specified by the EVM, but also the authorization logic.

- [Vitalik Buterin](https://ethereum-magicians.org/t/implementing-account-abstraction-as-part-of-eth1-x/4020)
- [EntryPoint Contract v0.6](https://etherscan.io/address/0x5ff137d4b0fdcd49dca30c7cf57e578a026d2789)
- [EntryPoint Contract v0.7](https://etherscan.io/address/0x0000000071727De22E5E9d8BAf0edAc6f37da032)

## What's this repo show?

1. A minimal EVM "Smart Wallet" using alt-mempool AA
   1. We even send a transactoin to the `EntryPoint.sol`

## What does this repo not show?

1. Sending your userop to the alt-mempool 
   1. You can learn how to do this via the [alchemy docs](https://alchemy.com/?a=673c802981)

# Getting Started 

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`
- [foundry-zksync](https://github.com/matter-labs/foundry-zksync)
  - You'll know you did it right if you can run `forge-zksync --help` and you see `zksync` somewhere in the output

## Installation

```bash
git clone https://github.com/GHexxerBrdv/EIP-4337-AA.git
cd EIP-4337-AA
forge build
```

# Quickstart 

## Vanilla Foundry

```bash
foundryup
forge test
```

### Deploy

This project of Account Abstraction will perform operatios on Token smart contract in `src` folder. If you have your own token deployed on anychain then just replace address of the target in `/script/HelperConfig.s.sol` like following.

```javascript
return NetworkConfig({
    .....
@>  target: 0x6b233dd6d07177824634f839BB692373A76404eB,
    .....
});
```

make sure you have made `.env` file and save your wallet privatekey and rpc-url for test network.

```bash
source .env
```

Deploy token contract. Here Polygon amoy is used for all the deployment.

```bash
forge script script/Token.s.sol --rpc-url $POLY --broadcast
```

after deploying token on test chain grab the deployment address and update the target address in `/script/HelperConfig.s.sol` shown above.

Now, Let's deploy our smart contract account.run the following command

```bash
forge script script/EIP4337AA.s.sol --rpc-url $POLY --private-key $PRIV --broadcast
```
### User operation (Interactions)
Now interact with deployed smart contract account by using `/script/signedPackedUSerOperations.s.sol`.

1. Fund the smart account.

```bash
forge script script/signedPackedUSerOperations.s.sol:fundAA --rpc-url $POLY --private-key $PRIV --broadcast
```

2. interact with smart account.

```bash
forge script script/signedPackedUSerOperations.s.sol:signedPackedUSerOperations --rpc-url $POLY --private-key $PRIV --broadcast
```

